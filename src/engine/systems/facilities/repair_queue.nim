## Repair Queue Management
##
## Handles automatic extraction of crippled ships from fleets and submission
## to repair queues at colonies with drydock capacity.
##
## Design:
## - Fleets with crippled ships at colonies automatically submit repair requests
## - Ships extracted from fleets → repair queue (1 turn, 25% cost)
## - Repaired ships recommission through standard pipeline (fleet)
## - Drydocks are repair-only facilities (10 docks each)
## - Shipyards are construction-only facilities (clean separation of concerns)

import std/[tables, options, strformat, sequtils]
import ../../types/[core, ship, production, facilities, combat]
import ../../systems/ship/entity as ship_entity # Ship helper functions
import ../../entities/[fleet_ops, project_ops]
import ../../../common/logger

export production.RepairProject, facilities.FacilityClass, production.RepairTargetType

proc calculateRepairCost*(shipClass: ShipClass): int =
  ## Calculate repair cost for a ship
  ## Per economy.md:5.4 - All repairs require drydocks, cost is 25% of build cost
  let ship = ship_entity.newShip(shipClass)
  result = (ship.buildCost().float * 0.25).int

proc extractCrippledShip*(
    state: var GameState, fleetId: FleetId, shipId: ShipId
): Option[production.RepairProject] =
  ## Extract a crippled ship from a fleet and create repair project
  ## Works with entity IDs for DoD compliance
  ## Returns None if extraction fails

  # Look up fleet using entity manager
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return none(RepairProject)
  var fleet = fleetOpt.get()

  # Verify ship is in fleet
  if shipId notin fleet.ships:
    return none(RepairProject)

  # Look up the ship being extracted
  let shipOpt = state.ship(shipId)
  if shipOpt.isNone:
    return none(RepairProject)
  let ship = shipOpt.get()

  if ship.state != CombatState.Crippled:
    return none(RepairProject)

  let shipClass = ship.shipClass

  # Remove ship from fleet
  fleet.ships = fleet.ships.filterIt(it != shipId)

  # EMPTY FLEET CLEANUP
  # If removing this ship leaves the fleet empty, delete the fleet entirely
  if fleet.ships.len == 0:
    destroyFleet(state, fleetId)
    logInfo(
      "Repair",
      "Removed crippled ship and deleted empty fleet",
      "shipId=", shipId, " fleetId=", fleetId,
    )
  else:
    state.updateFleet(fleetId, fleet)
    logInfo(
      "Repair", "Extracted crippled ship from fleet for repair",
      "shipId=", shipId, " fleetId=", fleetId,
    )

  # Create repair project (drydocks only)
  let cost = calculateRepairCost(shipClass)

  # Create repair project using project_ops
  let repair = project_ops.newRepairProject(
    id = RepairProjectId(0), # ID assigned by entity manager
    colonyId = ColonyId(0), # Assigned when queued
    targetType = production.RepairTargetType.Ship,
    facilityType = facilities.FacilityClass.Drydock, # Drydocks only
    cost = cost.int32,
    turnsRemaining = 1,
    priority = 1, # Ship repairs = priority 1 (construction = 0, kastra = 2)
    neoriaId = none(NeoriaId),
    fleetId = some(fleetId),
    shipId = some(shipId),
    kastraId = none(KastraId),
    shipClass = some(shipClass),
  )

  logInfo(
    "Repair", "Extracted crippled ship for repair", "shipClass=", shipClass,
    " fleetId=", fleetId, " shipId=", shipId, " cost=", cost,
    " facilityType=Drydock",
  )

  return some(repair)

proc submitAutomaticStarbaseRepairs*(state: var GameState, systemId: SystemId) =
  ## Automatically submit repair requests for crippled starbases at colony
  ## Starbases use spaceport facilities and do NOT consume dock space
  ## Per architecture: Starbases are facilities that require Spaceports

  let colonyIdOpt = state.colonyBySystem(systemId)
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
    if kastra.state == CombatState.Crippled:
      # Calculate repair cost (25% of starbase build cost)
      # TODO: Get actual starbase build cost from config (for now use estimate)
      let starbaseBuildCost = 300 # From facilities.toml
      let repairCost = (starbaseBuildCost.float * 0.25).int

      let repair = project_ops.newRepairProject(
        id = RepairProjectId(0), # ID assigned by entity manager
        colonyId = ColonyId(0), # Assigned when queued
        targetType = production.RepairTargetType.Starbase,
        facilityType = facilities.FacilityClass.Spaceport, # Use Spaceport, not Shipyard
        cost = repairCost.int32,
        turnsRemaining = 1,
        priority = 2, # Kastra repairs = priority 2 (lowest)
        neoriaId = none(NeoriaId),
        fleetId = none(FleetId),
        shipId = none(ShipId),
        kastraId = some(kastra.id),
        shipClass = none(ShipClass),
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

  let colonyIdOpt = state.colonyBySystem(systemId)
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

    # Check each ship in fleet for crippled status
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isNone:
        continue
      let ship = shipOpt.get()

      if ship.state == CombatState.Crippled:
        # Check drydock capacity
        let drydockProjects =
          colony.getActiveProjectsByFacility(facilities.FacilityClass.Drydock)
        let drydockCapacity = colony.getDrydockDockCapacity()

        if drydockProjects < drydockCapacity:
          # Extract and add to repair queue
          let repairOpt = state.extractCrippledShip(fleetId, shipId)
          if repairOpt.isSome:
            colony.repairQueue.add(repairOpt.get())
            logInfo(
              "Repair",
              "Submitted ship for repair",
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
