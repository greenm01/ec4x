# GOAP Phase 4 Integration - Usage Guide

## How to Integrate GOAP into Your RBA Order Generation

This guide shows how to call the Phase 1.5 GOAP strategic planning from your RBA order generation cycle.

---

## Step-by-Step Integration

### 1. Import Phase 1.5 Module

In your main order generation file (e.g., `src/ai/rba/orders/order_generation.nim`):

```nim
import ./phase1_5_goap
```

### 2. Call Phase 1.5 After Phase 1 (Requirements Generation)

```nim
proc generateOrders*(
  controller: var AIController,
  state: GameState,
  currentAct: GameAct
): Orders =

  # Phase 0: Intelligence gathering
  let filtered = filterGameStateForHouse(state, controller.houseId)
  let intelSnapshot = gatherIntelligence(controller, filtered)

  # Phase 1: Requirements generation (all 6 advisors)
  generateAllAdvisorRequirements(controller, filtered, intelSnapshot, currentAct)

  # ===== Phase 1.5: GOAP Strategic Planning (NEW) =====
  let goapConfig = defaultGOAPConfig()  # Or load from config
  let phase15Result = executePhase15_GOAP(filtered, intelSnapshot, goapConfig)

  # Store active goals in controller for visibility
  if phase15Result.plans.len > 0:
    controller.goapEnabled = true
    controller.goapLastPlanningTurn = state.turn
    controller.goapActiveGoals = phase15Result.plans.mapIt(
      $it.goal.goalType & " (conf=" & $int(it.confidence * 100) & "%)"
    )

  # Phase 2: Mediation with GOAP budget estimates
  let budgetEstimates = if phase15Result.plans.len > 0:
    some(phase15Result.budgetEstimatesStr)
  else:
    none(Table[string, int])

  let allocation = mediateAndAllocateBudget(
    controller, filtered, currentAct, budgetEstimates
  )

  # Phase 3: Execution (unchanged)
  # Phase 4: Feedback (unchanged for now)
  # ...
```

---

## Configuration

### Default Configuration

```nim
let config = defaultGOAPConfig()
# Returns:
# GOAPConfig(
#   enabled: true,
#   planningDepth: 5,
#   confidenceThreshold: 0.6,
#   maxConcurrentPlans: 5,
#   defensePriority: 0.7,
#   offensePriority: 0.5,
#   logPlans: false
# )
```

### Custom Configuration for Aggressive Strategy

```nim
let aggressiveConfig = GOAPConfig(
  enabled: true,
  planningDepth: 3,               # Shorter planning horizon
  confidenceThreshold: 0.5,        # Accept riskier plans
  maxConcurrentPlans: 7,           # More concurrent operations
  defensePriority: 0.4,            # Lower defense priority
  offensePriority: 0.9,            # Very high offense priority
  logPlans: true                   # Enable debug logging
)
```

### Custom Configuration for Turtle Strategy

```nim
let turtleConfig = GOAPConfig(
  enabled: true,
  planningDepth: 7,                # Longer planning horizon
  confidenceThreshold: 0.8,         # Only high-confidence plans
  maxConcurrentPlans: 3,            # Fewer concurrent operations
  defensePriority: 0.9,             # Very high defense priority
  offensePriority: 0.3,             # Low offense priority
  logPlans: false
)
```

### Disable GOAP (Pure RBA Mode)

```nim
let disabledConfig = GOAPConfig(
  enabled: false,
  # Other fields don't matter when disabled
  planningDepth: 0,
  confidenceThreshold: 0.0,
  maxConcurrentPlans: 0,
  defensePriority: 0.0,
  offensePriority: 0.0,
  logPlans: false
)

# Or simply:
if not shouldUseGOAP:
  return  # Skip Phase 1.5 entirely
```

---

## Phase15Result Structure

After calling `executePhase15_GOAP()`, you receive:

```nim
type Phase15Result* = object
  goals*: seq[Goal]                      # All extracted strategic goals
  plans*: seq[GOAPlan]                   # Generated plans (filtered by confidence)
  budgetEstimates*: Table[DomainType, int]    # By domain enum
  budgetEstimatesStr*: Table[string, int]     # String keys for treasurer
  planningTimeMs*: float                 # Performance metric (0.0 for now)
```

### Accessing Results

