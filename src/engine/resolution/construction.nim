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
## 2. Create project using economy/projects.nim factories
## 3. Route to facility queue (dock) OR colony queue (planet-side)
## 4. Deduct treasury and generate events
##
## **Separation of Concerns:**
## - economy/projects.nim: "What to build" (project definitions)
## - THIS MODULE: "How orders work" (validation, routing, treasury)
## - economy/facility_queue.nim: "Queue management" (advancement)

import std/[tables, options, strutils, strformat]
import ../../common/[hex, types/core, types/units, types/tech]
import ../gamestate, ../orders, ../logger
import ../order_types
import ../economy/[types as econ_types, projects, facility_queue]
import ../economy/capacity/construction_docks as dock_capacity
import ./types as res_types

proc resolveBuildOrders*(state: var GameState, packet: OrderPacket, events: var seq[res_types.GameEvent]) =
  ## Process construction orders for a house with budget validation
  ## Prevents overspending by tracking committed costs
  logInfo(LogCategory.lcEconomy, &"Processing build orders for {state.houses[packet.houseId].name}")

  # Initialize budget validation context
  # Use CURRENT treasury from state (NOT snapshot from OrderPacket)
  # This ensures validation matches the actual treasury after income/maintenance
  let house = state.houses[packet.houseId]
  var budgetContext = orders.initOrderValidationContext(house.treasury)

  logInfo(LogCategory.lcEconomy,
          &"{packet.houseId} Build Order Validation: {packet.buildOrders.len} orders, " &
          &"{house.treasury} PP available (current treasury after income/maintenance)")

  for order in packet.buildOrders:
    # Validate colony exists
    if order.colonySystem notin state.colonies:
      let errorMsg = &"Colony not found at system {order.colonySystem}"
      logError(LogCategory.lcEconomy, &"[BUILD ORDER REJECTED] {packet.houseId}: {errorMsg}")
      # TODO: Add to GameEvent for AI/player feedback when GameEvent system is integrated
      continue

    # Validate colony ownership
    let colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      let errorMsg = &"Colony at system {order.colonySystem} not owned by {packet.houseId} (owned by {colony.owner})"
      logError(LogCategory.lcEconomy, &"[BUILD ORDER REJECTED] {packet.houseId}: {errorMsg}")
      # TODO: Add to GameEvent for AI/player feedback when GameEvent system is integrated
      continue

    # Determine if this construction requires dock capacity
    # DOCK CONSTRUCTION: Capital ships (non-fighters) built at spaceport/shipyard facilities
    # COLONY CONSTRUCTION: Fighters, ground units, buildings, IU investment (planet-side)
    let requiresDock = (order.buildType == BuildType.Ship and
                        order.shipClass.isSome and
                        dock_capacity.shipRequiresDock(order.shipClass.get()))

    # For dock construction, check facility capacity and assign facility
    var assignedFacility: Option[tuple[facilityId: string, facilityType: econ_types.FacilityType]] = none(tuple[facilityId: string, facilityType: econ_types.FacilityType])

    if requiresDock:
      # Try to assign to available facility
      assignedFacility = dock_capacity.assignFacility(state, order.colonySystem, econ_types.ConstructionType.Ship, "")
      if assignedFacility.isNone:
        # No facility capacity available
        let (current, maximum) = dock_capacity.getColonyTotalCapacity(state, order.colonySystem)
        let errorMsg = &"System {order.colonySystem} at capacity ({current}/{maximum} docks used) - cannot accept more projects"
        logWarn(LogCategory.lcEconomy, &"[BUILD ORDER REJECTED] {packet.houseId}: {errorMsg}")
        continue

    # Validate budget BEFORE creating construction project
    let validationResult = orders.validateBuildOrderWithBudget(order, state, packet.houseId, budgetContext)
    if not validationResult.valid:
      let errorMsg = validationResult.error
      logWarn(LogCategory.lcEconomy, &"[BUILD ORDER REJECTED] {packet.houseId} at system {order.colonySystem}: {errorMsg}")
      # TODO: Add to GameEvent for AI/player feedback when GameEvent system is integrated
      continue

    # NOTE: No conversion needed! gamestate.Colony now has all economic fields
    # (populationUnits, industrial, grossOutput, taxRate, infrastructureDamage)
    # Project factory functions work directly with unified Colony type

    # Create construction project based on build type
    var project: econ_types.ConstructionProject
    var projectDesc: string

    case order.buildType
    of BuildType.Infrastructure:
      # Infrastructure investment (IU expansion)
      let units = order.industrialUnits
      if units <= 0:
        logError(LogCategory.lcEconomy, &"Infrastructure order failed: invalid unit count {units}")
        continue

      project = projects.createIndustrialProject(colony, units)
      projectDesc = "Industrial expansion: " & $units & " IU"

    of BuildType.Ship:
      # Ship construction
      if order.shipClass.isNone:
        logError(LogCategory.lcEconomy, &"Ship construction failed: no ship class specified")
        continue

      let shipClass = order.shipClass.get()
      project = projects.createShipProject(shipClass)
      projectDesc = "Ship construction: " & $shipClass

    of BuildType.Building:
      # Building construction
      if order.buildingType.isNone:
        logError(LogCategory.lcEconomy, &"Building construction failed: no building type specified")
        continue

      let buildingType = order.buildingType.get()

      # Phase F: Check planetary shield limit (max 1 per colony)
      # Shields can be rebuilt if destroyed (planetaryShieldLevel == 0)
      if buildingType.startsWith("PlanetaryShield"):
        if colony.planetaryShieldLevel > 0:
          logWarn(LogCategory.lcEconomy,
                  &"[BUILD ORDER REJECTED] {packet.houseId}: System {order.colonySystem} already has " &
                  &"planetary shield (level {colony.planetaryShieldLevel}), max 1 per colony")
          continue

      project = projects.createBuildingProject(buildingType)
      projectDesc = "Building construction: " & buildingType

    # Route construction to facility queue (capital ships) or colony queue (everything else)
    var success = false
    var queueLocation = ""

    if requiresDock and assignedFacility.isSome:
      # DOCK CONSTRUCTION: Add to facility queue
      success = dock_capacity.assignAndQueueProject(state, order.colonySystem, project)
      if success:
        let (facilityId, _) = assignedFacility.get()
        queueLocation = &"facility {facilityId}"
    else:
      # COLONY CONSTRUCTION: Add to colony queue (legacy system)
      var mutableColony = colony
      let wasOccupied = mutableColony.underConstruction.isSome

      if facility_queue.startConstruction(mutableColony, project):
        # Only add to queue if construction slot was already occupied
        if wasOccupied:
          mutableColony.constructionQueue.add(project)
        state.colonies[order.colonySystem] = mutableColony
        success = true
        queueLocation = "colony queue"

    if success:
      # CRITICAL FIX: Deduct construction cost from house treasury
      # IMPORTANT: Use get-modify-write pattern (Nim Table copy semantics!)
      var house = state.houses[packet.houseId]
      let oldTreasury = house.treasury
      house.treasury -= project.costTotal
      state.houses[packet.houseId] = house

      logInfo(LogCategory.lcEconomy,
        &"Started construction at system-{order.colonySystem}: {projectDesc} " &
        &"(Cost: {project.costTotal} PP, Est. {project.turnsRemaining} turns, " &
        &"Location: {queueLocation}, Treasury: {oldTreasury} → {house.treasury} PP)")

      # Generate event
      events.add(res_types.GameEvent(
        eventType: res_types.GameEventType.ConstructionStarted,
        houseId: packet.houseId,
        description: "Started " & projectDesc & " at system " & $order.colonySystem,
        systemId: some(order.colonySystem)
      ))
    else:
      logError(LogCategory.lcEconomy, &"Construction start failed at system-{order.colonySystem}")

  # Log budget validation summary
  let successfulOrders = packet.buildOrders.len - budgetContext.rejectedOrders
  logInfo(LogCategory.lcEconomy,
          &"{packet.houseId} Build Order Summary: {successfulOrders}/{packet.buildOrders.len} orders accepted, " &
          &"{budgetContext.committedSpending} PP committed, " &
          &"{budgetContext.getRemainingBudget()} PP remaining, " &
          &"{budgetContext.rejectedOrders} orders rejected due to insufficient funds")
