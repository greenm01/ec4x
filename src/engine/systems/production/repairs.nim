## Repair Queue Management
##
## Handles automatic submission of repair orders for crippled units during
## Command Phase Part A (Colony Automation). Players can cancel auto-repairs
## during their submission window. All repairs (auto and manual) execute in
## Production Phase Step 2c.
##
## **Architecture:**
## - Uses state layer APIs to read entities (state.fleet, state.ship, state.colony)
## - Uses entity ops for mutations (fleet_ops.destroyFleet, project_ops.queueRepairProject)
## - Follows three-layer pattern: State → Business Logic → Entity Ops
##
## **Auto-Repair System:**
## - Controlled by colony.autoRepair flag (true = auto, false = manual)
## - Submits repair orders during Command Phase Part A (before player window)
## - Players can cancel auto-repair orders during submission window
## - Priority order: Ships (1) → Ground Units (2) → Facilities (3)
##
## **Repair Types:**
## 1. Ships: Extracted from fleets → drydock queue (1 turn, 25% cost)
##    - Requires: Non-crippled drydock
##    - Repaired ships recommission through standard pipeline
## 2. Ground Units: Army, Marine, GroundBattery, PlanetaryShield (1 turn, 25% cost)
##    - Requires: Colony infrastructure (no facility)
## 3. Facilities: Spaceport, Shipyard, Drydock (1 turn, 25% cost)
##    - Spaceport: No prerequisite (colony self-repair)
##    - Shipyard: Requires non-crippled spaceport
##    - Drydock: Requires non-crippled spaceport
## 4. Starbases: Kastra repairs (1 turn, 25% cost)
##    - Requires: Non-crippled spaceport

import std/[options, sequtils]
import ../../types/[core, ship, production, facilities, combat, game_state, ground_unit, command]
import ../../entities/[fleet_ops, project_ops]
import ../../state/[engine, iterators]
import ../../systems/production/accessors # For ship cost lookups
import ../../systems/production/facility_queries
import ../../globals
import ../../../common/logger

export production.RepairProject, facilities.FacilityClass, production.RepairTargetType

proc findAvailableDrydock*(
    state: GameState, colonyId: ColonyId
): Option[NeoriaId] =
  ## Find a drydock with available capacity at the given colony
  ## Returns the NeoriaId of an available drydock, or none if all are full/crippled
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return none(NeoriaId)
  
  let colony = colonyOpt.get()
  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isSome:
      let neoria = neoriaOpt.get()
      if neoria.neoriaClass == NeoriaClass.Drydock and
          neoria.state != CombatState.Crippled:
        # Check if this drydock has available capacity
        let activeRepairs = neoria.activeRepairs.len.int32
        if activeRepairs < neoria.effectiveDocks:
          return some(neoriaId)
  
  return none(NeoriaId)