```nim
let result = executePhase15_GOAP(filtered, intel, config)

# Check if GOAP generated any plans
if result.plans.len == 0:
  echo "No viable GOAP plans generated"
else:
  echo &"Generated {result.plans.len} plans from {result.goals.len} goals"

  # Examine budget estimates
  for domain, cost in result.budgetEstimates:
    echo &"  {domain}: {cost}PP"

  # Examine individual plans
  for plan in result.plans:
    echo &"Plan: {plan.goal.goalType} - cost={plan.totalCost}PP, " &
         &"turns={plan.estimatedTurns}, confidence={plan.confidence}"
```

---

## Treasurer Integration

The treasurer automatically uses GOAP budget estimates if provided:

```nim
# In phase2_mediation.nim:
let allocation = mediateAndAllocateBudget(
  controller,
  filtered,
  currentAct,
  some(phase15Result.budgetEstimatesStr)  # Pass GOAP estimates
)

# Treasurer logs:
# "Treasurer: GOAP strategic estimates: 500PP total"
# "  - Fleet: 200PP"
# "  - Build: 150PP"
# "  - Research: 100PP"
# "  - Espionage: 50PP"
```

### Budget Shortfall Detection

If GOAP plans exceed available budget:

```nim
# Treasurer automatically logs warning:
# "Treasurer: WARNING - GOAP plans need 200PP more than available"

# This signals need for replanning (Phase 5 feature)
```

---

## Active Goals Tracking

Store active goals in controller for debugging/logging:

```nim
controller.goapEnabled = true
controller.goapLastPlanningTurn = state.turn
controller.goapActiveGoals = phase15Result.plans.mapIt(
  $it.goal.goalType & " (conf=" & $int(it.confidence * 100) & "%)"
)

# Later, Phase 2 mediation logs:
# "Active GOAP goals (3): DefendColony (conf=85%), InvadeColony (conf=70%), BuildFleet (conf=90%)"
```

---

## Example: Complete Integration

```nim
proc generateOrdersWithGOAP*(
  controller: var AIController,
  state: GameState,
  currentAct: GameAct
): Orders =
  ## RBA order generation with GOAP Phase 1.5 integration

  let filtered = filterGameStateForHouse(state, controller.houseId)
  let intel = gatherIntelligence(controller, filtered)

  # ===== Phase 1: Requirements Generation =====
  generateAllAdvisorRequirements(controller, filtered, intel, currentAct)

  # ===== Phase 1.5: GOAP Strategic Planning =====
  # Load config based on strategy
  let goapConfig = case controller.strategy
    of AIStrategy.Aggressive:
      GOAPConfig(
        enabled: true, planningDepth: 3, confidenceThreshold: 0.5,
        maxConcurrentPlans: 7, defensePriority: 0.4, offensePriority: 0.9,
        logPlans: false
      )
    of AIStrategy.Turtle:
      GOAPConfig(
        enabled: true, planningDepth: 7, confidenceThreshold: 0.8,
        maxConcurrentPlans: 3, defensePriority: 0.9, offensePriority: 0.3,
        logPlans: false
      )
    else:
      defaultGOAPConfig()  # Balanced configuration

  let phase15Result = executePhase15_GOAP(filtered, intel, goapConfig)

  # Update controller state
  if phase15Result.plans.len > 0:
    controller.goapEnabled = true
    controller.goapLastPlanningTurn = state.turn
    controller.goapActiveGoals = @[]

    for plan in phase15Result.plans:
      let goalDesc = &"{plan.goal.goalType} (cost={plan.totalCost}PP, " &
                     &"conf={int(plan.confidence * 100)}%)"
      controller.goapActiveGoals.add(goalDesc)

  # ===== Phase 2: Mediation with GOAP Estimates =====
  let budgetEstimates = if phase15Result.plans.len > 0:
    some(phase15Result.budgetEstimatesStr)
  else:
    none(Table[string, int])

  let allocation = mediateAndAllocateBudget(
    controller, filtered, currentAct, budgetEstimates
  )

  # ===== Phase 3: Execution =====
  let orders = executeAllAdvisors(controller, allocation, filtered, currentAct)

  # ===== Phase 4: Feedback =====
  # (Will integrate replanning in Phase 5)
  processFeedback(controller, allocation)

  return orders
```

---

## Performance Monitoring

Track GOAP performance:

```nim
let result = executePhase15_GOAP(filtered, intel, config)

if result.planningTimeMs > 500.0:
  echo &"WARNING: GOAP planning took {result.planningTimeMs}ms (target <500ms)"

echo &"GOAP stats: {result.goals.len} goals → {result.plans.len} plans " &
     &"in {result.planningTimeMs}ms"
```

