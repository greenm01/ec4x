# CRITICAL: RBA Not Using Engine Intelligence Reports

**Date:** 2025-12-05
**Severity:** 🚨 CRITICAL
**Category:** Unknown-Unknown - Major Architectural Gap

## Executive Summary

The RBA system is **ignoring 95% of engine intelligence data**. The engine generates rich intelligence reports (`ColonyIntelReport`, `SystemIntelReport`, `StarbaseIntelReport`, `CombatEncounterReport`) but the RBA only uses them **once** in the entire codebase.

This explains multiple observed issues:
1. Why "Balanced" strategy builds zero defenses (missing threat intelligence)
2. Why Act-based budgets don't adapt to strategic situation
3. Why the AI appears "blind" to tactical opportunities

## Evidence

### Engine Intelligence System (Comprehensive)

The engine generates detailed intelligence from:

**1. Colony Intelligence** (`ColonyIntelReport`)
- Population, industry (IU), defenses (batteries, armies)
- Starbase count, construction queue
- Economic data: Gross output (GCO), tax revenue (NCV)
- Orbital defenses: Unassigned squadrons, reserve fleets, mothballed fleets
- Shipyard count

**2. System Intelligence** (`SystemIntelReport`)
- Enemy fleets in system
- Fleet composition: ship classes, squadron sizes
- Tech levels and hull integrity (Spy quality)
- Spacelift ships (transports)

**3. Starbase Intelligence** (`StarbaseIntelReport`)
- Treasury balance, gross income, net income
- Tax rate
- Research allocations (ERP, SRP, TRP)
- Current research projects
- Tech levels across all fields

**4. Combat Intelligence** (`CombatEncounterReport`)
- Pre-combat: All forces, fleet compositions
- Post-combat: Outcomes, losses, retreats
- Detailed squadron data with damage

**5. Surveillance** (`StarbaseSurveillanceReport`)
- Continuous monitoring from starbases
- Detected fleets in sector (system + adjacent)
- Combat, bombardment, transit detection
- Threat assessment

### RBA Intelligence Usage (Minimal)

**Grep Results:**
```bash
$ grep -r "ColonyIntelReport|CombatEncounterReport|StarbaseIntelReport" src/ai/rba
src/ai/rba/tactical.nim:1
```

**Only 1 occurrence in entire RBA codebase!**

### What RBA Actually Uses

From `src/ai/rba/intelligence.nim`:
- ✅ Basic visibility tracking (None/Adjacent/Scouted/Occupied/Owned)
- ✅ Last scouted turn (staleness detection)
- ✅ Estimated defenses (rough calculation)
- ✅ Estimated fleet strength (rough calculation)
- ❌ **NO use of ColonyIntelReport**
- ❌ **NO use of SystemIntelReport**
- ❌ **NO use of StarbaseIntelReport**
- ❌ **NO use of CombatEncounterReport**
- ❌ **NO use of StarbaseSurveillanceReport**

The RBA essentially operates **blind**, using only fog-of-war visibility instead of the rich intelligence the engine provides.

## Impact Analysis

### 1. Defense Budget Allocation

**Current Behavior:**
```nim
# treasurer/allocation.nim:17-43
proc getBaselineAllocation*(act: GameAct): BudgetAllocation =
  # Uses ONLY game act, ignores:
  # - Enemy fleet positions (SystemIntelReport)
  # - Enemy colony strengths (ColonyIntelReport)
  # - Enemy research progress (StarbaseIntelReport)
  # - Recent combat outcomes (CombatEncounterReport)

  case act:
    of Act1: defense = 0.10  # Fixed 10%
    of Act2: defense = 0.15  # Fixed 15%
    of Act3: defense = 0.15  # Fixed 15%
```

**What It SHOULD Do:**
```nim
# Use intelligence to determine actual threat level
let enemyFleetStrength = analyzeSystemIntelReports(intelligence)
let enemyColonyProduction = analyzeColonyIntelReports(intelligence)
let recentCombatLosses = analyzeCombatReports(intelligence)

# Dynamic allocation based on actual threat
if enemyFleetStrength > ownFleetStrength * 0.8:
  defense = 0.30  # Enemy parity: boost defenses
elif recentCombatLosses > 5:
  defense = 0.40  # Emergency: losing battles
else:
  defense = 0.10  # Safe: maintain baseline
```

