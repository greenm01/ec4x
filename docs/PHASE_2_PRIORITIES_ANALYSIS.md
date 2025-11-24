# Phase 2 RBA Improvements - Priority Analysis

**Date:** 2025-11-24
**Based on:** Grok's EC4X Bootstrap Gap Analysis

## Current Status

**✅ Completed:**
- Core fog-of-war system
- FoW integration with AI (bridge pattern)
- 2,800+ line rule-based AI with 7 strategies
- 100k game stress test (engine production-ready)

**📊 Test Coverage:** 101 integration tests passing

## Gap Analysis Findings vs Current TODO

### High-Priority Gaps (Per Grok Analysis)

| Gap | Current TODO Status | Priority Justification |
|-----|---------------------|------------------------|
| **Espionage mission selection** | ❌ Not in Phase 2 plan | **CRITICAL** - Zero SpyPlanet/HackStarbase ever used |
| **Role-based ROE (patrol vs guard)** | ✅ Phase 2f (Defense layering) | **HIGH** - All fleets have same aggression |
| **Tech synergy chains (FD → ACO)** | ✅ Phase 2e (Fighter Doctrine & ACO) | **HIGH** - FD researched but ACO delayed |
| **Late-game fleet mothballing** | ✅ Phase 2f (Defense layering) | **HIGH** - Keeps full maintenance on 50+ ships |
| **Fallback system designation** | ❌ Not in Phase 2 plan | **HIGH** - Fleets fight to death with no retreat |
| **Fighter capacity violations** | ✅ Phase 2b (Fighter/carrier ownership) | **CRITICAL** - Any unresolved after grace period |
| **Idle carriers (0 fighters)** | ✅ Phase 2b (Fighter/carrier ownership) | **HIGH** - > 20% of carrier fleet idle |
| **ELI mesh < 3 scouts** | ✅ Phase 2d (ELI/CLK arms race) | **HIGH** - > 50% of major attacks fail |
| **Raider ambush success** | ✅ Phase 2d (ELI/CLK arms race) | **HIGH** - < 35% when CLK > ELI |
| **Scout operational modes** | ✅ Phase 2c (Scout modes) | **MEDIUM** - For ELI mesh coordination |

### Missing from Current Phase 2 Plan

**❌ CRITICAL GAPS NOT ADDRESSED:**

1. **Espionage Mission Targeting** (Not in plan!)
   - Problem: AI never uses SpyPlanet/HackStarbase
   - Symptom: 0 espionage missions in entire games
   - Priority: **HIGH** (should be Phase 2g)

2. **Fallback System Designation** (Not in plan!)
   - Problem: Fleets have no retreat target designated
   - Symptom: Fight to death instead of seeking home
   - Priority: **HIGH** (should be Phase 2h)
   - Note: Auto-seek-home exists, but needs fallback designation logic

3. **Multi-player Threat Assessment** (Not in plan!)
   - Problem: Attacks strongest instead of weakest
   - Symptom: Sub-optimal targeting decisions
   - Priority: **MEDIUM** (should be Phase 2i)

4. **Blockade & Economic Warfare** (Not in plan!)
   - Problem: Ignores enemy supply lanes
   - Symptom: Missing strategic options
   - Priority: **MEDIUM** (should be Phase 2j)

5. **Prestige Victory Path** (Not in plan!)
   - Problem: Never pursues prestige-focused strategy
   - Symptom: Missing victory condition
   - Priority: **MEDIUM** (should be Phase 2k)

## Revised Phase 2 Priority Order

### Critical Path (Must Do Before Bootstrap)

**Phase 2a: ✅ FoW Integration** (DONE)
- Blocks all other work
- Bridge pattern active

**Phase 2b: Fighter/Carrier Ownership System** ⏳ **NEXT UP**
- **Red-flag metric:** Any unresolved capacity violations
- **Impact:** Prevents systematic fighter disband failures
- **Diagnostic:** Capacity violation tracking
- **Effort:** ~400 lines, 15 tests

