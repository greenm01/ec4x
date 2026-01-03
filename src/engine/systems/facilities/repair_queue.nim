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
import ../../types/[core, ship, production, facilities]
import ../../systems/ship/entity as ship_entity # Ship helper functions
import ../../entities/fleet_ops
import ../../../common/logger

export production.RepairProject, facilities.FacilityClass, production.RepairTargetType

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
  let fleetOpt = state.mFleet(fleetId)
  if fleetOpt.isNone:
    return none(RepairProject)
  var fleet = fleetOpt.get()

  # Verify squadron is in fleet
  if squadronId notin fleet.squadrons:
    return none(RepairProject)

  # Look up squadron using entity manager
  let squadronOpt = state.mSquadron(squadronId)
  if squadronOpt.isNone:
    return none(RepairProject)
  var squadron = squadronOpt.get()

  # Look up the ship being extracted
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return none(RepairProject)
  let ship = shipOpt.get()

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
        let escortOpt = state.ship(escortId)
        if escortOpt.isNone:
          continue
        let escort = escortOpt.get()
        let strength = escort.stats.attackStrength + escort.stats.defenseStrength
        if strength > bestStrength:
          bestStrength = strength
          bestEscortId = escortId

      # Promote escort to flagship position
      squadron.flagshipId = bestEscortId
      squadron.ships = squadron.ships.filterIt(it != bestEscortId)

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

  # Create repair project (drydocks only)
  let cost = calculateRepairCost(shipClass)

  # Create repair project
  let repair = production.RepairProject(
    targetType: production.RepairTargetType.Ship,
    facilityType: facilities.FacilityClass.Drydock, # Drydocks only
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

  let colonyIdOpt = state.colonies.bySystem.getOrDefault(systemId)
  if colonyIdOpt.isNone:
    return

  let colonyId = colonyIdOpt.get()
  let colonyOpt = state.mColony(colonyId)
  if colonyOpt.isNone:
    return
  var colony = colonyOpt.get()

  # Check if colony has spaceport (starbases require spaceport for repair)
  # Note: This logic assumes 'spaceports' is a field in Colony type.
  # If spaceports are now Neorias, this needs to be adapted to count Neorias of type Spaceport.
  # For now, keeping as is, assuming colony.spaceports is still a thing for legacy reasons or internal tracking.
  # TODO: Revisit if Colony.spaceports changes due to Neoria/Kastra migration.
  # The type `facilities.FacilityClass.Spaceport` indicates a `NeoriaClass.Spaceport` for repair.
  var hasSpaceport = false
  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome and neoriaOpt.get().neoriaClass == NeoriaClass.Spaceport:
      hasSpaceport = true
      break
  if not hasSpaceport:
    return # No spaceport available

  # Submit repairs for crippled starbases
  # Note: Starbases do NOT consume dock capacity (they are facilities, not ships)
  # TODO: Iterate over actual Kastra objects for starbases.
  # This currently assumes 'starbases' is a field in Colony type, which might be a legacy structure.
  for kastraId in colony.kastraIds:
    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isNone:
      continue
    let kastra = kastraOpt.get()
    if kastra.isCrippled:
      # Calculate repair cost (25% of starbase build cost)
      # TODO: Get actual starbase build cost from config (for now use estimate)
      let starbaseBuildCost = 300 # From facilities.toml
      let repairCost = (starbaseBuildCost.float * 0.25).int

      let repair = production.RepairProject(
        targetType: production.RepairTargetType.Starbase,
        facilityType: facilities.FacilityClass.Spaceport, # Use Spaceport, not Shipyard
        fleetId: none(FleetId),
        squadronId: none(SquadronId),
        shipId: none(ShipId),
        starbaseId: some(kastra.id),
        shipClass: none(ShipClass),
        cost: repairCost,
        turnsRemaining: 1,
        priority: 2, # Starbase repairs = priority 2 (lowest)
      )

      colony.repairQueue.add(repair)
      logInfo(
        "Repair", "Submitted repair for starbase", "starbaseId=", kastra.id,
        " systemId=", systemId, " cost=", repairCost, " facilityType=Spaceport",
      )

proc submitAutomaticRepairs*(state: var GameState, systemId: SystemId) =
  ## Automatically submit repair requests for fleets with crippled ships at this colony
  ## Ship repairs require drydocks (spaceports and shipyards cannot repair)
  ## Called during turn resolution after fleet movements

  let colonyIdOpt = state.colonies.bySystem.getOrDefault(systemId)
  if colonyIdOpt.isNone:
    return

  let colonyId = colonyIdOpt.get()
  let colonyOpt = state.mColony(colonyId)
  if colonyOpt.isNone:
    return
  var colony = colonyOpt.get()

  # Check if colony has drydock (required for all ship repairs)
  var hasDrydock = false
  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome and neoriaOpt.get().neoriaClass == NeoriaClass.Drydock:
      hasDrydock = true
      break
  if not hasDrydock:
    return # No drydock = no repairs

  # Submit starbase repairs first (they have lower priority but same facility)
  submitAutomaticStarbaseRepairs(state, systemId)

  # Reload colony after starbase repairs submitted (it might have been modified)
  colony = state.mColony(colonyId).get()

  # Find all fleets at this colony
  var fleetsAtColony: seq[FleetId] = @[]
  for (fleetId, fleet) in state.allFleetsWithId():
    if fleet.location == systemId and fleet.houseId == colony.owner:
      fleetsAtColony.add(fleetId)

  # Process each fleet, extracting crippled ships
  for fleetId in fleetsAtColony:
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isNone:
      continue
    let fleet = fleetOpt.get()

    # Check each squadron for crippled ships
    for squadronId in fleet.squadrons:
      let squadronOpt = state.squadron(squadronId)
      if squadronOpt.isNone:
        continue
      let squadron = squadronOpt.get()

      # Check flagship
      let flagshipOpt = state.ship(squadron.flagshipId)
      if flagshipOpt.isSome:
        let flagship = flagshipOpt.get()
        if flagship.isCrippled:
          # Check drydock capacity
          let drydockProjects =
            colony.getActiveProjectsByFacility(facilities.FacilityClass.Drydock)
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
        let shipOpt = state.ship(shipId)
        if shipOpt.isNone:
          continue
        let ship = shipOpt.get()

        if ship.isCrippled:
          # Check drydock capacity
          let drydockProjects =
            colony.getActiveProjectsByFacility(facilities.FacilityClass.Drydock)
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
