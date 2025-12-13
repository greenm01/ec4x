## Maintenance Phase Resolution - Phase 4 of Canonical Turn Cycle
##
## Server batch processing phase: fleet movement, construction advancement,
## diplomatic state changes, and timer updates.
##
## **Canonical Execution Order:**
##
## Step 1: Fleet Movement and Order Activation
##   1a. Order Activation
##   1b. Order Maintenance
##   1c. Fleet Movement
##
## Step 2: Construction and Repair Advancement
##   2a. Construction Queue Advancement
##   2b. Split Commissioning (Planetary Defense immediate, Military Units next turn)
##   2c. Repair Queue
##
## Step 3: Diplomatic Actions
##
## Step 4: Population Transfers
##
## Step 5: Terraforming
##
## Step 6: Cleanup and Preparation
##
## **Key Properties:**
## - Split Commissioning: Planetary defenses commission immediately (Step 2b)
## - Military units (ships) are stored and commissioned next turn (Command Phase Part A)
## - Fleet movement positions units for next turn's Conflict Phase

import std/[tables, options, strformat, strutils, algorithm, sequtils, random, sets]
import ../../../common/[types/core, types/units, types/tech, types/combat]
import ../../gamestate, ../../orders, ../../logger, ../../starmap
import ../../order_types
import ../fleet_order_execution  # For movement order execution
import ../../economy/[types as econ_types, engine as econ_engine, facility_queue]
import ../../research/[types as res_types, advancement]
import ../commissioning  # For planetary defense commissioning
import ../../espionage/[types as esp_types]
import ../../diplomacy/[proposals as dip_proposals]
import ../../population/[types as pop_types]
import ../../config/[gameplay_config, population_config]
import ../[types as res_types_common]
import ../fleet_orders  # For findClosestOwnedColony
import ../diplomatic_resolution
import ../event_factory/init as event_factory
import ../../prestige
import ../../standing_orders  # For standing order activation

# Forward declaration for helper procs
proc resolvePopulationArrivals*(state: var GameState, events: var seq[GameEvent])
proc processTerraformingProjects(state: var GameState,events: var seq[GameEvent])

