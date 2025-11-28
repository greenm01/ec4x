# Admiral-Strategic Integration Design
**Phase 3 Architecture for Smart AI Training**

## Overview

The Admiral module currently operates reactively - it can only reassign existing fleets. For Phase 3 smart AI training, the Admiral must drive strategic build decisions based on tactical needs assessment. This document outlines the integration architecture.

## Current State (Phase 2)

### Architecture Flow
```
Strategic/Build Module (orders.nim)
  ├─> Hardcoded thresholds (needScouts, needDefenders)
  ├─> generateBuildOrders()
  └─> Ships produced
        ↓
Tactical/Logistics (logistics_manager.nim)
  ├─> assignFleetOrders()
  └─> Fleet movements
        ↓
Admiral Module (admiral.nim)
  ├─> analyzeFleetUtilization()
  ├─> generateDefensiveOrders()
  └─> Reassign existing fleets only
```

### Problems

1. **Top-Down Build Decisions**: Strategic module uses hardcoded thresholds
   ```nim
   # orders.nim:316 - Inflexible hardcoded logic
   let needScouts = case currentAct
     of GameAct.Act1_LandGrab:
       scoutCount < 5  # Hardcoded
     of GameAct.Act2_RisingTensions:
       scoutCount < 6  # Hardcoded
   ```

2. **No Feedback Loop**: Admiral analyzes tactical needs but cannot influence production
   - Cannot request scouts for reconnaissance gaps
   - Cannot request defenders for vulnerable colonies
   - Cannot request attackers for offensive opportunities

3. **Inflexible for ML Training**: Hard thresholds prevent learning optimal fleet compositions

## Phase 3 Architecture (Proposed)

### Requirements-Driven Build System

```
Admiral Strategic Analysis (NEW)
  ├─> analyzeStrategicRequirements()
  │   ├─> Reconnaissance gaps → scoutsNeeded
  │   ├─> Undefended colonies → defendersNeeded
  │   ├─> Offensive opportunities → attackersNeeded
  │   └─> Priority scoring
  └─> StrategicRequirements
        ↓
Strategic/Build Module (REFACTORED)
  ├─> Consults AdmiralRequirements
  ├─> Applies budget constraints
  ├─> generateBuildOrders()
  └─> Ships produced
        ↓
Tactical/Logistics
  └─> Fleet assignments
        ↓
Admiral Tactical Operations
  └─> Fine-tune fleet positioning
```

### New Type Definitions

```nim
# src/ai/rba/admiral/requirements.nim (NEW MODULE)

type
  ShipRequirement* = object
    shipClass*: ShipClass
    quantity*: int
    priority*: float  # 0.0-100.0, higher = more urgent
    reason*: string   # For diagnostics/explainability

  StrategicRequirements* = object
    ## Admiral's assessment of strategic ship needs
    ## Used by build system to prioritize production

    scouts*: ShipRequirement
    defenders*: ShipRequirement
    attackers*: ShipRequirement
    etacs*: ShipRequirement

    # Derived totals
    totalShipsNeeded*: int
    highestPriority*: float

    # Context
    act*: GameAct
    threatLevel*: float  # 0.0-1.0

  ReconnaissanceGap* = object
    ## Identified reconnaissance deficiencies
    unknownSystems*: int        # Systems not yet scouted
    staleIntelSystems*: int     # Systems with outdated intel (>5 turns)
    enemyColoniesNoIntel*: int  # Known enemy colonies with no recent data
    requiredScouts*: int        # Calculated scout need

  DefensiveGap* = object
    ## Identified defensive deficiencies
    undefendedColonies*: seq[SystemId]
    underdefendedColonies*: seq[SystemId]  # <2 defenders
    requiredDefenders*: int

  OffensiveCapacity* = object
    ## Assessment of offensive readiness
    availableAttackers*: int
    vulnerableTargets*: int
    stagingAreaEstablished*: bool
    recommendedForce*: int  # Ships needed for planned operations
```

