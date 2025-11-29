## Repair Queue Management
##
## Handles automatic extraction of crippled ships from fleets and submission
## to repair queues at colonies with shipyard/spaceport capacity.
##
## Design:
## - Fleets with crippled ships at colonies automatically submit repair requests
## - Ships extracted from squadrons → repair queue (1 turn, 25% cost)
## - Repaired ships recommission through standard pipeline (squadron → fleet)
## - Construction projects take precedence over repairs for dock capacity

import std/[tables, options, strformat]
import ../gamestate
import ../fleet
import ../squadron
import ../logger
import types as econ_types
import ../../common/types/[core, units]

export econ_types.RepairProject, econ_types.FacilityType, econ_types.RepairTargetType

proc calculateRepairCost*(shipClass: ShipClass): int =
  ## Calculate repair cost for a ship
  ## Per economy.md:5.4 - All repairs require shipyards, cost is 25% of build cost
  let stats = getShipStats(shipClass)
  result = (stats.buildCost.float * 0.25).int

proc extractCrippledShip*(state: var GameState, fleetId: FleetId,
                         squadronIdx: int, shipIdx: int): Option[RepairProject] =
  ## Extract a crippled ship from a fleet squadron and create repair project
  ## shipIdx: -1 for flagship, 0+ for escorts
  ## Returns None if extraction fails

  if fleetId notin state.fleets:
    return none(RepairProject)

  var fleet = state.fleets[fleetId]

  if squadronIdx < 0 or squadronIdx >= fleet.squadrons.len:
    return none(RepairProject)

  var squadron = fleet.squadrons[squadronIdx]

  # Extract ship based on index
  var shipClass: ShipClass
  var isCrippled: bool

  if shipIdx == -1:
    # =========================================================================
    # FLAGSHIP EXTRACTION FOR REPAIR
    # =========================================================================
    # Flagships are the command ships that hold squadrons together. When a
    # crippled flagship needs repair, we must handle the squadron appropriately.
    #
    # Per operations.md:6.5.2, all crippled ships must be repairable.
    # However, flagships cannot simply be removed like escort ships.
    #
    # STRATEGY:
    # - Case 1: Squadron has escorts → Promote strongest escort to new flagship
    # - Case 2: Squadron has no escorts → Dissolve squadron entirely
    #
    # This ensures:
    # - All crippled ships can be repaired (no stranded crippled flagships)
    # - Squadrons remain valid (always have a flagship or are removed)
    # - Empty fleets are cleaned up (no orphaned fleet structures)
    # =========================================================================

    shipClass = squadron.flagship.shipClass
    isCrippled = squadron.flagship.isCrippled

    if not isCrippled:
      return none(RepairProject)

    if squadron.ships.len > 0:
      # -----------------------------------------------------------------------
      # CASE 1: SQUADRON HAS ESCORTS - PROMOTE TO FLAGSHIP
      # -----------------------------------------------------------------------
      # When the squadron has escort ships, we promote the strongest escort
      # to become the new flagship. This preserves the squadron structure.
      #
      # Selection criteria: Highest combined AS + DS (combat effectiveness)
      # The old flagship is extracted for repair.
      # -----------------------------------------------------------------------

      var bestEscortIdx = 0
      var bestStrength = 0
      for i, ship in squadron.ships:
        let strength = ship.stats.attackStrength + ship.stats.defenseStrength
        if strength > bestStrength:
          bestStrength = strength
          bestEscortIdx = i

      # Promote escort to flagship position
      squadron.flagship = squadron.ships[bestEscortIdx]
      squadron.ships.delete(bestEscortIdx)
      fleet.squadrons[squadronIdx] = squadron
      state.fleets[fleetId] = fleet

      logInfo(LogCategory.lcEconomy,
              &"Promoted escort to flagship in squad-{squadron.id} (old flagship sent for repair)")
    else:
      # -----------------------------------------------------------------------
      # CASE 2: SQUADRON HAS NO ESCORTS - DISSOLVE SQUADRON
      # -----------------------------------------------------------------------
      # When the squadron has no escorts (single-flagship squadron), we must
      # dissolve the squadron entirely. The flagship goes to repair, and the
      # squadron structure is removed from the fleet.
      #
      # This also triggers EMPTY FLEET CLEANUP if this was the last squadron.
      # -----------------------------------------------------------------------

      var updatedSquadrons: seq[Squadron] = @[]
      for i, sq in fleet.squadrons:
        if i != squadronIdx:
          updatedSquadrons.add(sq)

      fleet.squadrons = updatedSquadrons

      # EMPTY FLEET CLEANUP
      # If removing this squadron leaves the fleet empty (no squadrons AND no spacelift ships),
      # delete the fleet entirely along with its associated orders.
      if fleet.isEmpty():
        state.fleets.del(fleetId)
        # Clean up associated orders to prevent orphaned data
        if fleetId in state.fleetOrders:
          state.fleetOrders.del(fleetId)
        if fleetId in state.standingOrders:
          state.standingOrders.del(fleetId)

        logInfo(LogCategory.lcEconomy,
                &"Dissolved squadron {squadron.id} and removed empty fleet-{fleetId} (flagship sent for repair)")
      else:
        state.fleets[fleetId] = fleet

        logInfo(LogCategory.lcEconomy,
                &"Dissolved squadron {squadron.id} from fleet-{fleetId} (flagship sent for repair)")
  else:
    # Escort
    if shipIdx < 0 or shipIdx >= squadron.ships.len:
      return none(RepairProject)

    let ship = squadron.ships[shipIdx]
    shipClass = ship.shipClass
    isCrippled = ship.isCrippled

    if not isCrippled:
      return none(RepairProject)

    # Remove escort from squadron
    squadron.ships.delete(shipIdx)
    fleet.squadrons[squadronIdx] = squadron
    state.fleets[fleetId] = fleet

  # Create repair project (shipyards only)
  let cost = calculateRepairCost(shipClass)

  let repair = RepairProject(
    targetType: econ_types.RepairTargetType.Ship,
    facilityType: econ_types.FacilityType.Shipyard,
    fleetId: some(fleetId),
    squadronIdx: some(squadronIdx),
    shipIdx: some(shipIdx),
    starbaseIdx: none(int),
    shipClass: some(shipClass),
    cost: cost,
    turnsRemaining: 1,
    priority: 1  # Ship repairs = priority 1 (construction = 0, starbase = 2)
  )

  logInfo(LogCategory.lcEconomy,
          &"Extracted crippled {shipClass} from fleet-{fleetId} squad-{squadronIdx} " &
          &"for repair (cost: {cost} PP, shipyard only)")

  return some(repair)