proc resolvePopulationArrivals*(state: var GameState, events: var seq[GameEvent]) =
  ## Process Space Guild population transfers that arrive this turn
  ## Implements risk handling per config/population.toml [transfer_risks]
  ## Per config: dest_blockaded_behavior = "closest_owned"
  ## Per config: dest_collapsed_behavior = "closest_owned"
  logDebug(LogCategory.lcGeneral, &"[Processing Space Guild Arrivals]")

  var arrivedTransfers: seq[int] = @[]  # Indices to remove after processing

  for idx, transfer in state.populationInTransit:
    if transfer.arrivalTurn != state.turn:
      continue  # Not arriving this turn

    let soulsToDeliver = transfer.ptuAmount * soulsPerPtu()

    # Check destination status
    if transfer.destSystem notin state.colonies:
      # Destination colony no longer exists
      logWarn(LogCategory.lcEconomy,
        &"Transfer {transfer.id}: {transfer.ptuAmount} PTU LOST - " &
        &"destination colony destroyed")
      arrivedTransfers.add(idx)
      events.add(event_factory.populationTransfer(
        transfer.houseId,
        transfer.ptuAmount,
        transfer.sourceSystem,
        transfer.destSystem,
        false,
        "destination destroyed"
      ))
      continue

    var destColony = state.colonies[transfer.destSystem]

    # Check if destination requires alternative delivery
    # Space Guild makes best-faith effort to deliver somewhere safe
    # Per config/population.toml: dest_blockaded_behavior = "closest_owned"
    # Per config/population.toml: dest_collapsed_behavior = "closest_owned"
    # Per config/population.toml: dest_conquered_behavior = "closest_owned"
    var needsAlternativeDestination = false
    var alternativeReason = ""

    if destColony.owner != transfer.houseId:
      # Destination conquered - Guild tries to find alternative colony
      needsAlternativeDestination = true
      alternativeReason = "conquered by " & $destColony.owner
    elif destColony.blockaded:
      needsAlternativeDestination = true
      alternativeReason = "blockaded"
    elif destColony.souls < soulsPerPtu():
      needsAlternativeDestination = true
      alternativeReason = "collapsed below minimum viable population"

    if needsAlternativeDestination:
      # Space Guild attempts to deliver to closest owned colony
      let alternativeDest = findClosestOwnedColony(state, transfer.destSystem,
                                                   transfer.houseId)

      if alternativeDest.isSome:
        # Deliver to alternative colony
        let altSystemId = alternativeDest.get()
        var altColony = state.colonies[altSystemId]
        altColony.souls += soulsToDeliver
        altColony.population = altColony.souls div 1_000_000
        state.colonies[altSystemId] = altColony

        logWarn(LogCategory.lcEconomy,
          &"Transfer {transfer.id}: {transfer.ptuAmount} PTU redirected to " &
          &"{altSystemId} - original destination {transfer.destSystem} " &
          &"{alternativeReason}")
        events.add(event_factory.populationTransfer(
          transfer.houseId,
          transfer.ptuAmount,
          transfer.sourceSystem,
          altSystemId,
          true,
          &"redirected from {transfer.destSystem} ({alternativeReason})"
        ))
      else:
        # No owned colonies - colonists are lost
        logWarn(LogCategory.lcEconomy,
          &"Transfer {transfer.id}: {transfer.ptuAmount} PTU LOST - " &
          &"destination {alternativeReason}, no owned colonies available")
        events.add(event_factory.populationTransfer(
          transfer.houseId,
          transfer.ptuAmount,
          transfer.sourceSystem,
          transfer.destSystem,
          false,
          &"{alternativeReason}, no owned colonies for delivery"
        ))

      arrivedTransfers.add(idx)
      continue

    # Successful delivery!
    destColony.souls += soulsToDeliver
    destColony.population = destColony.souls div 1_000_000
    state.colonies[transfer.destSystem] = destColony

    logInfo(LogCategory.lcEconomy,
      &"Transfer {transfer.id}: {transfer.ptuAmount} PTU arrived at " &
      &"{transfer.destSystem} ({soulsToDeliver} souls)")
    events.add(event_factory.populationTransfer(
      transfer.houseId,
      transfer.ptuAmount,
      transfer.sourceSystem,
      transfer.destSystem,
      true,
      ""
    ))

    arrivedTransfers.add(idx)

  # Remove processed transfers (in reverse order to preserve indices)
  for idx in countdown(arrivedTransfers.len - 1, 0):
    state.populationInTransit.del(arrivedTransfers[idx])

proc processTerraformingProjects(state: var GameState,
                                  events: var seq[GameEvent]) =
  ## Process active terraforming projects for all houses
  ## Per economy.md Section 4.7

  for colonyId, colony in state.colonies.mpairs:
    if colony.activeTerraforming.isNone:
      continue

    let houseId = colony.owner
    if houseId notin state.houses:
      continue

    let house = state.houses[houseId]
    var project = colony.activeTerraforming.get()
    project.turnsRemaining -= 1

    if project.turnsRemaining <= 0:
      # Terraforming complete!
      # Convert int class number (1-7) back to PlanetClass enum (0-6)
      colony.planetClass = PlanetClass(project.targetClass - 1)
      colony.activeTerraforming = none(TerraformProject)

      let className = case project.targetClass
        of 1: "Extreme"
        of 2: "Desolate"
        of 3: "Hostile"
        of 4: "Harsh"
        of 5: "Benign"
        of 6: "Lush"
        of 7: "Eden"
        else: "Unknown"

      logInfo(LogCategory.lcEconomy,
        &"{house.name} completed terraforming of {colonyId} to {className} " &
        &"(class {project.targetClass})")

      events.add(event_factory.terraformComplete(
        houseId,
        colonyId,
        className
      ))
    else:
      logDebug(LogCategory.lcEconomy,
        &"{house.name} terraforming {colonyId}: {project.turnsRemaining} " &
        &"turn(s) remaining")
      # Update project
      colony.activeTerraforming = some(project)

