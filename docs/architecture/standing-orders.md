# Standing Orders System Design

## Overview

Standing orders are persistent fleet behaviors that execute automatically when no explicit order is given for a turn. This reduces micromanagement and provides quality-of-life improvements for both human players and AI.

## Integration with Existing Systems

### ROE (Rules of Engagement)
- Standing orders respect per-fleet ROE settings (0-10)
- ROE affects combat decisions during standing order execution
- Example: Patrol with ROE=2 → retreat from stronger forces
- Example: Guard with ROE=8 → fight unless outnumbered 4:1

### Fleet Orders (Existing)
- `GameState.fleetOrders: Table[FleetId, FleetOrder]` stores persistent orders
- Standing orders are a **type** of persistent order
- Explicit orders override standing orders for one turn only
- After explicit order completes, fleet resumes standing order

## Type System

```nim
type
  StandingOrderType* {.pure.} = enum
    ## Persistent fleet behaviors (continue until cancelled)
    None              # No standing order (default)
    PatrolRoute       # Follow patrol path indefinitely
    DefendSystem      # Guard system, engage hostile forces per ROE
    AutoColonize      # ETACs auto-colonize nearest suitable system
    AutoReinforce     # Join nearest friendly fleet when damaged
    AutoRepair        # Return to nearest shipyard when HP < threshold
    AutoEvade         # Fall back to safe system if outnumbered per ROE
    TradeRoute        # Execute trade route repeatedly (future)
    GuardColony       # Defend specific colony system
    BlockadeTarget    # Maintain blockade on enemy colony

  StandingOrderParams* = object
    ## Parameters for standing order execution
    case orderType*: StandingOrderType
    of PatrolRoute:
      patrolSystems*: seq[SystemId]     # Patrol path (loops)
      patrolIndex*: int                 # Current position in path
    of DefendSystem, GuardColony:
      targetSystem*: SystemId           # System to defend
      maxRange*: int                    # Max distance from target (jumps)
    of AutoColonize:
      preferredPlanetClasses*: seq[PlanetClass]  # Priority classes
      maxRange*: int                    # Max colonization distance
    of AutoReinforce:
      damageThreshold*: float           # HP% to trigger (e.g., 0.5 = 50%)
      targetFleet*: Option[FleetId]     # Specific fleet, or nearest
    of AutoRepair:
      damageThreshold*: float           # HP% to trigger
      targetShipyard*: Option[SystemId] # Specific shipyard, or nearest
    of AutoEvade:
      fallbackSystem*: SystemId         # Safe retreat destination
      triggerRatio*: float              # Strength ratio to retreat
    of BlockadeTarget:
      targetColony*: SystemId           # Colony to blockade
    else:
      discard

  StandingOrder* = object
    ## Complete standing order specification
    fleetId*: FleetId
    orderType*: StandingOrderType
    params*: StandingOrderParams
    roe*: int                          # Rules of Engagement (0-10)
    createdTurn*: int                  # When order was issued
    lastExecutedTurn*: int             # Last turn this executed
    executionCount*: int               # Times executed
    suspended*: bool                   # Temporarily disabled (explicit order override)
```

## Execution Logic

### Command Phase Integration

Standing orders execute in Command Phase **after** explicit orders are processed:

```nim
proc executeStandingOrders*(state: var GameState, turn: int) =
  ## Execute standing orders for fleets without explicit orders
  ## Called in Command Phase after explicit orders processed

  logInfo(LogCategory.lcOrders,
          &"=== Standing Orders Execution: Turn {turn} ===")

  var executedCount = 0
  var skippedCount = 0
  var failedCount = 0

  for fleetId, fleet in state.fleets:
    # Skip if fleet has explicit order this turn
    if fleetId in state.fleetOrders:
      let explicitOrder = state.fleetOrders[fleetId]
      logDebug(LogCategory.lcOrders,
               &"{fleetId} has explicit order ({explicitOrder.orderType}), " &
               &"skipping standing order")
      skippedCount += 1
      continue

    # Check for standing order
    if fleetId in state.standingOrders:
      let standingOrder = state.standingOrders[fleetId]

      if standingOrder.suspended:
        logDebug(LogCategory.lcOrders,
                 &"{fleetId} standing order suspended, skipping")
        skippedCount += 1
        continue

      # Execute standing order
      let result = executeStandingOrder(state, fleetId, standingOrder, turn)

      if result.success:
        executedCount += 1
        logInfo(LogCategory.lcOrders,
                &"{fleetId} executed standing order: {standingOrder.orderType} " &
                &"→ {result.action}")

        # Update execution tracking
        var updatedOrder = standingOrder
        updatedOrder.lastExecutedTurn = turn
        updatedOrder.executionCount += 1
        state.standingOrders[fleetId] = updatedOrder
      else:
        failedCount += 1
        logWarn(LogCategory.lcOrders,
                &"{fleetId} standing order failed: {result.error}")

  logInfo(LogCategory.lcOrders,
          &"Standing Orders Summary: {executedCount} executed, " &
          &"{skippedCount} skipped (explicit orders), {failedCount} failed")
```