proc submitAutomaticStarbaseRepairs*(state: var GameState, systemId: SystemId) =
  ## Automatically submit repair requests for crippled starbases at colony
  ## Starbases always use shipyard facilities (priority 2, lower than ship repairs)

  if systemId notin state.colonies:
    return

  var colony = state.colonies[systemId]

  # Check if colony has shipyard (starbases require shipyard, not spaceport)
  let shipyardCapacity = colony.getShipyardDockCapacity()
  if shipyardCapacity == 0:
    return  # No shipyard available

  # Submit repairs for crippled starbases
  for idx, starbase in colony.starbases:
    if starbase.isCrippled:
      # Check if shipyard has capacity
      let activeProjects = colony.getActiveProjectsByFacility(econ_types.FacilityType.Shipyard)
      if activeProjects >= shipyardCapacity:
        logDebug(LogCategory.lcEconomy,
                 &"Colony-{systemId} has no shipyard capacity for starbase repair " &
                 &"({activeProjects}/{shipyardCapacity} docks used)")
        continue  # No capacity, skip this starbase

      # Calculate repair cost (25% of starbase build cost)
      # TODO: Get actual starbase build cost from config (for now use estimate)
      let starbaseBuildCost = 100  # Placeholder - starbases are expensive
      let repairCost = (starbaseBuildCost.float * 0.25).int

      let repair = RepairProject(
        targetType: econ_types.RepairTargetType.Starbase,
        facilityType: econ_types.FacilityType.Shipyard,
        fleetId: none(FleetId),
        squadronIdx: none(int),
        shipIdx: none(int),
        starbaseIdx: some(idx),
        shipClass: none(ShipClass),
        cost: repairCost,
        turnsRemaining: 1,
        priority: 2  # Starbase repairs = priority 2 (lowest)
      )

      colony.repairQueue.add(repair)
      logInfo(LogCategory.lcEconomy,
              &"Submitted repair for starbase-{starbase.id} at colony-{systemId} " &
              &"(cost: {repairCost} PP, shipyard)")

  # Update colony state
  state.colonies[systemId] = colony

proc submitAutomaticRepairs*(state: var GameState, systemId: SystemId) =
  ## Automatically submit repair requests for fleets with crippled ships at this colony
  ## Per economy.md:5.4 - Ship repairs require shipyards (spaceports cannot repair)
  ## Called during turn resolution after fleet movements

  if systemId notin state.colonies:
    return

  var colony = state.colonies[systemId]

  # Check if colony has shipyard (required for all ship repairs)
  let hasShipyard = colony.shipyards.len > 0

  if not hasShipyard:
    return  # No shipyard = no repairs

  # Submit starbase repairs first (they have lower priority but same facility)
  submitAutomaticStarbaseRepairs(state, systemId)

  # Reload colony after starbase repairs submitted
  colony = state.colonies[systemId]

  # Find all fleets at this colony
  var fleetsAtColony: seq[FleetId] = @[]
  for fleetId, fleet in state.fleets:
    if fleet.location == systemId and fleet.owner == colony.owner:
      fleetsAtColony.add(fleetId)

  # Process each fleet, extracting crippled ships
  for fleetId in fleetsAtColony:
    let fleet = state.fleets[fleetId]

    # Check each squadron for crippled escorts (skip flagships for now)
    for squadronIdx in 0..<fleet.squadrons.len:
      let squadron = fleet.squadrons[squadronIdx]

      # Check escorts
      for shipIdx in 0..<squadron.ships.len:
        let ship = squadron.ships[shipIdx]
        if ship.isCrippled:
          # Check if shipyard has capacity for this repair
          let activeProjects = colony.getActiveProjectsByFacility(econ_types.FacilityType.Shipyard)
          let capacity = colony.getShipyardDockCapacity()

          if activeProjects >= capacity:
            logDebug(LogCategory.lcEconomy,
                     &"Colony-{systemId} has no shipyard capacity for repair " &
                     &"({activeProjects}/{capacity} docks used)")
            continue  # No capacity, skip this ship

          # Extract and add to repair queue
          let repairOpt = state.extractCrippledShip(fleetId, squadronIdx, shipIdx)
          if repairOpt.isSome:
            colony.repairQueue.add(repairOpt.get())
            logInfo(LogCategory.lcEconomy,
                    &"Submitted repair for {ship.shipClass} from fleet-{fleetId} " &
                    &"to colony-{systemId} shipyard")

  # Update colony state
  state.colonies[systemId] = colony