### Core API Functions

```nim
# src/ai/rba/admiral/requirements.nim

proc analyzeReconnaissanceGaps*(
  filtered: FilteredGameState,
  controller: AIController,
  analyses: seq[FleetAnalysis]
): ReconnaissanceGap =
  ## Identify reconnaissance deficiencies
  ## Returns detailed gap analysis with scout requirements
  result = ReconnaissanceGap()

  # Count unknown systems
  let totalSystems = filtered.starMap.systems.len
  let knownSystems = filtered.ownHouse.intelligence.colonyReports.len
  result.unknownSystems = totalSystems - knownSystems

  # Check for stale intel (>5 turns old)
  for systemId, report in filtered.ownHouse.intelligence.colonyReports:
    if filtered.turn - report.lastUpdated > 5:
      result.staleIntelSystems += 1

  # Calculate scout requirement
  # Rule: 1 scout per 5 unknown systems + 1 per 10 stale intel systems
  result.requiredScouts =
    (result.unknownSystems div 5) +
    (result.staleIntelSystems div 10)

proc analyzeDefensiveGaps*(
  filtered: FilteredGameState,
  controller: AIController,
  analyses: seq[FleetAnalysis]
): DefensiveGap =
  ## Identify defensive deficiencies
  ## Returns detailed gap analysis with defender requirements
  result = DefensiveGap()

  # Identify undefended colonies
  for colony in filtered.ownColonies:
    let defenders = countDefendersAtColony(colony, analyses)
    if defenders == 0:
      result.undefendedColonies.add(colony.systemId)
    elif defenders < 2:
      result.underdefendedColonies.add(colony.systemId)

  # Calculate defender requirement
  # Rule: 1 defender per undefended, 1 additional per 2 underdefended
  result.requiredDefenders =
    result.undefendedColonies.len +
    (result.underdefendedColonies.len div 2)

proc calculateStrategicRequirements*(
  filtered: FilteredGameState,
  controller: AIController,
  analyses: seq[FleetAnalysis],
  currentAct: GameAct
): StrategicRequirements =
  ## Main entry point: Calculate comprehensive strategic requirements
  ## Called by build system BEFORE budget allocation
  result = StrategicRequirements(act: currentAct)

  # Analyze gaps
  let reconGap = analyzeReconnaissanceGaps(filtered, controller, analyses)
  let defenseGap = analyzeDefensiveGaps(filtered, controller, analyses)
  let offensiveCapacity = analyzeOffensiveCapacity(filtered, controller, analyses)

  # Translate gaps to ship requirements
  result.scouts = ShipRequirement(
    shipClass: ShipClass.Scout,
    quantity: reconGap.requiredScouts,
    priority: calculateScoutPriority(reconGap, currentAct),
    reason: &"Reconnaissance gap: {reconGap.unknownSystems} unknown systems"
  )

  result.defenders = ShipRequirement(
    shipClass: ShipClass.Destroyer,  # Default defender type
    quantity: defenseGap.requiredDefenders,
    priority: calculateDefenderPriority(defenseGap, currentAct),
    reason: &"Defense gap: {defenseGap.undefendedColonies.len} undefended colonies"
  )

  result.attackers = ShipRequirement(
    shipClass: ShipClass.Cruiser,  # Default attacker type
    quantity: offensiveCapacity.recommendedForce,
    priority: calculateOffensivePriority(offensiveCapacity, currentAct),
    reason: &"Offensive opportunity: {offensiveCapacity.vulnerableTargets} vulnerable targets"
  )

  # Calculate totals
  result.totalShipsNeeded =
    result.scouts.quantity +
    result.defenders.quantity +
    result.attackers.quantity

  result.highestPriority = max([
    result.scouts.priority,
    result.defenders.priority,
    result.attackers.priority
  ])
```

### Integration Points

#### 1. Modify orders.nim to consult Admiral

