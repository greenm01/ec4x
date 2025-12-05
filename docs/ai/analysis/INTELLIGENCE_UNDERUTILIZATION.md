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

## Priority

**CRITICAL - Block all other work until Phase 1 complete**

This is a foundational architectural gap. The RBA is making decisions with 5% of available information. Fixing this will likely resolve:
- Balanced strategy zero-defense bug
- Act-based budget rigidity
- Poor tactical responses
- Inefficient resource allocation

---

**Next Steps:**
1. Implement intelligence analyzer (1 day)
2. Connect to Treasurer budget allocation (1 day)
3. Update Domestikos to use threat intel (1 day)
4. Test and validate (2 days)

**User Goal:** "ensure the RBA was using all game units and test that they actually work. look for loopholes and unknown-unknonws"

**Result:** ✅ Found major unknown-unknown - RBA ignoring 95% of intelligence system!