### Order Type Execution Examples

#### 1. Patrol Route
```nim
proc executePatrolRoute(state: var GameState, fleetId: FleetId,
                       params: StandingOrderParams): ExecutionResult =
  ## Move to next system in patrol path
  let fleet = state.fleets[fleetId]
  let currentIndex = params.patrolIndex
  let nextSystem = params.patrolSystems[currentIndex]

  # Generate move order
  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(nextSystem),
    priority: 100  # Standing orders have lower priority
  )

  # Log patrol movement
  logInfo(LogCategory.lcOrders,
          &"{fleetId} Patrol: {fleet.location} → {nextSystem} " &
          &"(step {currentIndex + 1}/{params.patrolSystems.len})")

  # Advance patrol index (loop)
  var newParams = params
  newParams.patrolIndex = (currentIndex + 1) mod params.patrolSystems.len

  state.fleetOrders[fleetId] = moveOrder
  return ExecutionResult(success: true,
                        action: &"Move to {nextSystem}",
                        updatedParams: some(newParams))
```

#### 2. Auto-Colonize (ETACs)
```nim
proc executeAutoColonize(state: var GameState, fleetId: FleetId,
                        params: StandingOrderParams): ExecutionResult =
  ## Find and colonize nearest suitable system
  let fleet = state.fleets[fleetId]

  # Verify fleet has ETAC capability
  if not fleet.hasSpaceLiftShip(SpaceLiftCargo.Colonists):
    return ExecutionResult(success: false,
                          error: "Fleet has no colonization capability")

  # Find nearest uncolonized system within range
  let candidates = findUncolonizedSystems(state, fleet.location,
                                          params.maxRange,
                                          params.preferredPlanetClasses)

  if candidates.len == 0:
    logDebug(LogCategory.lcOrders,
             &"{fleetId} Auto-Colonize: No suitable systems within {params.maxRange} jumps")
    return ExecutionResult(success: false,
                          error: "No colonization targets available")

  # Pick best candidate (closest, preferred class)
  let target = selectBestColonizationTarget(candidates, params)

  # Generate colonize order
  let colonizeOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Colonize,
    targetSystem: some(target.systemId),
    priority: 100
  )

  logInfo(LogCategory.lcOrders,
          &"{fleetId} Auto-Colonize: Targeting system-{target.systemId} " &
          &"(class {target.planetClass}, {target.distance} jumps)")

  state.fleetOrders[fleetId] = colonizeOrder
  return ExecutionResult(success: true,
                        action: &"Colonize system-{target.systemId}")
```

#### 3. Auto-Repair
```nim
proc executeAutoRepair(state: var GameState, fleetId: FleetId,
                      params: StandingOrderParams): ExecutionResult =
  ## Return to shipyard if damaged below threshold
  let fleet = state.fleets[fleetId]

  # Check fleet damage
  let avgHP = calculateAverageHP(fleet)

  if avgHP >= params.damageThreshold:
    logDebug(LogCategory.lcOrders,
             &"{fleetId} Auto-Repair: HP {avgHP:.1%} above threshold " &
             &"{params.damageThreshold:.1%}, no action needed")
    return ExecutionResult(success: true, action: "No repair needed")

  # Find nearest shipyard
  let shipyardSystem = if params.targetShipyard.isSome:
    params.targetShipyard.get()
  else:
    findNearestShipyard(state, fleet.owner, fleet.location)

  if shipyardSystem == 0:
    return ExecutionResult(success: false, error: "No shipyard available")

  # Generate move order to shipyard
  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(shipyardSystem),
    priority: 100
  )

  logInfo(LogCategory.lcOrders,
          &"{fleetId} Auto-Repair: HP {avgHP:.1%} < threshold " &
          &"{params.damageThreshold:.1%}, returning to system-{shipyardSystem}")

  state.fleetOrders[fleetId] = moveOrder
  return ExecutionResult(success: true,
                        action: &"Return to shipyard at system-{shipyardSystem}")
```

