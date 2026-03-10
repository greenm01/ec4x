## Construction - Build command processing and validation
##
## This module handles Command Phase construction command submission,
## including budget validation, capacity checking, and routing to
## appropriate construction queues (facility-based or colony-based).
##
## **Dual Construction System:**
## - DOCK CONSTRUCTION: Capital ships → Spaceport/Shipyard facility queues
## - COLONY CONSTRUCTION: Fighters, buildings, IU → Colony queues
##
## **Phas commands)
##
## **Flow:**
## 1. Validate colony ownership and budget
## 2. Create project using projects.nim factories
## 3. Route to facility queue (dock) OR colony queue (planet-side)
## 4. Deduct treasury and generate events
##
## **Separation of Concerns:**
## - projects.nim: "What to build" (project definitions)
## - THIS MODULE: "How commands work" (validation, routing, treasury)
## - queue_advancement.nim: "Queue management" (advancement)

import std/[options, strformat, tables, algorithm]
import ../../types/[core, game_state, production, command, event]
import ../../types/[colony, facilities, ship, combat]
import ../../state/engine
import ../../entities/project_ops
import ../../../common/logger
import ../capacity/construction_docks
import ./queue_advancement
import ./[projects, accessors, facility_queries]
import ../../event_factory/economic

proc shipProjectCost(
    shipClass: ShipClass,
    assignedFacility: Option[tuple[facilityId: NeoriaId, facilityType: NeoriaClass]],
): int32 =
  let baseCost = accessors.shipConstructionCost(shipClass)
  if shipClass == ShipClass.Fighter:
    return baseCost
  if assignedFacility.isSome and
      assignedFacility.get().facilityType == NeoriaClass.Spaceport:
    return baseCost * 2
  baseCost

