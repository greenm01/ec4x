## Repair Queue Management
##
## Handles automatic extraction of crippled ships from fleets and submission
## to repair queues at colonies with drydock capacity.
##
## Design:
## - Fleets with crippled ships at colonies automatically submit repair requests
## - Ships extracted from squadrons → repair queue (1 turn, 25% cost)
## - Repaired ships recommission through standard pipeline (squadron → fleet)
## - Drydocks are repair-only facilities (10 docks each)
## - Shipyards are construction-only facilities (clean separation of concerns)

import std/[tables, options, strformat, sequtils]
import ../../types/[game_state, core, ship, production, facilities]
import ../../systems/ship/entity as ship_entity # Ship helper functions
import ../../entities/[fleet_ops, colony_ops]
import ../../../common/logger

export production.RepairProject, facilities.FacilityType, production.RepairTargetType

proc calculateRepairCost*(shipClass: ShipClass): int =
  ## Calculate repair cost for a ship
  ## Per economy.md:5.4 - All repairs require drydocks, cost is 25% of build cost
  let ship = ship_entity.newShip(shipClass)
  result = (ship.buildCost().float * 0.25).int

proc extractCrippledShip*(
    state: var GameState, fleetId: FleetId, squadronId: SquadronId, shipId: ShipId
): Option[production.RepairProject] =
  ## Extract a crippled ship from a fleet squadron and create repair project
  ## Works with entity IDs for DoD compliance
  ## Returns None if extraction fails

  # Look up fleet using entity manager
  if fleetId notin state.fleets.entities.index:
    return none(RepairProject)

  let fleetIdx = state.fleets.entities.index[fleetId]
  var fleet = state.fleets.entities.data[fleetIdx]

  # Verify squadron is in fleet
  if squadronId notin fleet.squadrons:
    return none(RepairProject)

  # Look up squadron using entity manager
  if squadronId notin state.squadrons.entities.index:
    return none(RepairProject)

  let squadronIdx = state.squadrons.entities.index[squadronId]
  var squadron = state.squadrons.entities.data[squadronIdx]

  # Look up the ship being extracted
  if shipId notin state.ships.entities.index:
    return none(RepairProject)

  let shipIdx = state.ships.entities.index[shipId]
  let ship = state.ships.entities.data[shipIdx]

  if not ship.isCrippled:
    return none(RepairProject)

  let shipClass = ship.shipClass
  let isFlagship = (shipId == squadron.flagshipId)

  if isFlagship:
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

      var bestEscortId: ShipId
      var bestStrength = 0

      for escortId in squadron.ships:
        if escortId notin state.ships.entities.index:
          continue
        let escortIdx = state.ships.entities.index[escortId]
        let escort = state.ships.entities.data[escortIdx]
        let strength = escort.stats.attackStrength + escort.stats.defenseStrength
        if strength > bestStrength:
          bestStrength = strength
          bestEscortId = escortId

      # Promote escort to flagship position
      squadron.flagshipId = bestEscortId
      squadron.ships = squadron.ships.filterIt(it != bestEscortId)

      # Write back modified squadron
      state.squadrons.entities.data[state.squadrons.entities.index[squadronId]] =
        squadron

      logInfo(
        "Repair", "Promoted escort to flagship (old flagship sent for repair)",
        "squadronId=", squadron.id,
      )
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

      # Remove squadron from fleet
      fleet.squadrons = fleet.squadrons.filterIt(it != squadronId)

      # EMPTY FLEET CLEANUP
      # If removing this squadron leaves the fleet empty (no squadrons remaining),
      # delete the fleet entirely using fleet_ops.
      if fleet.squadrons.len == 0:
        destroyFleet(state, fleetId)
        logInfo(
          "Repair",
          "Dissolved squadron and removed empty fleet (flagship sent for repair)",
          "squadronId=", squadron.id, " fleetId=", fleetId,
        )
      else:
        # Write back modified fleet
        state.fleets.entities.data[fleetIdx] = fleet
        logInfo(
          "Repair", "Dissolved squadron from fleet (flagship sent for repair)",
          "squadronId=", squadron.id, " fleetId=", fleetId,
        )
  else:
    # Escort extraction
    if shipId notin squadron.ships:
      return none(RepairProject)

    # Remove escort from squadron
    squadron.ships = squadron.ships.filterIt(it != shipId)

    # Write back modified squadron
    state.squadrons.entities.data[state.squadrons.entities.index[squadronId]] = squadron

  # Create repair project (drydocks only)
  let cost = calculateRepairCost(shipClass)

  # Create repair project
  let repair = production.RepairProject(
    targetType: production.RepairTargetType.Ship,
    facilityType: facilities.FacilityType.Drydock, # Drydocks only
    fleetId: some(fleetId),
    squadronId: some(squadronId),
    shipId: some(shipId),
    starbaseId: none(StarbaseId),
    shipClass: some(shipClass),
    cost: cost.int32,
    turnsRemaining: 1,
    priority: 1, # Ship repairs = priority 1 (construction = 0, starbase = 2)
  )

  logInfo(
    "Repair", "Extracted crippled ship for repair", "shipClass=", shipClass,
    " fleetId=", fleetId, " squadronId=", squadronId, " cost=", cost,
    " facilityType=Drydock",
  )

  return some(repair)