proc resolveMaintenancePhase*(state: var GameState,
                              events: var seq[GameEvent],
                              orders: Table[HouseId, OrderPacket],
                              rng: var Rand):
                              seq[econ_types.CompletedProject] =
  ## Phase 4: Upkeep, effect decrements, and diplomatic status updates
  ## Returns completed projects for commissioning in next turn's Command Phase
  logInfo(LogCategory.lcOrders, &"=== Maintenance Phase === (turn={state.turn})")

  result = @[]  # Will collect completed projects from construction queues

  # ===================================================================
  # STEP 1: FLEET MOVEMENT
  # ===================================================================
  # Per FINAL_TURN_SEQUENCE.md: "Movement orders execute Turn N Maintenance Phase"

  # Step 1a: Activate ALL orders (both active and standing)
  # - Active orders: Already validated in Command Phase Part C, now become "active"
  # - Standing orders: Check activation conditions, generate fleet orders
  # Standing orders generate fleet orders (Move, Colonize, SeekHome, etc.)
  # These are written to state.fleetOrders and picked up by Step 1b/1c
  # Phase 7b: Emits StandingOrderActivated/Suspended events
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 1a] Activating orders (active + standing)...")

  # Activate active orders (already validated and stored in state.fleetOrders)
  # "Activation" means orders are now ready for processing in Steps 1b/1c
  let activeOrderCount = state.fleetOrders.len
  logInfo(LogCategory.lcOrders, &"  Active orders: {activeOrderCount} orders ready for processing")

  # Activate standing orders (check conditions, generate new fleet orders)
  let standingOrdersBefore = state.fleetOrders.len
  standing_orders.activateStandingOrders(state, state.turn, events)
  let standingOrdersGenerated = state.fleetOrders.len - standingOrdersBefore
  logInfo(LogCategory.lcOrders, &"  Standing orders: {standingOrdersGenerated} orders generated")

  logInfo(LogCategory.lcOrders, &"[MAINTENANCE STEP 1a] Order activation complete ({state.fleetOrders.len} total orders)")

  # Step 1b: Perform order maintenance (check completions, validate conditions)
  # Includes orders generated by standing orders in Step 1a
  # This is NOT execution - just lifecycle management
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 1b] Performing order maintenance...")
  var combatReports: seq[res_types_common.CombatReport] = @[]
  fleet_order_execution.performOrderMaintenance(
    state,
    orders,
    events,
    combatReports,
    rng,
    isMovementOrder,  # Filter: only movement orders
    "Maintenance Phase - Fleet Movement"
  )
  logInfo(LogCategory.lcOrders, &"[MAINTENANCE STEP 1b] Order maintenance complete ({combatReports.len} orders processed)")

  # Build set of fleets with completed orders for O(1) lookup in Step 1c
  var completedFleetOrders = initHashSet[FleetId]()
  for event in events:
    if event.eventType == res_types_common.GameEventType.OrderCompleted and
       event.fleetId.isSome:
      completedFleetOrders.incl(event.fleetId.get())

  # ===================================================================
  # STEP 1c: MOVE FLEETS TOWARD PERSISTENT ORDER TARGETS
  # ===================================================================
  # For all persistent orders (except movement orders already handled in Step 1b),
  # move fleets toward their target systems via pathfinding.
  # This allows multi-turn missions: fleet travels incrementally each turn.

  logInfo(LogCategory.lcOrders, &"[MAINTENANCE STEP 1c] Moving fleets toward order targets... ({state.fleetOrders.len} persistent orders)")

  var fleetsMovedCount = 0

  for fleetId, persistentOrder in state.fleetOrders:
    # Skip if fleet doesn't exist
    if fleetId notin state.fleets:
      continue

    let fleet = state.fleets[fleetId]

    # Filter 1: Skip orders without target systems
    if persistentOrder.targetSystem.isNone:
      continue

    # Filter 2: Skip Hold orders (explicit "stay here")
    if persistentOrder.orderType == FleetOrderType.Hold:
      continue

    let targetSystem = persistentOrder.targetSystem.get()

    # Check 1: Skip if order already completed this turn (event-based)
    if fleetId in completedFleetOrders:
      logDebug(LogCategory.lcOrders, &"  {fleetId} order completed, no movement needed")
      continue

    # Check 2: Skip if fleet already at target
    if fleet.location == targetSystem:
      logDebug(LogCategory.lcOrders, &"  {fleetId} already at target {targetSystem}")
      continue

    logDebug(LogCategory.lcOrders, &"  Moving {fleetId} toward {targetSystem} for {persistentOrder.orderType} order")

    # Pathfinding: Find route from current location to target
    # CRITICAL: findPath() respects lane restrictions based on fleet composition:
    # - Fleet with crippled ships: Major lanes only (via canFleetTraverseLane)
    # - Fleet with ETACs/TroopTransports: Major + Minor lanes only
    # - Fleet with no restrictions: All lanes available
    let pathResult = state.starMap.findPath(fleet.location, targetSystem, fleet)

    if not pathResult.found or pathResult.path.len == 0:
      logWarn(LogCategory.lcOrders, &"  No path found for {fleetId} from {fleet.location} to {targetSystem} (lane restrictions may apply)")
      continue

    # Determine max jumps per turn (1-2 based on territory control and lane types)
    var maxJumps = 1  # Default: 1 jump per turn

    # 2-jump rule: All systems owned by house AND both jumps are Major lanes
    if pathResult.path.len >= 3:  # Need at least 2 intermediate jumps available
      var allSystemsOwned = true
      var nextTwoAreMajor = true

      # Check ownership of all systems in path
      for systemId in pathResult.path:
        if systemId notin state.colonies or
           state.colonies[systemId].owner != fleet.owner:
          allSystemsOwned = false
          break

      # Check if next 2 jumps are Major lanes
      if allSystemsOwned:
        for i in 0..<min(2, pathResult.path.len - 1):
          let fromSys = pathResult.path[i]
          let toSys = pathResult.path[i + 1]

          let laneType = state.starMap.getLaneType(fromSys, toSys)
          if laneType.isNone or laneType.get() != LaneType.Major:
            nextTwoAreMajor = false
            break

        if nextTwoAreMajor:
          maxJumps = 2

    # Move fleet along path (1 or 2 jumps)
    let jumpsToMove = min(maxJumps, pathResult.path.len - 1)
    let newLocation = pathResult.path[jumpsToMove]

    # Update fleet location
    state.fleets[fleetId].location = newLocation
    fleetsMovedCount += 1

    logDebug(LogCategory.lcOrders, &"  Moved {fleetId} {jumpsToMove} jump(s) to {newLocation}")

  logInfo(LogCategory.lcOrders, &"[MAINTENANCE STEP 1c] Completed ({fleetsMovedCount} fleets moved toward targets)")

  # ===================================================================
  # STEP 1d: DETECT FLEET ARRIVALS AT ORDER TARGETS
  # ===================================================================
  # Check which fleets have arrived at their order targets
  # Generate FleetArrived events for execution in Conflict/Income phases

  logDebug(LogCategory.lcOrders, "[MAINTENANCE STEP 1d] Checking for fleet arrivals...")

  var arrivedFleetCount = 0

  for fleetId, order in state.fleetOrders:
    # Skip if fleet doesn't exist
    if fleetId notin state.fleets:
      continue

    let fleet = state.fleets[fleetId]

    # Skip if order has no target system
    if order.targetSystem.isNone:
      continue

    let targetSystem = order.targetSystem.get()

    # Check if fleet is at target system
    if fleet.location == targetSystem:
      # Generate FleetArrived event
      events.add(event_factory.fleetArrived(
        fleet.owner,
        fleetId,
        $order.orderType,  # Convert enum to string
        targetSystem
      ))

      # Track arrival for Conflict/Income phase execution
      state.arrivedFleets[fleetId] = targetSystem
      arrivedFleetCount += 1

      logDebug(LogCategory.lcOrders,
        &"  Fleet {fleetId} arrived at {targetSystem} (order: {order.orderType})")

  logInfo(LogCategory.lcOrders,
    &"[MAINTENANCE STEP 1d] Completed ({arrivedFleetCount} fleets arrived at targets)")

  # ===================================================================
  # STEP 2: CONSTRUCTION & REPAIR ADVANCEMENT
  # ===================================================================
  # Advance construction queues for both facilities (capital ships) and
  # colonies (fighters/buildings)
  logInfo(LogCategory.lcEconomy, "[MAINTENANCE STEP 2] Advancing construction & repair queues...")
  let maintenanceReport = econ_engine.tickConstructionAndRepair(state, events)

  # Split completed projects by commissioning phase
  var planetaryProjects: seq[econ_types.CompletedProject] = @[]
  var militaryProjects: seq[econ_types.CompletedProject] = @[]

  for project in maintenanceReport.completedProjects:
    if facility_queue.isPlanetaryDefense(project):
      planetaryProjects.add(project)
    else:
      militaryProjects.add(project)

  # Step 2b: Commission planetary defense immediately (same turn)
  if planetaryProjects.len > 0:
    logInfo(LogCategory.lcEconomy,
      &"[MAINTENANCE STEP 2b] Commissioning {planetaryProjects.len} planetary defense assets")
    commissioning.commissionPlanetaryDefense(state, planetaryProjects, events)

  # Collect ship projects for next turn's Command Phase commissioning
  result.add(militaryProjects)

  logInfo(LogCategory.lcEconomy,
    &"[MAINTENANCE STEP 2] Completed ({planetaryProjects.len} planetary commissioned, " &
    &"{militaryProjects.len} ships pending)")

  # ===================================================================
  # STEP 3: DIPLOMATIC ACTIONS
  # ===================================================================
  # Process diplomatic actions (moved from Command Phase)
  # Diplomatic state changes happen AFTER all commands execute
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 3] Processing diplomatic actions...")
  diplomatic_resolution.resolveDiplomaticActions(state, orders, events)
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 3] Completed diplomatic actions")

  # ===================================================================
  # STEP 4: POPULATION TRANSFERS
  # ===================================================================
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 4] Processing population transfers...")
  resolvePopulationArrivals(state, events)
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 4] Completed population transfers")

  # ===================================================================
  # STEP 5: TERRAFORMING
  # ===================================================================
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 5] Processing terraforming projects...")
  processTerraformingProjects(state, events)
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 5] Completed terraforming projects")

  # ===================================================================
  # STEP 6: CLEANUP AND PREPARATION
  # ===================================================================
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 6] Performing cleanup...")
  # Timer logic moved to Income Phase Step 9.
  # Other cleanup (destroyed entities, fog of war) is handled implicitly
  # by other systems or is not yet implemented.
  logInfo(LogCategory.lcOrders, "[MAINTENANCE STEP 6] Cleanup complete")

   # ===================================================================
  # RESEARCH ADVANCEMENT
  # ===================================================================
  # Process tech advancements
  # Per economy.md:4.1: Tech upgrades can be purchased EVERY TURN if RP
  # is available
  logInfo(LogCategory.lcOrders, "[MAINTENANCE] Processing research advancements...")

  # Research breakthroughs (every 5 turns)
  # Per economy.md:4.1.1: Breakthrough rolls provide bonus RP, cost reductions, or free levels
  if advancement.isBreakthroughTurn(state.turn):
    logDebug(LogCategory.lcResearch, &"[RESEARCH BREAKTHROUGHS] Turn {state.turn} - rolling for breakthroughs")
    for houseId in state.houses.keys:
      # Calculate total RP invested in last 5 turns
      # NOTE: This is a simplified approximation - proper implementation would track historical RP
      let investedRP = state.houses[houseId].lastTurnResearchERP +
                       state.houses[houseId].lastTurnResearchSRP +
                       state.houses[houseId].lastTurnResearchTRP

      # Roll for breakthrough
      var rng = initRand(hash(state.turn) xor hash(houseId))
      let breakthroughOpt = advancement.rollBreakthrough(investedRP * 5, rng)  # Approximate 5-turn total

      if breakthroughOpt.isSome:
        let breakthrough = breakthroughOpt.get
        logInfo(LogCategory.lcResearch, &"{houseId} BREAKTHROUGH: {breakthrough}")

        # Apply breakthrough effects
        let allocation = res_types.ResearchAllocation(
          economic: state.houses[houseId].lastTurnResearchERP,
          science: state.houses[houseId].lastTurnResearchSRP,
          technology: initTable[TechField, int]()
        )
        let event = advancement.applyBreakthrough(
          state.houses[houseId].techTree,
          breakthrough,
          allocation
        )

        logDebug(LogCategory.lcResearch, &"{houseId} breakthrough effect applied (category: {event.category})")

  var totalAdvancements = 0
  for houseId, house in state.houses.mpairs:
    # Try to advance Economic Level (EL) with accumulated ERP
    let currentEL = house.techTree.levels.economicLevel
    let elAdv = attemptELAdvancement(house.techTree, currentEL)
    if elAdv.isSome:
      totalAdvancements += 1
      let adv = elAdv.get()
      logInfo(LogCategory.lcResearch,
        &"{house.name}: EL {adv.elFromLevel} → {adv.elToLevel} " &
        &"(spent {adv.elCost} ERP)")
      if adv.prestigeEvent.isSome:
        applyPrestigeEvent(state, houseId, adv.prestigeEvent.get())
        logDebug(LogCategory.lcResearch,
          &"+{adv.prestigeEvent.get().amount} prestige")
      events.add(event_factory.techAdvance(
        houseId,
        "Economic Level",
        adv.elToLevel
      ))

    # Try to advance Science Level (SL) with accumulated SRP
    let currentSL = house.techTree.levels.scienceLevel
    let slAdv = attemptSLAdvancement(house.techTree, currentSL)
    if slAdv.isSome:
      totalAdvancements += 1
      let adv = slAdv.get()
      logInfo(LogCategory.lcResearch,
        &"{house.name}: SL {adv.slFromLevel} → {adv.slToLevel} " &
        &"(spent {adv.slCost} SRP)")
      if adv.prestigeEvent.isSome:
        applyPrestigeEvent(state, houseId, adv.prestigeEvent.get())
        logDebug(LogCategory.lcResearch,
          &"+{adv.prestigeEvent.get().amount} prestige")
      events.add(event_factory.techAdvance(
        houseId,
        "Science Level",
        adv.slToLevel
      ))

    # Try to advance technology fields with accumulated TRP
    for field in [TechField.ConstructionTech, TechField.WeaponsTech,
                  TechField.TerraformingTech, TechField.ElectronicIntelligence,
                  TechField.CounterIntelligence]:
      let advancement = attemptTechAdvancement(state, houseId, house.techTree, field)
      if advancement.isSome:
        totalAdvancements += 1
        let adv = advancement.get()
        logInfo(LogCategory.lcResearch,
          &"{house.name}: {field} {adv.techFromLevel} → " &
          &"{adv.techToLevel} (spent {adv.techCost} TRP)")

        # Apply prestige if available
        if adv.prestigeEvent.isSome:
          applyPrestigeEvent(state, houseId, adv.prestigeEvent.get())
          logDebug(LogCategory.lcResearch,
            &"+{adv.prestigeEvent.get().amount} prestige")

        # Generate event
        events.add(event_factory.techAdvance(
          houseId,
          $field,
          adv.techToLevel
        ))

  logInfo(LogCategory.lcOrders, &"[MAINTENANCE] Research advancements completed ({totalAdvancements} total advancements)")
