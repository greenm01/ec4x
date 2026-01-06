## Construction - Build order processing and validation
##
## This module handles Command Phase construction order submission,
## including budget validation, capacity checking, and routing to
## appropriate construction queues (facility-based or colony-based).
##
## **Dual Construction System:**
## - DOCK CONSTRUCTION: Capital ships → Spaceport/Shipyard facility queues
## - COLONY CONSTRUCTION: Fighters, buildings, IU → Colony queues
##
## **Phase:** Command Phase (after commissioning, before fleet orders)
##
## **Flow:**
## 1. Validate colony ownership and budget
## 2. Create project using projects.nim factories
## 3. Route to facility queue (dock) OR colony queue (planet-side)
## 4. Deduct treasury and generate events
##
## **Separation of Concerns:**
## - projects.nim: "What to build" (project definitions)
## - THIS MODULE: "How orders work" (validation, routing, treasury)
## - queue_advancement.nim: "Queue management" (advancement)

import std/[options, strformat]
import ../../types/[core, game_state, production, command, event]
import ../../types/[colony, facilities]
import ../../state/engine
import ../../../common/logger
import ../capacity/construction_docks
import ./queue_advancement
import ./[projects, accessors]
import ../../event_factory/economic

proc resolveBuildOrders*(
    state: var GameState, packet: CommandPacket, events: var seq[GameEvent]
) =
  ## Process construction orders for a house with budget validation
  ## Prevents overspending by tracking committed costs
  let house = state.house(packet.houseId).get()
  logInfo(
    "Economy",
    &"Processing build orders for {house.name}",
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
    &"{packet.houseId} Build Order Validation: {packet.buildCommands.len} orders, " &
      &"{house.treasury} PP available (current treasury after income/maintenance)",
  )

  for command in packet.buildCommands:
    # Validate colony exists
    let colonyOpt = state.colony(command.colonyId)
    if colonyOpt.isNone:
      let errorMsg = &"Colony not found at {command.colonyId}"
      logError(
        "Economy", &"[BUILD ORDER REJECTED] {packet.houseId}: {errorMsg}"
      )
      # TODO: Add to GameEvent for AI/player feedback when GameEvent system is integrated
      continue

    # Validate colony ownership
    let colony = colonyOpt.get()
    if colony.owner != packet.houseId:
      let errorMsg =
        &"Colony at {command.colonyId} not owned by {packet.houseId} (owned by {colony.owner})"
      logError(
        "Economy", &"[BUILD ORDER REJECTED] {packet.houseId}: {errorMsg}"
      )
      # TODO: Add to GameEvent for AI/player feedback when GameEvent system is integrated
      continue

    # Determine if this construction requires dock capacity
    # DOCK CONSTRUCTION: Capital ships (non-fighters) built at spaceport/shipyard facilities
    # COLONY CONSTRUCTION: Fighters, ground units, buildings, IU investment (planet-side)
    let requiresDock = (
      command.buildType == BuildType.Ship and command.shipClass.isSome and
      construction_docks.shipRequiresDock(command.shipClass.get())
    )

    # For dock construction, check facility capacity and assign facility
    var assignedFacility:
      Option[tuple[facilityId: NeoriaId, facilityType: NeoriaClass]] =
      none(tuple[facilityId: NeoriaId, facilityType: NeoriaClass])

    if requiresDock:
      # Try to assign to available facility
      assignedFacility = construction_docks.assignFacility(
        state, command.colonyId, BuildType.Ship, ""
      )
      if assignedFacility.isNone:
        # No facility capacity available
        let (current, maximum) =
          construction_docks.getColonyTotalCapacity(state, command.colonyId)
        let errorMsg =
          &"Colony {command.colonyId} at capacity ({current}/{maximum} docks used) - cannot accept more projects"
        logWarn(
          "Economy", &"[BUILD ORDER REJECTED] {packet.houseId}: {errorMsg}"
        )
        continue

    # Budget validation: Check if treasury has enough funds
    # Simple check since costs are paid upfront
    let projectCost = case command.buildType
      of BuildType.Ship:
        if command.shipClass.isSome:
          accessors.getShipConstructionCost(command.shipClass.get())
        else:
          0'i32
      of BuildType.Facility:
        if command.facilityClass.isSome:
          accessors.getBuildingCost(command.facilityClass.get())
        else:
          0'i32
      of BuildType.Industrial, BuildType.Infrastructure:
        projects.getIndustrialUnitCost(colony) * command.industrialUnits
      of BuildType.Ground:
        0'i32  # TODO: Implement ground unit costs

    if budgetContext.availableTreasury - budgetContext.committedSpending < projectCost:
      let errorMsg = &"Insufficient funds: need {projectCost} PP, have {budgetContext.availableTreasury - budgetContext.committedSpending} PP"
      logWarn(
        "Economy",
        &"[BUILD ORDER REJECTED] {packet.houseId} at {command.colonyId}: {errorMsg}",
      )
      budgetContext.rejectedCommands += 1
      continue

    # Reserve funds
    budgetContext.committedSpending += projectCost

    # NOTE: No conversion needed! gamestate.Colony now has all economic fields
    # (populationUnits, industrial, grossOutput, taxRate, infrastructureDamage)
    # Project factory functions work directly with unified Colony type

    # Create construction project based on build type
    var project: ConstructionProject
    var projectDesc: string

    case command.buildType
    of BuildType.Industrial, BuildType.Infrastructure:
      # Infrastructure investment (IU expansion)
      let units = command.industrialUnits
      if units <= 0:
        logError(
          "Economy",
          &"Infrastructure order failed: invalid unit count {units}",
        )
        continue

      project = createIndustrialProject(colony, units)
      projectDesc = "Industrial expansion: " & $units & " IU"
    of BuildType.Ship:
      # Ship construction
      if command.shipClass.isNone:
        logError(
          "Economy", &"Ship construction failed: no ship class specified"
        )
        continue

      let shipClass = command.shipClass.get()
      project = createShipProject(shipClass)
      projectDesc = "Ship construction: " & $shipClass
    of BuildType.Facility:
      # Facility construction
      if command.facilityClass.isNone:
        logError(
          "Economy",
          &"Facility construction failed: no facility class specified",
        )
        continue

      let facilityClass = command.facilityClass.get()
      project = createBuildingProject(facilityClass)
      projectDesc = "Facility construction: " & $facilityClass
    of BuildType.Ground:
      # Ground unit construction
      logError("Economy", "Ground unit construction not yet implemented")
      continue

    # Route construction to facility queue (capital ships) or colony queue (everything else)
    var success = false
    var queueLocation = ""

    if requiresDock and assignedFacility.isSome:
      # DOCK CONSTRUCTION: Add to facility queue
      success =
        construction_docks.assignAndQueueProject(state, command.colonyId, project)
      if success:
        let (facilityId, _) = assignedFacility.get()
        queueLocation = &"facility {facilityId}"
    else:
      # COLONY CONSTRUCTION: Add to colony queue (legacy system)
      var mutableColony = colony

      if state.startConstruction(mutableColony, project):
        # Write back modified colony
        state.updateColony(command.colonyId, mutableColony)
        success = true
        queueLocation = "colony queue"

    if success:
      # CRITICAL FIX: Deduct construction cost from house treasury
      # IMPORTANT: Use get-modify-write pattern (Nim Table copy semantics!)
      var mutableHouse = state.house(packet.houseId).get()
      let oldTreasury = mutableHouse.treasury

      # TREASURY FLOOR CHECK: Prevent negative treasury (race condition protection)
      # Validation happened earlier, but treasury may have changed due to:
      # - Research spending in Income Phase
      # - Espionage spending in Income Phase
      # - Other houses' construction orders processed before this one
      if mutableHouse.treasury >= project.costTotal:
        mutableHouse.treasury -= project.costTotal
        state.updateHouse(packet.houseId, mutableHouse)

        logInfo(
          "Economy",
          &"Started construction at {command.colonyId}: {projectDesc} " &
            &"(Cost: {project.costTotal} PP, Est. {project.turnsRemaining} turns, " &
            &"Location: {queueLocation}, Treasury: {oldTreasury} → {mutableHouse.treasury} PP)",
        )

        # Generate event
        events.add(
          economic.constructionStarted(
            packet.houseId, projectDesc, colony.systemId, project.costTotal
          )
        )
      else:
        # Treasury insufficient (race condition: spent between validation and deduction)
        # Cancel construction and log error
        logError(
          "Economy",
          &"{packet.houseId} Construction CANCELLED at {command.colonyId}: {projectDesc} " &
            &"- Insufficient treasury (need {project.costTotal} PP, have {mutableHouse.treasury} PP, " &
            &"was {oldTreasury} PP at validation)",
        )

        # Remove from construction queue if it was added
        if queueLocation == "colony queue":
          var mutableColony = state.colony(command.colonyId).get()
          # Remove last added project (the one we just added)
          if mutableColony.constructionQueue.len > 0:
            discard mutableColony.constructionQueue.pop()
          state.updateColony(command.colonyId, mutableColony)

        # Increment rejected orders counter for logging
        budgetContext.rejectedCommands += 1
    else:
      logError(
        "Economy",
        &"Construction start failed at {command.colonyId}",
      )

  # Log budget validation summary
  let remainingBudget = budgetContext.availableTreasury - budgetContext.committedSpending
  let successfulOrders = packet.buildCommands.len - budgetContext.rejectedCommands
  logInfo(
    "Economy",
    &"{packet.houseId} Build Order Summary: {successfulOrders}/{packet.buildCommands.len} orders accepted, " &
      &"{budgetContext.committedSpending} PP committed, " &
      &"{remainingBudget} PP remaining, " &
      &"{budgetContext.rejectedCommands} orders rejected due to insufficient funds",
  )