proc submitAutomaticStarbaseRepairs*(state: var GameState, systemId: SystemId) =
  ## Automatically submit repair requests for crippled starbases at colony
  ## Starbases use spaceport facilities and do NOT consume dock space
  ## Per architecture: Starbases are facilities that require Spaceports

  if systemId notin state.colonies.bySystem:
    return

  let colonyId = state.colonies.bySystem[systemId]
  if colonyId notin state.colonies.entities.index:
    return

  let colonyIdx = state.colonies.entities.index[colonyId]
  var colony = state.colonies.entities.data[colonyIdx]

  # Check if colony has spaceport (starbases require spaceport for repair)
  let spaceportCount = colony.spaceports.len
  if spaceportCount == 0:
    return # No spaceport available

  # Submit repairs for crippled starbases
  # Note: Starbases do NOT consume dock capacity (they are facilities, not ships)
  for starbase in colony.starbases:
    if starbase.isCrippled:
      # Calculate repair cost (25% of starbase build cost)
      # TODO: Get actual starbase build cost from config (for now use estimate)
      let starbaseBuildCost = 300 # From facilities.toml
      let repairCost = (starbaseBuildCost.float * 0.25).int

      let repair = production.RepairProject(
        targetType: production.RepairTargetType.Starbase,
        facilityType: facilities.FacilityType.Spaceport, # Use Spaceport, not Shipyard
        fleetId: none(FleetId),
        squadronId: none(SquadronId),
        shipId: none(ShipId),
        starbaseId: some(starbase.id),
        shipClass: none(ShipClass),
        cost: repairCost,
        turnsRemaining: 1,
        priority: 2, # Starbase repairs = priority 2 (lowest)
      )

      colony.repairQueue.add(repair)
      logInfo(
        "Repair", "Submitted repair for starbase", "starbaseId=", starbase.id,
        " systemId=", systemId, " cost=", repairCost, " facilityType=Spaceport",
      )

  # Write back modified colony
  state.colonies.entities.data[colonyIdx] = colony

proc submitAutomaticRepairs*(state: var GameState, systemId: SystemId) =
  ## Automatically submit repair requests for fleets with crippled ships at this colony
  ## Ship repairs require drydocks (spaceports and shipyards cannot repair)
  ## Called during turn resolution after fleet movements

  if systemId notin state.colonies.bySystem:
    return

  let colonyId = state.colonies.bySystem[systemId]
  if colonyId notin state.colonies.entities.index:
    return

  let colonyIdx = state.colonies.entities.index[colonyId]
  var colony = state.colonies.entities.data[colonyIdx]

  # Check if colony has drydock (required for all ship repairs)
  let hasDrydock = colony.drydocks.len > 0

  if not hasDrydock:
    return # No drydock = no repairs

  # Submit starbase repairs first (they have lower priority but same facility)
  submitAutomaticStarbaseRepairs(state, systemId)

  # Reload colony after starbase repairs submitted
  colony = state.colonies.entities.data[colonyIdx]

  # Find all fleets at this colony using entity manager
  var fleetsAtColony: seq[FleetId] = @[]
  for fleetId, fleet in state.fleets.entities.data:
    if fleet.location == systemId and fleet.owner == colony.owner:
      fleetsAtColony.add(fleetId)

  # Process each fleet, extracting crippled ships
  for fleetId in fleetsAtColony:
    if fleetId notin state.fleets.entities.index:
      continue

    let fleetIdx = state.fleets.entities.index[fleetId]
    let fleet = state.fleets.entities.data[fleetIdx]

    # Check each squadron for crippled ships
    for squadronId in fleet.squadrons:
      if squadronId notin state.squadrons.entities.index:
        continue

      let squadronIdx = state.squadrons.entities.index[squadronId]
      let squadron = state.squadrons.entities.data[squadronIdx]

      # Check flagship
      if squadron.flagshipId in state.ships.entities.index:
        let flagshipIdx = state.ships.entities.index[squadron.flagshipId]
        let flagship = state.ships.entities.data[flagshipIdx]
        if flagship.isCrippled:
          # Check drydock capacity
          let drydockProjects =
            colony.getActiveProjectsByFacility(facilities.FacilityType.Drydock)
          let drydockCapacity = colony.getDrydockDockCapacity()

          if drydockProjects < drydockCapacity:
            # Extract and add to repair queue
            let repairOpt =
              state.extractCrippledShip(fleetId, squadronId, squadron.flagshipId)
            if repairOpt.isSome:
              colony.repairQueue.add(repairOpt.get())
              logInfo(
                "Repair",
                "Submitted repair for flagship",
                shipClass = flagship.shipClass,
                fleetId = fleetId,
                systemId = systemId,
              )
          else:
            logDebug(
              "Repair",
              "Colony has no drydock capacity",
              systemId = systemId,
              used = drydockProjects,
              capacity = drydockCapacity,
            )

      # Check escorts
      for shipId in squadron.ships:
        if shipId notin state.ships.entities.index:
          continue

        let shipIdx = state.ships.entities.index[shipId]
        let ship = state.ships.entities.data[shipIdx]

        if ship.isCrippled:
          # Check drydock capacity
          let drydockProjects =
            colony.getActiveProjectsByFacility(facilities.FacilityType.Drydock)
          let drydockCapacity = colony.getDrydockDockCapacity()

          if drydockProjects < drydockCapacity:
            # Extract and add to repair queue
            let repairOpt = state.extractCrippledShip(fleetId, squadronId, shipId)
            if repairOpt.isSome:
              colony.repairQueue.add(repairOpt.get())
              logInfo(
                "Repair",
                "Submitted repair for escort",
                shipClass = ship.shipClass,
                fleetId = fleetId,
                systemId = systemId,
              )
          else:
            logDebug(
              "Repair",
              "Colony has no drydock capacity",
              systemId = systemId,
              used = drydockProjects,
              capacity = drydockCapacity,
            )

  # Write back modified colony
  state.colonies.entities.data[colonyIdx] = colony