proc availableAssignedFacilities(
    state: GameState,
    colonyId: ColonyId,
    pendingUsage: Table[NeoriaId, int32],
): seq[tuple[facilityId: NeoriaId, facilityType: NeoriaClass, availableDocks: int32]] =
  let colonyOpt = state.colony(colonyId)
  if colonyOpt.isNone:
    return @[]

  let colony = colonyOpt.get()
  for neoriaId in colony.neoriaIds:
    let neoriaOpt = state.neoria(neoriaId)
    if neoriaOpt.isNone:
      continue
    let neoria = neoriaOpt.get()
    if neoria.state == CombatState.Crippled or
        neoria.neoriaClass == NeoriaClass.Drydock:
      continue

    let reserved = pendingUsage.getOrDefault(neoriaId, 0'i32)
    let usedDocks = int32(
      neoria.activeConstructions.len + neoria.activeRepairs.len
    ) + reserved
    let available = neoria.effectiveDocks - usedDocks
    if available > 0'i32:
      result.add((neoriaId, neoria.neoriaClass, available))

  result.sort do(
    a, b: tuple[facilityId: NeoriaId, facilityType: NeoriaClass,
      availableDocks: int32]
  ) -> int:
    if a.facilityType == NeoriaClass.Shipyard and
        b.facilityType == NeoriaClass.Spaceport:
      return -1
    if a.facilityType == NeoriaClass.Spaceport and
        b.facilityType == NeoriaClass.Shipyard:
      return 1
    cmp(b.availableDocks, a.availableDocks)

proc assignFacilityForPacket(
    state: GameState,
    colonyId: ColonyId,
    pendingUsage: Table[NeoriaId, int32],
): Option[tuple[facilityId: NeoriaId, facilityType: NeoriaClass]] =
  let available = state.availableAssignedFacilities(colonyId, pendingUsage)
  if available.len == 0:
    return none(tuple[facilityId: NeoriaId, facilityType: NeoriaClass])
  let best = available[0]
  some((best.facilityId, best.facilityType))

proc queueProjectToAssignedFacility(
    state: GameState,
    colonyId: ColonyId,
    project: ConstructionProject,
    facilityId: NeoriaId,
): bool =
  var assignedProject = project
  assignedProject.neoriaId = some(facilityId)
  discard state.queueConstructionProject(colonyId, assignedProject)
  true

proc resolveBuildOrders*(
    state: GameState, packet: CommandPacket, events: var seq[GameEvent]
) =
  ## Process construction commands for a house with budget validation
  ## Prevents overspending by tracking committed costs
  let house = state.house(packet.houseId).get()
  logInfo(
    "Economy",
    &"Processing build commands for {house.name}",
  )

  # Initialize budget validation context
  # Use CURRENT treasury from state (NOT snapshot from CommandPacket)
  # This ensures validation matches the actual treasury after income/maintenance
  var budgetContext = CommandValidationContext(
    availableTreasury: house.treasury,
    committedSpending: 0,
    rejectedCommands: 0
  )

  logInfo(
    "Economy",
    &"{packet.houseId} Build Command Validation: {packet.buildCommands.len} orders, " &
      &"{house.treasury} PP available (current treasury after income/maintenance)",
  )

  var requestedUnits = 0
  var acceptedUnits = 0
  var pendingDockUsage = initTable[NeoriaId, int32]()

  for command in packet.buildCommands:
    let requestedCount = case command.buildType
      of BuildType.Industrial:
        max(0'i32, command.industrialUnits)
      else:
        max(1'i32, command.quantity)
    requestedUnits += int(requestedCount)

    # Validate colony exists
    let colonyOpt = state.colony(command.colonyId)
    if colonyOpt.isNone:
      let errorMsg = &"Colony not found at {command.colonyId}"
      logError(
        "Economy", &"[BUILD ORDER REJECTED] {packet.houseId}: {errorMsg}"
      )
      # Note: Rejection events handled by turn result system
      continue

    # Validate colony ownership
    let colony = colonyOpt.get()
    if colony.owner != packet.houseId:
      let errorMsg =
        &"Colony at {command.colonyId} not owned by {packet.houseId} (owned by {colony.owner})"
      logError(
        "Economy", &"[BUILD ORDER REJECTED] {packet.houseId}: {errorMsg}"
      )
      # Note: Rejection events handled by turn result system
      continue

    # Check facility prerequisites (e.g., Spaceport required for
    # Shipyard/Drydock/Starbase). Reject early so PP is never spent.
    if command.buildType == BuildType.Facility and command.facilityClass.isSome:
      let fc = command.facilityClass.get()
      if not facility_queries.facilityPrerequisiteMet(state, command.colonyId, fc):
        let prereq = accessors.facilityPrerequisite(fc)
        logWarn(
          "Economy",
          &"[BUILD ORDER REJECTED] {packet.houseId}: " &
            &"{fc} requires operational {prereq} at {command.colonyId}",
        )
        continue

    for unitIdx in 0 ..< int(requestedCount):
      # Determine if this construction requires dock capacity
      let requiresDock = (
        command.buildType == BuildType.Ship and command.shipClass.isSome and
        construction_docks.shipRequiresDock(command.shipClass.get())
      )

      var assignedFacility:
        Option[tuple[facilityId: NeoriaId, facilityType: NeoriaClass]] =
        none(tuple[facilityId: NeoriaId, facilityType: NeoriaClass])

      if requiresDock:
        assignedFacility = state.assignFacilityForPacket(
          command.colonyId,
          pendingDockUsage,
        )
        if assignedFacility.isNone:
          let (current, maximum) =
            construction_docks.colonyTotalCapacity(state, command.colonyId)
          let errorMsg =
            &"Colony {command.colonyId} at capacity ({current}/{maximum} docks used) - cannot accept more projects"
          logWarn(
            "Economy", &"[BUILD ORDER REJECTED] {packet.houseId}: {errorMsg}"
          )
          budgetContext.rejectedCommands += 1
          continue

      let projectCost = case command.buildType
        of BuildType.Ship:
          if command.shipClass.isSome:
            shipProjectCost(command.shipClass.get(), assignedFacility)
          else:
            0'i32
        of BuildType.Facility:
          if command.facilityClass.isSome:
            accessors.buildingCost(command.facilityClass.get())
          else:
            0'i32
        of BuildType.Industrial, BuildType.Infrastructure:
          projects.industrialUnitCost(colony)
        of BuildType.Ground:
          if command.groundClass.isSome:
            accessors.groundUnitCost(command.groundClass.get())
          else:
            0'i32

      if budgetContext.availableTreasury - budgetContext.committedSpending <
          projectCost:
        let errorMsg =
          &"Insufficient funds: need {projectCost} PP, have " &
          &"{budgetContext.availableTreasury - budgetContext.committedSpending} PP"
        logWarn(
          "Economy",
          &"[BUILD ORDER REJECTED] {packet.houseId} at {command.colonyId}: {errorMsg}",
        )
        budgetContext.rejectedCommands += 1
        continue

      budgetContext.committedSpending += projectCost

      var project: ConstructionProject
      var projectDesc: string

      case command.buildType
      of BuildType.Industrial, BuildType.Infrastructure:
        project = createIndustrialProject(colony, 1)
        projectDesc = "Industrial expansion: 1 IU"
      of BuildType.Ship:
        if command.shipClass.isNone:
          logError(
            "Economy", &"Ship construction failed: no ship class specified"
          )
          budgetContext.rejectedCommands += 1
          continue

        let shipClass = command.shipClass.get()
        project = createShipProject(shipClass)
        project.costTotal = projectCost
        project.costPaid = projectCost
        projectDesc = "Ship construction: " & $shipClass
      of BuildType.Facility:
        if command.facilityClass.isNone:
          logError(
            "Economy",
            &"Facility construction failed: no facility class specified",
          )
          budgetContext.rejectedCommands += 1
          continue

        let facilityClass = command.facilityClass.get()
        project = createBuildingProject(facilityClass)
        projectDesc = "Facility construction: " & $facilityClass
      of BuildType.Ground:
        if command.groundClass.isNone:
          logError(
            "Economy",
            &"Ground unit construction failed: no ground class specified",
          )
          budgetContext.rejectedCommands += 1
          continue

        let groundClass = command.groundClass.get()
        project = projects.createGroundUnitProject(groundClass)
        projectDesc = "Ground unit construction: " & $groundClass

      var success = false
      var queueLocation = ""

      if requiresDock and assignedFacility.isSome:
        let (facilityId, _) = assignedFacility.get()
        success = state.queueProjectToAssignedFacility(
          command.colonyId,
          project,
          facilityId,
        )
        if success:
          queueLocation = &"facility {facilityId}"
          pendingDockUsage[facilityId] =
            pendingDockUsage.getOrDefault(facilityId, 0'i32) + 1'i32
      else:
        var mutableColony = colony
        if state.startConstruction(mutableColony, project):
          state.updateColony(command.colonyId, mutableColony)
          success = true
          queueLocation = "colony queue"

      if success:
        var mutableHouse = state.house(packet.houseId).get()
        let oldTreasury = mutableHouse.treasury

        if mutableHouse.treasury >= project.costTotal:
          mutableHouse.treasury -= project.costTotal
          state.updateHouse(packet.houseId, mutableHouse)
          acceptedUnits += 1

          logInfo(
            "Economy",
            &"Started construction at {command.colonyId}: {projectDesc} " &
              &"(Cost: {project.costTotal} PP, Est. {project.turnsRemaining} turns, " &
              &"Location: {queueLocation}, Treasury: {oldTreasury} → {mutableHouse.treasury} PP)",
          )

          events.add(
            economic.constructionStarted(
              packet.houseId, projectDesc, colony.systemId, project.costTotal
            )
          )
        else:
          logError(
            "Economy",
            &"{packet.houseId} Construction CANCELLED at {command.colonyId}: {projectDesc} " &
              &"- Insufficient treasury (need {project.costTotal} PP, have {mutableHouse.treasury} PP, " &
              &"was {oldTreasury} PP at validation)",
          )

          if queueLocation == "colony queue":
            var mutableColony = state.colony(command.colonyId).get()
            if mutableColony.constructionQueue.len > 0:
              discard mutableColony.constructionQueue.pop()
            state.updateColony(command.colonyId, mutableColony)

          budgetContext.rejectedCommands += 1
      else:
        logError(
          "Economy",
          &"Construction start failed at {command.colonyId}",
        )
        budgetContext.rejectedCommands += 1

  # Log budget validation summary
  let remainingBudget = budgetContext.availableTreasury - budgetContext.committedSpending
  let rejectedUnits = requestedUnits - acceptedUnits
  logInfo(
    "Economy",
    &"{packet.houseId} Build Command Summary: {acceptedUnits}/{requestedUnits} units accepted, " &
      &"{budgetContext.committedSpending} PP committed, " &
      &"{remainingBudget} PP remaining, " &
      &"{rejectedUnits} units rejected",
  )