**Phase 2g: Espionage Mission Targeting** ⏳ **HIGH PRIORITY** (NEW)
- **Red-flag metric:** 0 SpyPlanet/HackStarbase missions
- **Impact:** Enables intelligence gathering under FoW
- **Diagnostic:** Espionage mission count per game
- **Effort:** ~250 lines, 8 tests
- **Implementation:**
  - `identifySpyTargets()` - High-value enemy colonies with no recent intel
  - `identifyHackTargets()` - Enemy production/research centers
  - `prioritizeEspionageActions()` - Choose best mission type
  - Integration with `generateEspionageAction()`

**Phase 2h: Fallback System Designation** ⏳ **HIGH PRIORITY** (NEW)
- **Red-flag metric:** Fleets fight to death
- **Impact:** Proper retreat behavior
- **Diagnostic:** Fleet destruction without retreat attempts
- **Effort:** ~200 lines, 6 tests
- **Implementation:**
  - `designateFallbackSystem()` - Assign nearest safe colony
  - `updateFallbackOnLoss()` - Reassign if fallback captured
  - Integration with auto-seek-home system

**Phase 2c: Scout Operational Modes** ⏳ **HIGH PRIORITY**
- **Red-flag metric:** ELI mesh < 3 scouts on invasions
- **Impact:** Proper scouting for invasions
- **Diagnostic:** Scout squadron sizes in fleets
- **Effort:** ~300 lines, 10 tests

**Phase 2d: ELI/CLK Arms Race Dynamics** ⏳ **HIGH PRIORITY**
- **Red-flag metric:** Raider ambush success < 35%
- **Impact:** Proper stealth/detection mechanics
- **Diagnostic:** Raider ambush success rate
- **Effort:** ~250 lines, 8 tests

### Important (High Quality Bootstrap)

**Phase 2e: Fighter Doctrine & ACO Research** ⏳ **MEDIUM PRIORITY**
- **Red-flag metric:** FD researched but ACO delayed
- **Impact:** Tech synergy chains
- **Diagnostic:** FD/ACO research correlation
- **Effort:** ~200 lines, 7 tests

**Phase 2f: Defense Layering Strategy** ⏳ **MEDIUM PRIORITY**
- **Red-flag metric:** Mothballed fleets never used
- **Impact:** Late-game efficiency
- **Diagnostic:** Mothball usage in winning games
- **Effort:** ~150 lines, 5 tests

### Optional (Nice to Have)

**Phase 2i: Multi-player Threat Assessment** ⏳ **MEDIUM PRIORITY** (NEW)
- **Red-flag metric:** Attacks strongest instead of weakest
- **Impact:** Better strategic targeting
- **Diagnostic:** Target selection patterns
- **Effort:** ~200 lines, 6 tests

**Phase 2j: Blockade & Economic Warfare** ⏳ **LOW PRIORITY** (NEW)
- **Red-flag metric:** Ignores enemy supply lanes
- **Impact:** Additional strategic options
- **Diagnostic:** Blockade order usage
- **Effort:** ~150 lines, 5 tests

**Phase 2k: Prestige Victory Path** ⏳ **LOW PRIORITY** (NEW)
- **Red-flag metric:** Never pursues prestige
- **Impact:** Victory condition diversity
- **Diagnostic:** Prestige-focused strategies
- **Effort:** ~150 lines, 5 tests

## Diagnostic Infrastructure (Milestone 1)

**Priority: IMMEDIATE** (Before starting Phase 2b)

### Add Tracking to run_simulation.nim

**Key Metrics Per House, Per Turn:**