proc calculateRepairCost*(shipClass: ShipClass): int32 =
  ## Calculate repair cost for a ship
  ## Per economy.md:5.4 - All repairs require drydocks, cost is 25% of build cost
  let buildCost = accessors.shipConstructionCost(shipClass)
  result = (buildCost.float32 * 0.25'f32).int32

proc extractCrippledShip*(
    state: GameState, fleetId: FleetId, shipId: ShipId, drydockId: NeoriaId
): Option[production.RepairProject] =
  ## Extract a crippled ship from a fleet and create repair project assigned to a drydock
  ## Works with entity IDs for DoD compliance
  ## Returns None if extraction fails
  ## **NOTE:** Ship repairs MUST be assigned to a specific drydock (neoriaId required)

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
    state.destroyFleet(fleetId)
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

  # Create repair project using project_ops with ASSIGNED drydock
  let repair = project_ops.newRepairProject(
    id = RepairProjectId(0), # ID assigned by entity manager
    colonyId = ColonyId(0), # Assigned when queued
    targetType = production.RepairTargetType.Ship,
    facilityType = facilities.FacilityClass.Drydock, # Drydocks only
    cost = cost.int32,
    turnsRemaining = 1,
    priority = 1, # Ship repairs = priority 1 (construction = 0, kastra = 2)
    neoriaId = some(drydockId), # CRITICAL: Assign to specific drydock
    fleetId = some(fleetId),
    shipId = some(shipId),
    kastraId = none(KastraId),
    groundUnitId = none(GroundUnitId),
    shipClass = some(shipClass),
  )

  logInfo(
    "Repair", "Extracted crippled ship for repair", "shipClass=", shipClass,
    " fleetId=", fleetId, " shipId=", shipId, " cost=", cost,
    " drydockId=", drydockId,
  )

  return some(repair)

proc submitAutomaticStarbaseRepairs*(state: GameState, systemId: SystemId) =
  ## Automatically submit repair requests for crippled starbases at colony
  ## Starbases use spaceport facilities and do NOT consume dock space
  ## Per architecture: Starbases are facilities that require Spaceports

  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return

  var colony = colonyOpt.get()
  let colonyId = colony.id

  # Check if auto-repair is enabled
  if not colony.autoRepair:
    return # Manual mode - skip automatic repairs

  # Check if colony has spaceport (starbases require spaceport for repair)
  if not facility_queries.hasOperationalSpaceport(state, colonyId):
    return # No operational spaceport available

  # Track if we modified the colony
  var modified = false

  # Submit repairs for crippled starbases
  # Note: Starbases do NOT consume dock capacity (they are facilities, not ships)
  for kastraId in colony.kastraIds:
    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isNone:
      continue
    let kastra = kastraOpt.get()
    if kastra.state == CombatState.Crippled:
      # Calculate repair cost (25% of starbase build cost)
      let starbaseBuildCost = gameConfig.facilities.facilities[FacilityClass.Starbase].buildCost
      let repairCost = (starbaseBuildCost.float32 * 0.25'f32).int32

      # Create and queue repair project using entity manager
      var repair = project_ops.newRepairProject(
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

      let finalRepair = state.queueRepairProject(colonyId, repair)

      # Colony-level repair (no specific neoria), add to colony queue
      colony.repairQueue.add(finalRepair.id)
      modified = true
      logInfo(
        "Repair", "Submitted repair for starbase", "starbaseId=", kastra.id,
        " systemId=", systemId, " cost=", repairCost, " facilityType=Spaceport",
      )

  # Write back modified colony
  if modified:
    state.updateColony(colonyId, colony)

proc submitAutomaticRepairs*(state: GameState, systemId: SystemId) =
  ## Automatically submit repair requests for fleets with crippled ships at this colony
  ## Ship repairs require drydocks (spaceports and shipyards cannot repair)
  ## Called during turn resolution after fleet movements

  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return

  var colony = colonyOpt.get()
  let colonyId = colony.id

  # Check if auto-repair is enabled
  if not colony.autoRepair:
    return # Manual mode - skip automatic repairs

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
  state.submitAutomaticStarbaseRepairs(systemId)

  # Reload colony after starbase repairs submitted (it might have been modified)
  colony = state.colony(colonyId).get()

  # Track if we modified the colony
  var modified = false

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
        # Find an available drydock with capacity
        let drydockIdOpt = state.findAvailableDrydock(colonyId)
        
        if drydockIdOpt.isSome:
          let drydockId = drydockIdOpt.get()
          # Extract and add to drydock's repair queue
          let repairOpt = state.extractCrippledShip(fleetId, shipId, drydockId)
          if repairOpt.isSome:
            var repair = repairOpt.get()
            discard state.queueRepairProject(colonyId, repair)

            # Ship repair goes to drydock queue (handled by queueRepairProject)
            # No need to add to colony.repairQueue - ships use neoria pipeline
            modified = true
            logInfo(
              "Repair", "Submitted ship for repair at drydock",
              " shipClass=", ship.shipClass, " fleetId=", fleetId,
              " systemId=", systemId, " drydockId=", drydockId,
            )
        else:
          logDebug(
            "Repair", "Colony has no available drydock capacity",
            " systemId=", systemId,
          )

  # Write back modified colony
  if modified:
    state.updateColony(colonyId, colony)

proc calculateGroundUnitRepairCost*(groundClass: GroundClass): int32 =
  ## Calculate repair cost for a ground unit
  ## Per economy.md:5.4 - Ground unit repairs cost 25% of build cost
  ## Ground units are repaired via colony infrastructure (no facility required)
  let buildCost = case groundClass
    of GroundClass.Army:
      accessors.armyBuildCost()
    of GroundClass.Marine:
      accessors.marineBuildCost()
    of GroundClass.GroundBattery:
      accessors.groundBatteryBuildCost()
    of GroundClass.PlanetaryShield:
      accessors.planetaryShieldCost(1) # Base cost for SLD I
  result = (buildCost.float32 * 0.25'f32).int32

proc submitAutomaticGroundUnitRepairs*(
    state: GameState, systemId: SystemId
) =
  ## Automatically submit repair requests for crippled ground units at colony
  ## Ground units are repaired via colony infrastructure (no facility required)
  ## Priority: 2 (after ships, before facilities)

  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return

  var colony = colonyOpt.get()
  let colonyId = colony.id

  # Check if auto-repair is enabled
  if not colony.autoRepair:
    return # Manual mode - skip automatic repairs

  # Track if we modified the colony
  var modified = false

  # Find all ground units at this colony
  let groundUnits = state.groundUnitsAtColony(colonyId)

  for unit in groundUnits:
    if unit.state == CombatState.Crippled:
      # Calculate repair cost (25% of build cost)
      let repairCost = calculateGroundUnitRepairCost(unit.stats.unitType)

      # Create and queue repair project using entity manager
      # Ground units don't use facilities (colony infrastructure repair)
      var repair = project_ops.newRepairProject(
        id = RepairProjectId(0), # ID assigned by entity manager
        colonyId = ColonyId(0), # Assigned when queued
        targetType = production.RepairTargetType.GroundUnit,
        facilityType = facilities.FacilityClass.Spaceport, # Placeholder (not used)
        cost = repairCost,
        turnsRemaining = 1,
        priority = 2, # Ground unit repairs = priority 2 (after ships, before facilities)
        neoriaId = none(NeoriaId),
        fleetId = none(FleetId),
        shipId = none(ShipId),
        kastraId = none(KastraId),
        groundUnitId = some(unit.id),
        shipClass = none(ShipClass),
      )

      let finalRepair = state.queueRepairProject(colonyId, repair)

      # Colony-level repair (no specific neoria), add to colony queue
      colony.repairQueue.add(finalRepair.id)
      modified = true
      logInfo(
        "Repair", "Submitted ground unit for repair",
        " unitType=", unit.stats.unitType, " unitId=", unit.id,
        " systemId=", systemId, " cost=", repairCost,
      )

  # Write back modified colony
  if modified:
    state.updateColony(colonyId, colony)

proc calculateFacilityRepairCost*(facilityClass: NeoriaClass): int32 =
  ## Calculate repair cost for a facility (Neoria)
  ## Per economy.md:5.4 - Facility repairs cost 25% of build cost
  ## Repair prerequisites per design decisions:
  ##   - Spaceport: No prerequisite (colony self-repair)
  ##   - Shipyard: Requires non-crippled spaceport
  ##   - Drydock: Requires non-crippled spaceport
  let buildCost = case facilityClass
    of NeoriaClass.Spaceport:
      accessors.buildingCost(FacilityClass.Spaceport)
    of NeoriaClass.Shipyard:
      accessors.buildingCost(FacilityClass.Shipyard)
    of NeoriaClass.Drydock:
      accessors.buildingCost(FacilityClass.Drydock)
  result = (buildCost.float32 * 0.25'f32).int32

proc submitAutomaticFacilityRepairs*(
    state: GameState, systemId: SystemId
) =
  ## Automatically submit repair requests for crippled facilities at colony
  ## Repair prerequisites per design decisions:
  ##   - Spaceport: No prerequisite (colony self-repair)
  ##   - Shipyard: Requires non-crippled spaceport
  ##   - Drydock: Requires non-crippled spaceport
  ## Priority: 3 (after ships and ground units)

  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return

  var colony = colonyOpt.get()
  let colonyId = colony.id

  # Check if auto-repair is enabled
  if not colony.autoRepair:
    return # Manual mode - skip automatic repairs

  # Track if we modified the colony
  var modified = false

  # Check if we have operational spaceport (for shipyard/drydock repairs)
  let hasSpaceport = state.hasOperationalSpaceport(colonyId)

  # Process each facility at this colony
  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isNone:
      continue
    let neoria = neoriaOpt.get()

    if neoria.state == CombatState.Crippled:
      # Check prerequisites based on facility type
      let canRepair = case neoria.neoriaClass
        of NeoriaClass.Spaceport:
          true # No prerequisite (colony self-repair)
        of NeoriaClass.Shipyard:
          hasSpaceport # Requires operational spaceport
        of NeoriaClass.Drydock:
          hasSpaceport # Requires operational spaceport

      if not canRepair:
        logDebug(
          "Repair", "Cannot repair facility - missing prerequisite",
          " facilityType=", neoria.neoriaClass, " neoriaId=", neoriaId,
          " systemId=", systemId,
        )
        continue

      # Calculate repair cost (25% of build cost)
      let repairCost = calculateFacilityRepairCost(neoria.neoriaClass)

      # Create and queue repair project using entity manager
      var repair = project_ops.newRepairProject(
        id = RepairProjectId(0), # ID assigned by entity manager
        colonyId = ColonyId(0), # Assigned when queued
        targetType = production.RepairTargetType.Facility,
        facilityType = FacilityClass.Spaceport, # Use spaceport for facility repairs
        cost = repairCost,
        turnsRemaining = 1,
        priority = 3, # Facility repairs = priority 3 (lowest)
        neoriaId = some(neoriaId),
        fleetId = none(FleetId),
        shipId = none(ShipId),
        kastraId = none(KastraId),
        groundUnitId = none(GroundUnitId),
        shipClass = none(ShipClass),
      )

      let finalRepair = state.queueRepairProject(colonyId, repair)

      # Colony-level repair (no specific neoria), add to colony queue
      colony.repairQueue.add(finalRepair.id)
      modified = true
      logInfo(
        "Repair", "Submitted facility for repair",
        " facilityType=", neoria.neoriaClass, " neoriaId=", neoriaId,
        " systemId=", systemId, " cost=", repairCost,
      )

  # Write back modified colony
  if modified:
    state.updateColony(colonyId, colony)

proc submitAllAutomaticRepairs*(state: GameState, systemId: SystemId) =
  ## Master function to submit all automatic repairs for a colony
  ## Called during Command Phase Part A, Step 2 (Colony Automation)
  ##
  ## **Purpose:** Automatically queue repair orders for crippled units
  ## **Timing:** Command Phase Part A (BEFORE player submission window)
  ## **Execution:** Repairs execute later in Production Phase Step 2c
  ##
  ## **Player Control:**
  ## - Players can cancel auto-repair orders during Part B submission window
  ## - Manual mode (colony.autoRepair = false) disables all auto-repairs
  ##
  ## **Priority Order:**
  ##   1. Ships (Priority 1) + Starbases (Priority 2, processed together)
  ##   2. Ground Units (Priority 2)
  ##   3. Facilities (Priority 3)
  ##
  ## **Unified Queue System:**
  ## - Auto-repairs and manual-repairs use the same repair queue
  ## - All repairs execute together in Production Phase Step 2c
  
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isNone:
    return
  
  let colony = colonyOpt.get()
  
  # Check if auto-repair is enabled (master flag check)
  if not colony.autoRepair:
    return # Manual mode - skip all automatic repair submissions
  
  # Submit repair orders in priority sequence
  # Note: submitAutomaticRepairs() internally calls submitAutomaticStarbaseRepairs()
  state.submitAutomaticRepairs(systemId)           # Ships (Pri 1) + Starbases (Pri 2)
  state.submitAutomaticGroundUnitRepairs(systemId) # Ground Units (Pri 2)
  state.submitAutomaticFacilityRepairs(systemId)   # Facilities (Pri 3)
  
  logDebug(
    "Repair", "Completed auto-repair submission",
    " systemId=", systemId, " colony=", colony.id,
  )

proc processManualRepairCommand*(
    state: GameState, cmd: RepairCommand
): bool =
  ## Process a single manual repair command
  ## Called during Command Phase Part C (after validation)
  ## Returns true if repair was successfully queued, false otherwise
  ##
  ## **Timing:** Command Phase Part C (command processing)
  ## **Execution:** Repair executes in Production Phase Step 2c
  
  let colonyOpt = state.colony(cmd.colonyId)
  if colonyOpt.isNone:
    return false
  
  var colony = colonyOpt.get()
  
  # Determine target details and cost based on type
  var repair: RepairProject
  
  case cmd.targetType
  of RepairTargetType.Ship:
    # Find available drydock for ship repair
    let drydockIdOpt = state.findAvailableDrydock(cmd.colonyId)
    if drydockIdOpt.isNone:
      logWarn(
        "Repair", "Manual ship repair failed - no available drydock",
        " colonyId=", cmd.colonyId, " shipId=", cmd.targetId,
      )
      return false
    
    let shipId = ShipId(cmd.targetId)
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      return false
    let ship = shipOpt.get()
    let repairCost = calculateRepairCost(ship.shipClass)
    
    repair = project_ops.newRepairProject(
      id = RepairProjectId(0),
      colonyId = ColonyId(0),
      targetType = RepairTargetType.Ship,
      facilityType = FacilityClass.Drydock,
      cost = repairCost,
      turnsRemaining = 1,
      priority = if cmd.priority > 0: cmd.priority else: 1, # Default priority 1
      neoriaId = some(drydockIdOpt.get()), # CRITICAL: Assign to specific drydock
      fleetId = none(FleetId), # Manual repairs don't track source fleet
      shipId = some(shipId),
      kastraId = none(KastraId),
      groundUnitId = none(GroundUnitId),
      shipClass = some(ship.shipClass),
    )
  
  of RepairTargetType.GroundUnit:
    let unitId = GroundUnitId(cmd.targetId)
    let unitOpt = state.groundUnit(unitId)
    if unitOpt.isNone:
      return false
    let unit = unitOpt.get()
    let repairCost = calculateGroundUnitRepairCost(unit.stats.unitType)
    
    repair = project_ops.newRepairProject(
      id = RepairProjectId(0),
      colonyId = ColonyId(0),
      targetType = RepairTargetType.GroundUnit,
      facilityType = FacilityClass.Spaceport, # Placeholder
      cost = repairCost,
      turnsRemaining = 1,
      priority = if cmd.priority > 0: cmd.priority else: 2, # Default priority 2
      neoriaId = none(NeoriaId),
      fleetId = none(FleetId),
      shipId = none(ShipId),
      kastraId = none(KastraId),
      groundUnitId = some(unitId),
      shipClass = none(ShipClass),
    )
  
  of RepairTargetType.Facility:
    let neoriaId = NeoriaId(cmd.targetId)
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isNone:
      return false
    let neoria = neoriaOpt.get()
    let repairCost = calculateFacilityRepairCost(neoria.neoriaClass)
    
    repair = project_ops.newRepairProject(
      id = RepairProjectId(0),
      colonyId = ColonyId(0),
      targetType = RepairTargetType.Facility,
      facilityType = FacilityClass.Spaceport,
      cost = repairCost,
      turnsRemaining = 1,
      priority = if cmd.priority > 0: cmd.priority else: 3, # Default priority 3
      neoriaId = some(neoriaId),
      fleetId = none(FleetId),
      shipId = none(ShipId),
      kastraId = none(KastraId),
      groundUnitId = none(GroundUnitId),
      shipClass = none(ShipClass),
    )
  
  of RepairTargetType.Starbase:
    let kastraId = KastraId(cmd.targetId)
    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isNone:
      return false
    discard kastraOpt.get()
    let starbaseBuildCost = 300'i32 # From facilities.kdl
    let repairCost = (starbaseBuildCost.float32 * 0.25'f32).int32
    
    repair = project_ops.newRepairProject(
      id = RepairProjectId(0),
      colonyId = ColonyId(0),
      targetType = RepairTargetType.Starbase,
      facilityType = FacilityClass.Spaceport,
      cost = repairCost,
      turnsRemaining = 1,
      priority = if cmd.priority > 0: cmd.priority else: 2, # Default priority 2
      neoriaId = none(NeoriaId),
      fleetId = none(FleetId),
      shipId = none(ShipId),
      kastraId = some(kastraId),
      groundUnitId = none(GroundUnitId),
      shipClass = none(ShipClass),
    )
  
  # Queue the repair project
  let finalRepair = state.queueRepairProject(cmd.colonyId, repair)
  
  # Only add to colony queue for colony-pipeline repairs (not ships)
  # Ships go to drydock queue (handled by queueRepairProject via neoriaId)
  if cmd.targetType != RepairTargetType.Ship:
    colony.repairQueue.add(finalRepair.id)
    state.updateColony(cmd.colonyId, colony)
  
  logInfo(
    "Repair", "Manually queued repair",
    " targetType=", cmd.targetType, " targetId=", cmd.targetId,
    " colonyId=", cmd.colonyId, " cost=", repair.cost,
  )
  
  return true

proc processManualRepairCommands*(
    state: GameState, houseId: HouseId, commands: seq[RepairCommand]
) =
  ## Process all manual repair commands for a house
  ## Called during Command Phase Part C (after player submission window)
  ## Validated commands are queued for execution in Production Phase Step 2c
  
  for cmd in commands:
    let success = state.processManualRepairCommand(cmd)
    if not success:
      logWarn(
        "Repair", "Failed to process manual repair command",
        " houseId=", houseId, " targetType=", cmd.targetType,
        " targetId=", cmd.targetId,
      )