```nim
# src/ai/rba/orders.nim (REFACTORED)

# OLD (Phase 2):
let needScouts = scoutCount < 5  # Hardcoded

# NEW (Phase 3):
# Run Admiral analysis BEFORE build phase
let admiralRequirements = calculateStrategicRequirements(
  filtered, controller, analyses, currentAct
)

# Use Admiral's assessment
let needScouts = admiralRequirements.scouts.quantity > 0
let scoutPriority = admiralRequirements.scouts.priority
let needDefenders = admiralRequirements.defenders.quantity > 0

# Pass requirements to build system
result.buildOrders = generateBuildOrdersWithRequirements(
  controller, filtered, admiralRequirements, availableBudget
)
```

#### 2. Refactor build_manager.nim to use requirements

```nim
# src/ai/rba/budget.nim (REFACTORED)

proc generateBuildOrdersWithRequirements*(
  controller: AIController,
  filtered: FilteredGameState,
  requirements: StrategicRequirements,
  budget: int
): seq[BuildOrder] =
  ## Generate build orders based on Admiral's strategic requirements
  ## Prioritizes by requirement priority, respects budget constraints

  var tracker = initBudgetTracker(controller.houseId, budget, requirements.act)

  # Sort requirements by priority
  type PrioritizedReq = tuple[req: ShipRequirement, category: BudgetCategory]
  var prioritized: seq[PrioritizedReq] = @[
    (requirements.scouts, Reconnaissance),
    (requirements.defenders, Defense),
    (requirements.attackers, Military)
  ]

  # Sort by priority (highest first)
  prioritized.sort(proc(a, b: PrioritizedReq): int =
    if a.req.priority > b.req.priority: -1
    elif a.req.priority < b.req.priority: 1
    else: 0
  )

  # Build ships in priority order
  for item in prioritized:
    let ships = buildShipsForRequirement(
      item.req, item.category, tracker, colonies
    )
    result.add(ships)
```

## Configuration

Add Admiral requirements to RBA config:

```toml
# config/rba.toml

[admiral.requirements]
enabled = true

# Reconnaissance thresholds
unknown_systems_per_scout = 5     # 1 scout per 5 unknown systems
stale_intel_per_scout = 10        # 1 scout per 10 stale intel reports

# Defense thresholds
min_defenders_per_colony = 1      # Baseline requirement
defenders_per_frontier = 2        # Frontier colonies get extra

# Offensive thresholds
min_attackers_for_invasion = 3    # Minimum fleet size for offensive ops
staging_area_capacity = 10        # Max ships to stage before attack

# Priority weights (0.0-1.0)
reconnaissance_weight = 0.7       # Act 1: High priority
defense_weight = 0.8              # All acts: High priority
offensive_weight = 0.3            # Act 1: Low, Act 2+: Medium-High
```

## Benefits for Phase 3

### 1. ML Training Compatibility
- **Input Features**: Gap analysis metrics (unknownSystems, undefendedColonies, vulnerableTargets)
- **Output Actions**: Ship production quantities and priorities
- **Reward Signal**: Success metrics (intel coverage, colony defense rate, victory points)