```nim
type
  DiagnosticMetrics = object
    turn: int
    houseId: HouseId

    # Economy
    treasuryBalance: int
    productionPerTurn: int
    puGrowth: int
    zeroSpendTurns: int

    # Military
    spaceCombatFailures: int
    spaceCombatTotal: int
    orbitalFailures: int
    orbitalTotal: int
    raiderAmbushSuccess: int
    raiderAmbushAttempts: int

    # Logistics
    capacityViolationsActive: int
    fightersDisbanded: int
    totalFighters: int
    idleCarriers: int
    totalCarriers: int

    # Intel / Tech
    invasionFleetsWithoutELIMesh: int
    totalInvasions: int
    clkResearchedNoRaiders: bool
    spyPlanetMissions: int
    hackStarbaseMissions: int

    # Defense
    coloniesWithoutDefense: int
    totalColonies: int
    mothballedFleetsUsed: int
    mothballedFleetsTotal: int

    # Orders
    invalidOrders: int
    totalOrders: int

proc collectDiagnostics(state: GameState, houseId: HouseId, turn: int): DiagnosticMetrics

proc writeDiagnosticsLog(metrics: seq[DiagnosticMetrics], filename: string)
```

**Output Format:** CSV for easy analysis
```csv
turn,house,treasury,production,pu_growth,capacity_violations,spy_missions,invalid_orders
1,house-alpha,1000,131,0,0,0,0
2,house-alpha,1131,131,131,0,0,0
...
```

### Analysis Dashboard (Python)

**Script:** `analysis/analyze_diagnostics.py`

```python
import pandas as pd
import matplotlib.pyplot as plt

# Load all diagnostic CSVs
df = pd.read_csv('diagnostics/*.csv')

# Calculate red-flag metrics
capacity_fail_rate = df[df.capacity_violations > 0].shape[0] / df.shape[0]
spy_mission_rate = df.spy_missions.sum() / df.shape[0]
raider_success = df.raider_success.sum() / df.raider_attempts.sum()

# Generate report
print(f"Capacity violation rate: {capacity_fail_rate:.1%}")
print(f"Games with spy missions: {spy_mission_rate:.1%}")
print(f"Raider ambush success: {raider_success:.1%}")
```

## Revised Phase 2 Deliverable

**Total estimated effort:**
- Critical path (2b, 2g, 2h, 2c, 2d): ~1,400 lines, 47 tests
- Important (2e, 2f): ~350 lines, 12 tests
- Optional (2i, 2j, 2k): ~500 lines, 16 tests
- Diagnostic infrastructure: ~300 lines, 5 tests
- **Grand Total:** ~2,550 lines added/modified, 80 tests

## Implementation Order

1. **Diagnostic Infrastructure** (Immediate)
   - Add metric collection to run_simulation.nim
   - Run 2,000 diagnostic games
   - Generate gap analysis report

2. **Critical Path** (In Order)
   - Phase 2b: Fighter/carrier ownership
   - Phase 2g: Espionage mission targeting (NEW)
   - Phase 2h: Fallback system designation (NEW)
   - Phase 2c: Scout operational modes
   - Phase 2d: ELI/CLK arms race

3. **First Validation** (After Critical Path)
   - Re-run 2,000 games
   - Verify top 3 red-flags resolved
   - Check stress-test scenarios

4. **Important Features** (If Time Allows)
   - Phase 2e: Fighter Doctrine & ACO
   - Phase 2f: Defense layering

5. **Final Validation** (Before Bootstrap)
   - Run 500 full-length games
   - Target < 2% unresolved capacity violations
   - Target > 60% Raider success when CLK > ELI
   - Target > 70% mothballing in winning games
   - Target > 80% games with espionage missions

6. **Bootstrap Generation** (Phase 3)
   - Run 10,000+ games with enhanced RBA
   - Export 1.5M+ training examples

## Key Insight from Grok

> "Your current 2,800-line rule-based AI is already far above average. These diagnostics will turn it from 'very good' to 'excellent teacher' for the neural network. Every flaw you fix now compounds through every self-play iteration later."

**Translation:** Don't try to make perfect AI. Make AI that doesn't do systematically stupid things.

---

**Status:** Analysis complete ✅ | Diagnostic infrastructure next ⏳ | Ready to implement

**Priority:** Start with diagnostic infrastructure before any Phase 2 tasks!