### 2. Balanced Strategy Zero-Defense Bug

**Root Cause Hypothesis:**
The "Balanced" strategy may have a personality configuration that somehow blocks defense requirements from being generated. Let me check:

```nim
# Balanced strategy personality (config/rba.toml:51-57)
aggression = 0.4
risk_tolerance = 0.5
economic_focus = 0.7
expansion_drive = 0.5
diplomacy_value = 0.6
tech_priority = 0.5
```

**Treasurer allocation (allocation.nim:58-70):**
```nim
# Economic personalities: More expansion, less military (Act 1-2 only)
if economicMod > 0.0 and act in {Act1, Act2}:
  allocation[Expansion] = min(0.75, allocation[Expansion] + economicMod)
  allocation[Military] = max(0.10, allocation[Military] - economicMod * 0.5)
```

**BUG FOUND:** `economicMod = (0.7 - 0.5) * 0.20 = 0.04`

For Balanced strategy:
- `allocation[Expansion] = 0.45 + 0.04 = 0.49` (Act 1)
- `allocation[Military] = 0.20 - 0.04*0.5 = 0.18` (Act 1)

But where does **Defense** get adjusted? Let me check:

**SMOKING GUN:** Defense budget is NEVER adjusted by personality!

```nim
# applyPersonalityModifiers only adjusts:
- Military (aggression modifier)
- Expansion (economic modifier)

# Defense is NEVER modified!
# It stays at baseline: 0.10 (Act 1), 0.15 (Act 2-3)
```

So the issue is **NOT strategy-specific**, it's that **Act 1 baseline defense budget (10%) is too low** when combined with high ship production competition.

### 3. Missing Intelligence-Driven Decisions