## Comprehensive Logging

### Log Categories
- **lcOrders** - Standing order creation, modification, execution
- **lcFleet** - Fleet movement, combat encounters during standing orders
- **lcAI** - AI standing order decision-making
- **lcEconomy** - Resource implications of standing orders

### Logging Levels

#### INFO - High-level execution tracking
```nim
logInfo(LogCategory.lcOrders,
        &"{fleetId} Standing Order Created: {orderType} with ROE={roe}")

logInfo(LogCategory.lcOrders,
        &"{fleetId} Patrol: system-5 → system-7 (step 2/4)")

logInfo(LogCategory.lcOrders,
        &"Standing Orders Summary: 12 executed, 3 skipped, 1 failed")
```

#### DEBUG - Detailed decision logic
```nim
logDebug(LogCategory.lcOrders,
         &"{fleetId} Auto-Colonize: Evaluating 5 candidate systems")

logDebug(LogCategory.lcOrders,
         &"{fleetId} Auto-Evade: Enemy strength 450, our strength 200, " &
         &"ratio 0.44 < ROE {roe} threshold 0.5 → evading")

logDebug(LogCategory.lcOrders,
         &"{fleetId} Auto-Repair: HP 85% above threshold 50%, no action")
```

#### WARN - Failures and issues
```nim
logWarn(LogCategory.lcOrders,
        &"{fleetId} Standing order execution failed: No valid path to target")

logWarn(LogCategory.lcOrders,
        &"{fleetId} Patrol route blocked: system-7 now enemy-controlled")
```

### Diagnostic Metrics

Add to `tests/balance/diagnostics.nim`:

```nim
# Standing Order Execution Metrics (per turn)
standing_orders_active: int           # Fleets with standing orders
standing_orders_executed: int         # Orders executed this turn
standing_orders_overridden: int       # Explicit orders given instead
standing_orders_failed: int           # Execution failures

# Standing Order Type Distribution
standing_order_patrol: int
standing_order_defend: int
standing_order_auto_colonize: int
standing_order_auto_repair: int
standing_order_auto_evade: int
```

## Benefits

### For Players
- **Reduced micromanagement**: Set patrol routes once, forget about them
- **ETACs auto-expand**: No need to issue colonize orders every turn
- **Automatic repairs**: Damaged fleets return to shipyards automatically
- **Consistent behavior**: Fleets follow doctrine without player input

### For AI
- **Simpler order generation**: Standing orders + exceptions vs all orders every turn
- **Persistent strategy**: Doctrine persists across turns
- **Better diagnostics**: Can track standing order effectiveness
- **Reduced computation**: Only generate orders for special actions

### Code Quality
- **Separation of concerns**: Standing logic separate from explicit orders
- **Comprehensive logging**: Full visibility into fleet automation
- **Testable**: Can unit test each standing order type independently
- **Extensible**: Easy to add new standing order types

## Implementation Plan

### Phase 1: Core System (1 day)
1. Add `StandingOrder` types to `order_types.nim`
2. Add `standingOrders: Table[FleetId, StandingOrder]` to GameState
3. Implement `executeStandingOrders()` in Command Phase
4. Add comprehensive logging

### Phase 2: Order Types (1 day)
1. Implement Patrol, DefendSystem, GuardColony
2. Implement Auto-Colonize for ETACs
3. Implement Auto-Repair
4. Add unit tests

### Phase 3: AI Integration (1 day)
1. Update AI to use standing orders for routine tasks
2. AI issues standing orders in setup phase
3. AI overrides with explicit orders only when needed
4. Add diagnostic metrics

### Phase 4: Validation & Testing (0.5 day)
1. Balance tests with standing orders enabled
2. Verify logging output
3. Performance testing (should be faster than current system)

**Total: ~3.5 days**

## Future Extensions
- Trade routes (automatic resource transport)
- Conditional triggers (e.g., "patrol until enemy detected")
- Complex patrol patterns (weighted systems, timing)
- Standing diplomatic orders (auto-accept certain proposals)