---

## Debugging

### Enable GOAP Logging

```nim
let debugConfig = defaultGOAPConfig()
debugConfig.logPlans = true

let result = executePhase15_GOAP(filtered, intel, debugConfig)

# Logs detailed information:
# - Each goal extracted
# - Each plan generated
# - Budget estimates by domain
# - Confidence scores
```

### Disable GOAP for A/B Testing

```nim
# Test 1: With GOAP
controller1.goapEnabled = true
let config1 = defaultGOAPConfig()
config1.enabled = true

# Test 2: Without GOAP (pure RBA)
controller2.goapEnabled = false
let config2 = defaultGOAPConfig()
config2.enabled = false

# Compare win rates, prestige, etc.
```

---

## Common Patterns

### Pattern 1: Strategy-Based Configuration

```nim
proc getGOAPConfigForStrategy(strategy: AIStrategy): GOAPConfig =
  case strategy
  of AIStrategy.Aggressive:
    result = defaultGOAPConfig()
    result.offensePriority = 0.9
    result.defensePriority = 0.4
  of AIStrategy.Turtle:
    result = defaultGOAPConfig()
    result.offensePriority = 0.3
    result.defensePriority = 0.9
  of AIStrategy.Balanced:
    result = defaultGOAPConfig()  # Use defaults
  # ... etc
```

### Pattern 2: Conditional GOAP (Only When Needed)

```nim
# Only use GOAP if at war or facing threats
let shouldUseGOAP = intel.threatAssessment.values.anyIt(it >= ThreatLevel.High)

let goapConfig = defaultGOAPConfig()
goapConfig.enabled = shouldUseGOAP

if shouldUseGOAP:
  let result = executePhase15_GOAP(filtered, intel, goapConfig)
  # ... use result
else:
  # Pure RBA mode
  discard
```

### Pattern 3: Replanning Trigger (Phase 5 Preview)

```nim
# After Phase 2 mediation, check if budget was insufficient
if allocation.treasurerFeedback.totalUnfulfilledCost > availableBudget * 0.5:
  # More than 50% of requirements unfulfilled
  # Phase 5 will trigger replanning here
  echo "GOAP replanning needed due to budget shortfall"
```

---

## Integration Checklist

When integrating Phase 1.5 into your order generation:

- [ ] Import `phase1_5_goap` module
- [ ] Call `executePhase15_GOAP()` after Phase 1
- [ ] Pass `Phase15Result.budgetEstimatesStr` to `mediateAndAllocateBudget()`
- [ ] Store active goals in `controller.goapActiveGoals`
- [ ] Set `controller.goapEnabled = true` when plans generated
- [ ] Track `controller.goapLastPlanningTurn` to prevent re-planning same turn
- [ ] Handle empty result when GOAP disabled or no plans found
- [ ] Configure GOAP parameters per strategy
- [ ] Add performance logging
- [ ] Test with GOAP enabled and disabled

---

## Next Steps (Phase 5)

Phase 5 will add:

1. **PlanTracker Integration**
   ```nim
   # Store plans in controller
   controller.goapPlanTracker = some(newPlanTracker())
   for plan in phase15Result.plans:
     controller.goapPlanTracker.get().addPlan(plan)
   ```

2. **Multi-Turn Plan Continuation**
   ```nim
   # Each turn, advance plans
   let tracker = controller.goapPlanTracker.get()
   tracker.advanceTurn(state.turn, worldState)
   ```

3. **Replanning Triggers**
   ```nim
   # In Phase 4 feedback, detect failed requirements
   if shouldReplan(tracker, allocation):
     let reason = detectReplanReason(...)
     let newPlans = replanWithBudgetConstraint(tracker, worldState, budget)
   ```

4. **Opportunistic Planning**
   ```nim
   # Detect new high-value opportunities
   let newGoals = detectNewOpportunities(currentGoals, worldState)
   integrateNewOpportunities(tracker, newGoals, worldState)
   ```

---

## Summary

Phase 4 integration is straightforward:

1. **Call Phase 1.5** between requirements and mediation
2. **Pass budget estimates** to treasurer
3. **Store active goals** for visibility
4. **Configure per strategy** for different behavior

The system is **backward compatible** (works with GOAP disabled) and **configuration-driven** (easy to tune per strategy).

**Phase 4 provides the foundation for Phase 5's advanced multi-turn planning and replanning features!**