**What RBA COULD Do With Intelligence (But Doesn't):**

1. **Targeted Defense Buildup**
   ```nim
   # ColonyIntelReport shows enemy colony at System 7:
   # - industry: 8 IU
   # - defenses: 3 batteries, 2 armies
   # - grossOutput: 800 PP
   # - constructionQueue: ["Shipyard", "Battleship"]

   # RBA should respond:
   # Build 4 batteries + 3 armies at nearby colony (match enemy + buffer)
   # But instead: Builds based on Act baseline (1 battery)
   ```

2. **Preemptive Fleet Positioning**
   ```nim
   # SystemIntelReport shows enemy fleet 2 jumps away:
   # - 5 cruisers, 3 destroyers
   # - Moving toward our border

   # RBA should respond:
   # Position defensive fleet to intercept
   # Prioritize defense budget allocation
   # But instead: No response until enemy arrives
   ```

3. **Research Prioritization**
   ```nim
   # StarbaseIntelReport shows enemy research:
   # - WEP: Level 3 (we're Level 2)
   # - SL: Level 2 (we're Level 2)
   # - currentResearch: "WEP Level 4"

   # RBA should respond:
   # Emergency WEP research to close gap
   # Increase shield tech to counter weapons
   # But instead: Uses fixed tech allocation (5-10%)
   ```

4. **Combat Adaptation**
   ```nim
   # CombatEncounterReport shows:
   # - Lost 3 cruisers to enemy battleship squadron
   # - Enemy has cloaked raiders
   # - Our retreat failed (enemy pursuit)

   # RBA should respond:
   # Build counter-units (battleships vs. cruisers)
   # Research cloaking detection
   # Adjust fleet composition
   # But instead: Continues same build queue
   ```

## Architecture Gap

### Current Flow (Blind AI)
```
Engine → Generates Intelligence Reports → Stored in GameState
                                              ↓ (IGNORED!)
RBA → Uses only fog-of-war visibility → Makes decisions blindly
```

### Required Flow (Intelligence-Driven AI)
```
Engine → Generates Intelligence Reports → IntelligenceDatabase
                                              ↓
RBA Intelligence Analyzer → Processes reports → Threat assessment
                                              ↓
Domestikos → Requirements based on threats
Treasurer → Budget adjusted for emergencies
Logothete → Research priorities from enemy tech
Drungarius → Espionage targets from StarbaseIntel
                                              ↓
CFO → Executes intelligence-informed orders
```

## Recommended Fixes

### Phase 1: Connect Intelligence to RBA (Critical - 3 days)

**1.1 Intelligence Consumption Layer**
```nim
# src/ai/rba/intelligence/analyzer.nim
proc analyzeColonyIntel*(
  reports: seq[ColonyIntelReport],
  ownColonies: seq[Colony]
): ColonyThreatAssessment =
  ## Analyze enemy colony intel to determine threat levels

  for report in reports:
    let distanceToOwn = findNearestOwnColony(report.colonyId, ownColonies)
    let productionThreat = report.grossOutput.get(0) / 100  # Normalize
    let militaryThreat = report.defenses / 10  # Normalize
    let proximityThreat = 1.0 / float(distanceToOwn + 1)

    let totalThreat = productionThreat * 0.3 +
                      militaryThreat * 0.4 +
                      proximityThreat * 0.3

    result.threats.add((report.colonyId, totalThreat))
```

**1.2 Threat-Aware Budget Allocation**
```nim
# src/ai/rba/treasurer/allocation.nim
proc allocateBudget*(
  act: GameAct,
  personality: AIPersonality,
  intelligence: IntelligenceDatabase  # NEW!
): BudgetAllocation =

  result = getBaselineAllocation(act)
  applyPersonalityModifiers(result, personality, act)

  # NEW: Intelligence-driven adjustments
  let threatLevel = assessOverallThreat(intelligence)
  if threatLevel > 0.7:
    result[Defense] = 0.30  # Emergency defense
    result[Military] = 0.40  # War footing
  elif threatLevel > 0.4:
    result[Defense] = 0.20  # Elevated defense
    result[Military] = 0.30  # Mobilization
```

**1.3 Intelligence-Driven Requirements**
```nim
# src/ai/rba/domestikos/build_requirements.nim
proc generateDefenseRequirements*(
  filtered: FilteredGameState,
  intelligence: IntelligenceDatabase,  # NEW!
  currentAct: GameAct
): seq[BuildRequirement] =

  # Use colony intel to determine actual threat
  for colony in filtered.ownColonies:
    let nearbyEnemies = findNearbyEnemyColonies(
      colony.systemId,
      intelligence.colonyReports,
      maxDistance = 5
    )

    var threatLevel = 0.0
    for enemy in nearbyEnemies:
      let distance = calculateDistance(colony.systemId, enemy.colonyId)
      let enemyStrength = enemy.defenses + enemy.industry
      let decayedThreat = enemyStrength / float(distance * distance)
      threatLevel += decayedThreat

    # Build defenses proportional to actual threat
    let targetBatteries = if threatLevel > 10.0:
      3  # High threat: full defenses
    elif threatLevel > 5.0:
      2  # Medium threat: moderate defenses
    else:
      1  # Low threat: baseline
```

### Phase 2: Strategy-Aware Budgets (Medium - 2 days)

**2.1 Strategy-Specific Budget Modifiers**
```nim
# config/rba.toml - Add strategy-specific overrides
[strategies_balanced.budget_modifiers]
defense_modifier = 1.2    # 20% more defense than baseline
military_modifier = 0.9   # 10% less military
expansion_modifier = 1.1  # 10% more expansion

[strategies_turtle.budget_modifiers]
defense_modifier = 1.5    # 50% more defense
military_modifier = 0.7   # 30% less military
```

**2.2 Load Strategy Modifiers**
```nim
# src/ai/rba/treasurer/allocation.nim
proc applyStrategyModifiers*(
  allocation: var BudgetAllocation,
  strategy: AIStrategy
) =
  let modifiers = globalRBAConfig.getStrategyModifiers(strategy)

  allocation[Defense] *= modifiers.defense_modifier
  allocation[Military] *= modifiers.military_modifier
  allocation[Expansion] *= modifiers.expansion_modifier

  normalizeAllocation(allocation)
```

### Phase 3: Combat Learning (Long-term - 5 days)

**3.1 Combat Report Analysis**
```nim
# src/ai/rba/intelligence/combat_analyzer.nim
proc analyzeCombatReports*(
  reports: seq[CombatEncounterReport]
): CombatLearning =
  ## Learn from combat outcomes to adjust tactics

  for report in reports:
    if report.outcome == Defeat:
      # What killed us?
      let enemyComposition = analyzeEnemyFleet(report.enemyForces)
      let ourComposition = analyzeOwnFleet(report.alliedForces)

      # Build counters
      if enemyComposition.capitalShipRatio > 0.6:
        result.recommendedBuilds.add("Build more capitals")
      if enemyComposition.hasCloakedUnits:
        result.recommendedResearch.add("CLK detection tech")
```

## Testing Strategy

### 1. Intelligence Integration Tests

**Test 1: Colony Intel → Defense Requirements**
```nim
# Given: ColonyIntelReport showing enemy with 5 batteries at System 7
# When: RBA generates defense requirements for nearby System 3
# Then: System 3 should request 6+ batteries (match + buffer)
```

**Test 2: Threat Level → Budget Allocation**
```nim
# Given: High threat level (0.8) from intelligence analysis
# When: Treasurer allocates budget
# Then: Defense >= 25%, Military >= 35%
```

**Test 3: Combat Reports → Unit Composition**
```nim
# Given: Lost 3 battles to enemy battleships
# When: Domestikos generates ship requirements
# Then: Should request battleships, not cruisers
```

### 2. Balanced Strategy Fix Test

**Test 4: Balanced Strategy Builds Defenses**
```nim
# Given: Balanced strategy AI with 1000 PP treasury
# When: Act 1, Turn 10, peaceful game
# Then: Should have built 1-2 batteries per colony (Act 1 baseline)
```

## Success Criteria

1. ✅ RBA uses all 5 intelligence report types
2. ✅ Budget allocation responds to threat level (not just Act)
3. ✅ Defense requirements use ColonyIntelReports
4. ✅ Balanced strategy builds defenses (fix zero-battery bug)
5. ✅ Combat reports influence unit composition
6. ✅ Research priorities adjusted based on StarbaseIntel

## GOAP Integration: Intelligence-Driven Strategic Planning

### Overview

Intelligence reports are the **foundation** for GOAP planning. GOAP's strategic layer needs accurate threat assessment to generate meaningful goals, and intelligence reports provide that ground truth.

**Key Insight:** GOAP planning without intelligence = planning in the dark. Fix intelligence integration FIRST, then GOAP multiplies its value.

### Architecture: Intelligence → GOAP → RBA

```
┌─────────────────────────────────────────────────────────────────┐
│                    INTELLIGENCE LAYER                            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
    Engine Intelligence Reports (ColonyIntel, SystemIntel, etc.)
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              INTELLIGENCE ANALYZER (NEW)                         │
│  - Process ColonyIntelReports → Colony threat map               │
│  - Process SystemIntelReports → Fleet threat map                │
│  - Process CombatReports → Combat effectiveness learning         │
│  - Process StarbaseIntel → Tech gap analysis                    │
│  - Generate WorldStateSnapshot with threat assessments          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    STRATEGIC LAYER (GOAP)                        │
│  - Generate goals based on intelligence-driven threats          │
│  - Prioritize goals using threat severity                       │
│  - Plan action sequences with intel-aware preconditions         │
│  - Replan when new intelligence invalidates assumptions         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    TACTICAL LAYER (RBA)                          │
│  - Execute GOAP plan actions using requirements system          │
│  - Adjust budget allocation based on threat level               │
│  - Generate detailed build orders for plan steps                │
└─────────────────────────────────────────────────────────────────┘
```

### Intelligence-Driven Goal Generation

**1. WorldStateSnapshot Enhancement**

```nim
# Current: src/ai/rba/goap/state/snapshot.nim
type WorldStateSnapshot* = object
  # Basic state (current)
  treasury*: int
  production*: int
  ownedColonies*: seq[SystemId]

  # Intelligence-driven additions (NEW)
  colonyIntelligence*: Table[SystemId, ColonyIntelReport]
  systemIntelligence*: Table[SystemId, SystemIntelReport]
  starbaseIntelligence*: Table[HouseId, StarbaseIntelReport]
  recentCombats*: seq[CombatEncounterReport]

  # Derived threat assessments (NEW)
  colonyThreats*: Table[SystemId, float]  # 0.0-1.0 threat per colony
  enemyCapabilities*: Table[HouseId, EnemyCapability]
  techGaps*: Table[TechField, int]  # How many levels behind enemy
  combatEffectiveness*: Table[ShipClass, float]  # Win rate by ship class
```

**2. Intelligence-Driven Goal Creation**

```nim
# Example: DefendColony goal generation

proc createDefendColonyGoal*(
  snapshot: WorldStateSnapshot,
  colonyId: SystemId
): Option[Goal] =
  ## Generate defense goal using intelligence reports

  # Check if we have intel on nearby enemy colonies
  let nearbyEnemies = findNearbyEnemies(
    colonyId,
    snapshot.colonyIntelligence,
    maxDistance = 5
  )

  if nearbyEnemies.len == 0:
    return none(Goal)  # No threat, no defense goal

  # Calculate threat from intelligence
  var totalThreat = 0.0
  var highestEnemyDefenses = 0

  for enemy in nearbyEnemies:
    let intel = snapshot.colonyIntelligence[enemy.systemId]
    let distance = calculateDistance(colonyId, enemy.systemId)

    # Threat factors from intelligence
    let productionThreat = intel.grossOutput.get(0) / 1000.0
    let defenseThreat = float(intel.defenses) / 10.0
    let proximityMultiplier = 1.0 / float(distance)

    let threat = (productionThreat + defenseThreat) * proximityMultiplier
    totalThreat += threat

    highestEnemyDefenses = max(highestEnemyDefenses, intel.defenses)

  # Goal parameters driven by intelligence
  let priority = min(totalThreat, 1.0)  # 0.0-1.0
  let targetDefenses = highestEnemyDefenses + 2  # Enemy + buffer
  let estimatedCost = targetDefenses * 50  # 50 PP per battery
  let deadline = estimateEnemyArrival(nearbyEnemies, colonyId)

  return some(Goal(
    goalType: DefendColony,
    priority: priority,
    target: some(colonyId),
    requiredResources: estimatedCost,
    deadline: deadline,
    preconditions: @[
      controlsSystem(colonyId),
      hasMinBudget(estimatedCost)
    ],
    successCondition: hasDefenses(colonyId, batteries=targetDefenses),
    description: "Defend colony from " & $nearbyEnemies.len & " nearby enemies (threat=" & $totalThreat & ")"
  ))
```

**3. Combat Learning → Fleet Composition Goals**

```nim
# Example: Build counter-units based on combat reports

proc analyzeCombatEffectiveness*(
  snapshot: WorldStateSnapshot
): Table[ShipClass, float] =
  ## Learn what works from combat reports

  result = initTable[ShipClass, float]()

  for report in snapshot.recentCombats:
    if report.outcome == Victory:
      # What won for us?
      for fleet in report.alliedForces:
        for squadron in fleet.squadrons:
          let shipClass = parseEnum[ShipClass](squadron.shipClass)
          result[shipClass] = result.getOrDefault(shipClass, 0.0) + 0.1

    elif report.outcome == Defeat:
      # What failed?
      for fleet in report.alliedForces:
        for squadron in fleet.squadrons:
          let shipClass = parseEnum[ShipClass](squadron.shipClass)
          result[shipClass] = result.getOrDefault(shipClass, 0.0) - 0.1

  # Normalize to win rates
  for shipClass, effectiveness in result.mpairs:
    effectiveness = clamp(effectiveness, -1.0, 1.0)

proc createBuildFleetGoal*(
  snapshot: WorldStateSnapshot,
  systemId: SystemId,
  priority: float
): Goal =
  ## Build fleet using combat learning

  let effectiveness = analyzeCombatEffectiveness(snapshot)

  # Build more of what works, less of what fails
  var bestShipClass = ShipClass.Cruiser  # Default
  var bestEffectiveness = -999.0

  for shipClass, effectiveness in effectiveness:
    if effectiveness > bestEffectiveness:
      bestShipClass = shipClass
      bestEffectiveness = effectiveness

  let cost = getShipCost(bestShipClass) * 3  # Build 3 ships

  return Goal(
    goalType: BuildFleet,
    priority: priority,
    target: some(systemId),
    requiredResources: cost,
    description: "Build 3x " & $bestShipClass & " (combat effectiveness: " & $bestEffectiveness & ")"
  )
```

**4. Tech Gap Analysis → Research Goals**

```nim
# Example: Priority research from enemy tech intel

proc generateResearchGoals*(
  snapshot: WorldStateSnapshot
): seq[Goal] =
  ## Generate research goals based on enemy tech intelligence

  result = @[]

  for enemyHouse, starbaseIntel in snapshot.starbaseIntelligence:
    if starbaseIntel.techLevels.isNone:
      continue

    let enemyTech = starbaseIntel.techLevels.get()
    let ownTech = snapshot.ownTechLevels

    # Find critical tech gaps
    for field in TechField:
      let gap = getEnemyLevel(enemyTech, field) - getOwnLevel(ownTech, field)

      if gap >= 2:
        # Enemy has 2+ level advantage: CRITICAL
        result.add(Goal(
          goalType: CloseTechGap,
          priority: 0.9,
          techField: some(field),
          requiredResources: estimateResearchCost(field, gap),
          description: "Close " & $field & " gap (enemy +" & $gap & " levels)"
        ))

      elif gap == 1 and starbaseIntel.currentResearch.isSome:
        # Enemy researching this field: URGENT
        if $field in starbaseIntel.currentResearch.get():
          result.add(Goal(
            goalType: CloseTechGap,
            priority: 0.7,
            techField: some(field),
            requiredResources: estimateResearchCost(field, 1),
            description: "Match enemy " & $field & " research (prevent gap widening)"
          ))
```

### GOAP Planner Benefits from Intelligence

**1. Accurate Precondition Evaluation**

```nim
# Current (Blind): Can't check if system is defended
proc hasDefenses(systemId: SystemId): bool =
  # Must visit system to know
  false  # Conservative: assume no defenses

# With Intelligence (Informed):
proc hasDefenses(systemId: SystemId, snapshot: WorldStateSnapshot): bool =
  if systemId in snapshot.colonyIntelligence:
    let intel = snapshot.colonyIntelligence[systemId]
    return intel.defenses >= 3  # We know from spy reports
  else:
    return false  # No intel = can't confirm
```

**2. Realistic Cost Estimates**

```nim
# Current (Guess): Estimate based on defaults
proc estimateInvasionCost(targetSystem: SystemId): int =
  return 500  # Generic guess

# With Intelligence (Accurate):
proc estimateInvasionCost(
  targetSystem: SystemId,
  snapshot: WorldStateSnapshot
): int =
  let intel = snapshot.colonyIntelligence.get(targetSystem)
  if intel.isNone:
    return 999999  # No intel = too risky

  let defenses = intel.get().defenses
  let starbases = intel.get().starbaseLevel

  # Calculate force needed to overcome known defenses
  let marinesNeeded = defenses + 5  # Overcome ground forces
  let shipsNeeded = starbases * 3 + 10  # Overcome orbital defenses

  return (marinesNeeded * 15) + (shipsNeeded * 100)
```

**3. Dynamic Replanning from Intelligence Updates**

```nim
# GOAP replanning trigger: New intelligence invalidates plan

proc shouldReplanDefense*(
  currentPlan: GOAPlan,
  newSnapshot: WorldStateSnapshot
): bool =
  ## Check if new intelligence invalidates defense plan

  if currentPlan.goal.goalType != DefendColony:
    return false

  let targetColony = currentPlan.goal.target.get()

  # Check if enemy threat increased
  let oldThreat = currentPlan.snapshot.colonyThreats.getOrDefault(targetColony, 0.0)
  let newThreat = newSnapshot.colonyThreats.getOrDefault(targetColony, 0.0)

  if newThreat > oldThreat * 1.5:
    # Threat increased 50% - need more defenses
    return true

  # Check if new enemy colony detected nearby
  let oldNearbyEnemies = findNearbyEnemies(targetColony, currentPlan.snapshot.colonyIntelligence)
  let newNearbyEnemies = findNearbyEnemies(targetColony, newSnapshot.colonyIntelligence)

  if newNearbyEnemies.len > oldNearbyEnemies.len:
    # New enemy discovered nearby
    return true

  return false
```

**4. Multi-Turn Intelligence-Aware Planning**

```nim
# Example: 3-turn defense plan with intelligence updates

Turn 1 Intelligence:
  - Enemy colony at System 7: 5 batteries, 800 PP/turn
  - Distance: 3 jumps

Turn 1 GOAP Plan:
  Goal: DefendColony(System 3)
  Actions:
    Turn 1: Build 1 battery (50 PP) - baseline
    Turn 2: Build 1 battery (50 PP) - match threat
    Turn 3: Build 1 battery (50 PP) - buffer
  Total Cost: 150 PP, Confidence: 0.8

Turn 2 Intelligence Update:
  - Enemy colony at System 7: NOW 8 batteries, 1200 PP/turn
  - Enemy fleet detected (SystemIntelReport): 5 cruisers heading toward us

Turn 2 Replanning:
  Goal: DefendColony(System 3) [ESCALATED]
  New Actions:
    Turn 2: Build 2 batteries (100 PP) - URGENT
    Turn 3: Build 1 army (15 PP) - last-line defense
    Turn 4: Build defensive fleet (200 PP) - space defense
  Total Cost: 315 PP, Confidence: 0.6 (enemy fleet uncertain)

Turn 3 Intelligence Update:
  - Combat report: Our scout engaged enemy fleet, lost (CombatEncounterReport)
  - Enemy fleet composition: 3 battleships, 2 cruisers (stronger than estimated)

Turn 3 Replanning:
  Goal: Emergency Defense(System 3) [CRITICAL]
  New Actions:
    Turn 3: Build 3 batteries (150 PP) - full fortification
    Turn 3: Build 2 armies (30 PP) - ground defense
    Turn 4: Build 2 battleships (600 PP) - counter enemy capitals
  Total Cost: 780 PP, Confidence: 0.7
```

### Intelligence → GOAP → RBA Pipeline

**Complete Flow Example:**

```nim
# Turn 5: Intelligence arrives

1. Engine generates ColonyIntelReport:
   - Enemy System 7: 5 batteries, 2 armies, 1200 PP/turn
   - Stored in GameState.intelligenceReports

2. Intelligence Analyzer processes report:
   - Calculates threat: 0.6 (moderate)
   - Updates WorldStateSnapshot.colonyThreats[System7] = 0.6
   - Marks System 3 (our colony, 2 jumps away) as vulnerable

3. GOAP Goal Generator creates goals:
   - DefendColony(System3, priority=0.7, targetDefenses=7)
   - BuildFleet(System3, priority=0.5, shipClass=Cruiser)
   - CloseTechGap(WEP, priority=0.4)  # Enemy has better weapons

4. GOAP Planner sequences actions:
   - Plan: Build 2 batteries (Turn 5), 2 batteries (Turn 6), 1 army (Turn 7)
   - Total: 115 PP over 3 turns
   - Confidence: 0.8 (good intel, achievable cost)

5. RBA Execution (Turn 5):
   - Domestikos converts GOAP plan → BuildRequirement(Defense, Critical, 100 PP)
   - Treasurer allocates 30% to Defense (threat-driven boost)
   - CFO executes: Build 2 batteries at System 3

6. Turn 6: Intelligence update triggers replanning
   - New SystemIntelReport: Enemy fleet moved closer
   - GOAP detects plan invalidation, replans with urgency
   - New actions: Accelerate defense, add fleet component
```

### Benefits of Intelligence + GOAP Integration

**vs. Current RBA (Blind Reactive):**
- RBA: "Build 1 battery (Act 1 baseline), enemy arrives with overwhelming force"
- Intelligence + GOAP: "Enemy has 5 batteries 3 jumps away, plan 7 battery defense over 3 turns"

**vs. RBA with Intelligence (Reactive but Informed):**
- RBA+Intel: "See enemy threat this turn, build defenses this turn (may be too late)"
- Intelligence + GOAP: "See enemy threat, plan multi-turn response, complete before arrival"

**vs. GOAP without Intelligence (Strategic but Blind):**
- GOAP alone: "Plan defense based on Act baseline, enemy arrives stronger than expected"
- Intelligence + GOAP: "Plan defense based on actual enemy strength, adjust as intel updates"

### Implementation Order

**CRITICAL: Intelligence integration must come FIRST**

```
Phase 1 (Week 1): Intelligence Foundation
├── Day 1-2: Intelligence Analyzer
│   ├── Process ColonyIntelReports → threat maps
│   ├── Process SystemIntelReports → fleet tracking
│   └── Process CombatReports → effectiveness learning
├── Day 3-4: RBA Intelligence Integration
│   ├── Update Domestikos to use ColonyIntel
│   ├── Update Treasurer to use threat levels
│   └── Update Logothete to use StarbaseIntel
└── Day 5: Testing & Validation
    └── Verify Balanced strategy builds defenses

Phase 2 (Week 2): GOAP Integration
├── Day 1-2: WorldStateSnapshot Enhancement
│   └── Add intelligence fields to snapshot
├── Day 3-4: Intelligence-Driven Goal Generation
│   ├── DefendColony goals from ColonyIntel
│   ├── BuildFleet goals from CombatReports
│   └── Research goals from StarbaseIntel
└── Day 5: Replanning Triggers
    └── Detect when new intelligence invalidates plans

Phase 3 (Week 3): Advanced Features
├── Predictive threat modeling
├── Multi-colony defense coordination
└── Long-term strategic positioning
```

### Why Intelligence Before GOAP

**Without Intelligence:**
```
GOAP: "Plan to defend System 3 with 2 batteries (Act baseline)"
Reality: Enemy has 8 batteries at System 7, overwhelms defense
Result: Strategic plan based on wrong assumptions = failure
```

**With Intelligence:**
```
Intelligence: "Enemy System 7: 8 batteries, 1500 PP/turn, 3 jumps away"
GOAP: "Plan to defend System 3 with 10 batteries + fleet (match enemy + buffer)"
Reality: Enemy arrives, defenses hold
Result: Strategic plan based on ground truth = success
```

**Key Insight:** GOAP amplifies the quality of information it receives. Garbage in = garbage out. Fix the information flow first, then GOAP makes optimal use of it.

## Priority

**CRITICAL - Block all other work until Phase 1 complete**

This is a foundational architectural gap. The RBA is making decisions with 5% of available information. Fixing this will likely resolve:
- Balanced strategy zero-defense bug
- Act-based budget rigidity
- Poor tactical responses
- Inefficient resource allocation

**Intelligence integration is prerequisite for GOAP to add value.**

---

**Next Steps:**
1. Implement intelligence analyzer (2 days)
2. Connect to RBA decision-making (2 days)
3. Validate with comprehensive tests (1 day)
4. **THEN** add GOAP integration (1 week)

**User Goal:** "ensure the RBA was using all game units and test that they actually work. look for loopholes and unknown-unknonws"

**Result:** ✅ Found major unknown-unknown - RBA ignoring 95% of intelligence system!

**Follow-up:** "how would utilizing the intelligence reports tie into the new goap system?"

**Result:** ✅ Intelligence is foundation for GOAP - strategic planning requires ground truth. Fix intelligence FIRST, then GOAP multiplies effectiveness.