### 2. Adaptive Strategy
- Responds dynamically to threats (more defenders when under attack)
- Opportunistic offense (builds attackers when targets identified)
- Resource optimization (builds what's needed, not hardcoded amounts)

### 3. Explainability
- Each requirement includes `reason` field for debugging
- Priority scoring transparent and configurable
- Diagnostic logs show Admiral's reasoning

### 4. Gradual Rollout
- Phase 3.0: Implement requirements API with simple heuristics
- Phase 3.1: Add ML model to learn optimal priorities
- Phase 3.2: Full reinforcement learning for strategy adaptation

## Migration Path

### Phase 2 → Phase 3 Transition

1. **Phase 2 (Current)**: Hardcoded thresholds, Admiral reactive
2. **Phase 3.0 (Milestone 1)**: Implement requirements API with heuristics
3. **Phase 3.1 (Milestone 2)**: Add ML priority learning
4. **Phase 3.2 (Milestone 3)**: Full RL-driven strategy

### Backward Compatibility

Keep existing hardcoded logic as fallback:

```nim
# config/rba.toml
[admiral.requirements]
enabled = false  # Default: use legacy hardcoded thresholds

# When enabled=true, use requirements API
# When enabled=false, use old hardcoded logic (Phase 2)
```

## Testing Strategy

### Unit Tests
```nim
# tests/ai/test_admiral_requirements.nim

test "Reconnaissance gap analysis":
  # Given: 20 unknown systems, 10 stale intel
  # When: analyzeReconnaissanceGaps()
  # Then: requiredScouts = (20/5) + (10/10) = 5

test "Defensive gap analysis":
  # Given: 3 undefended, 4 underdefended colonies
  # When: analyzeDefensiveGaps()
  # Then: requiredDefenders = 3 + (4/2) = 5

test "Priority ordering":
  # Given: Defense priority=90, Scout priority=70, Attack priority=50
  # When: Sort requirements by priority
  # Then: Order = [Defense, Scout, Attack]
```

### Integration Tests
```nim
test "Admiral requirements drive builds":
  # Given: Admiral identifies 5 undefended colonies
  # When: generateBuildOrdersWithRequirements()
  # Then: Build orders include 5+ defenders

test "Budget constraints respected":
  # Given: Admiral wants 10 ships, budget allows 5
  # When: generateBuildOrdersWithRequirements()
  # Then: Build orders = 5 ships (highest priority)
```

### Balance Tests
```nim
# New Phase 3 balance test
test "PHASE3_ADAPTIVE_BUILDS":
  # Scenario 1: Heavy threat → Builds defenders
  # Scenario 2: Many unknowns → Builds scouts
  # Scenario 3: Vulnerable targets → Builds attackers
  # Validate: Build decisions match strategic needs
```

## Open Questions

1. **Priority Calculation**: How to weight competing needs?
   - Option A: Fixed weights per Act
   - Option B: ML learns optimal weights
   - **Recommendation**: Start with A, evolve to B

2. **Budget Allocation**: How to split budget among requirements?
   - Option A: Proportional to priority
   - Option B: All-or-nothing by priority order
   - **Recommendation**: B (simpler, clearer)

3. **Requirement Persistence**: Do requirements carry across turns?
   - Option A: Recalculate every turn
   - Option B: Track unmet requirements
   - **Recommendation**: B (better planning)

## Implementation Checklist

- [ ] Create `src/ai/rba/admiral/requirements.nim`
- [ ] Implement `StrategicRequirements` type
- [ ] Implement gap analysis functions
- [ ] Add configuration to `config/rba.toml`
- [ ] Refactor `orders.nim` to use requirements
- [ ] Refactor `budget.nim` to consume requirements
- [ ] Add unit tests for requirement calculations
- [ ] Add integration tests for build coordination
- [ ] Add Phase 3 balance tests
- [ ] Update RBA documentation
- [ ] Performance profiling (ensure no regression)

## References

- **Current Admiral Implementation**: `src/ai/rba/admiral.nim`
- **Current Build Logic**: `src/ai/rba/budget.nim`
- **Current Order Generation**: `src/ai/rba/orders.nim`
- **Phase 2 Results**: `docs/testing/BALANCE_TESTING_2025-11-26.md`
- **Unknown-Unknown #3 Fix**: Reduced undefended colonies from 54.7% → 27.0%

## Success Criteria

Phase 3 requirements integration is successful when:

1. **Adaptive Behavior**: AI builds scouts when unknowns high, defenders when threatened
2. **Budget Efficiency**: No wasted production, all builds address identified needs
3. **Performance**: <5% CPU overhead vs Phase 2 hardcoded logic
4. **ML Ready**: Requirements API provides clear input/output for training
5. **Explainable**: Logs show clear reasoning for every build decision

---

**Status**: Design Complete (Phase 3 roadmap)
**Next Steps**: Implement after Phase 2 validation completes
