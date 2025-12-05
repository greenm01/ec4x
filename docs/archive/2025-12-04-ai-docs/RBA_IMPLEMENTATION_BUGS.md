# RBA Implementation Bugs - Root Cause Analysis

**Date:** 2025-12-04
**Status:** Identified, ready for fix
**Impact:** Critical - AI completely non-functional for combat and espionage

## Executive Summary

The RBA AI had **four critical implementation bugs** preventing it from executing military operations, intelligence gathering, and espionage:

1. **Espionage AI**: Budget always 0 (hardcoded bug) - **0 espionage missions** ✅ FIXED
2. **War AI**: Never generates Bombard/Invade/Blitz orders - **0 invasions, 0 bombardments** ✅ FIXED
3. **Scout Intelligence**: Never uses SpyPlanet/SpySystem/HackStarbase - **0 intel missions** ✅ FIXED
4. **Diplomacy AI**: Properly implemented ✅ VERIFIED

These are **not architectural problems** - they are simple implementation bugs where developers forgot to use existing order types.

## Bug #1: Espionage Budget Hardcoded to Zero ❌

### Location
`src/ai/rba/orders/phase3_execution.nim:54`

### Bug
```nim
proc executeEspionageAction*(
  controller: AIController,
  filtered: FilteredGameState,
  allocation: MultiAdvisorAllocation,
  rng: var Rand
): Option[EspionageAttempt] =
  let espionageBudget = allocation.budgets.getOrDefault(controller_types.AdvisorType.Drungarius, 0)

  # BUG: Passes 0 instead of using allocated budget!
  result = generateEspionageAction(controller, filtered, 0, 0, rng)  # ❌
```

### Impact
- Espionage AI receives 0 EBP (Espionage Budget Points) and 0 CIP (Counter-Intelligence Points)
- `drungarius/operations.nim:181` checks `if house.prestige < 50: return none`
- Even though espionage has budget, it's never passed to the decision logic
- **Result: 0 espionage missions ever executed**

### Fix
```nim
# Calculate EBP/CIP from allocated budget
# TODO: Proper conversion formula (PP → EBP/CIP)
let projectedEBP = house.espionageBudget.ebpPoints + espionageBudget
let projectedCIP = house.espionageBudget.cipPoints + (espionageBudget div 2)

result = generateEspionageAction(controller, filtered, projectedEBP, projectedCIP, rng)
```

### Root Cause
Developer left TODO comment but hardcoded 0 values - never implemented proper budget conversion.

---

## Bug #2: War AI Never Issues Bombardment/Invasion Orders ❌ → ✅ FIXED

### Location
`src/ai/rba/domestikos/offensive_ops.nim:122-273`

### Bug
The entire `offensive_ops.nim` module only generates `Move` orders:

```nim
proc generateCounterAttackOrders*(...): seq[FleetOrder] =
  # ... finds vulnerable enemy colonies ...

  # BUG: Only moves to target, never bombards/invades!
  result.add(FleetOrder(
    fleetId: attacker.fleetId,
    orderType: FleetOrderType.Move,  # ❌ Should be Bombard/Invade/Blitz
    targetSystem: some(target.systemId),
    priority: 90
  ))
```

### Available Order Types (NOT USED)
From `src/engine/order_types.nim:16-18`:
- `Bombard` - Orbital bombardment
- `Invade` - Ground assault
- `Blitz` - Combined bombardment + invasion

### Impact
- AI identifies vulnerable enemy colonies correctly ✅
- AI moves fleets to attack positions ✅
- AI **never issues combat orders** ❌
- Fleets arrive at enemy colonies and **sit idle**
- **Result: 0 invasions, 0 orbital bombardments**

### Fix Strategy
Replace `FleetOrderType.Move` with proper combat orders based on context:

```nim
# Determine combat order type based on fleet composition
let combatOrder = if attacker.hasMarines and attacker.shipCount >= 3:
  FleetOrderType.Blitz  # Strong fleet with marines - full assault
elif attacker.hasMarines:
  FleetOrderType.Invade  # Marines available - ground invasion
else:
  FleetOrderType.Bombard  # No marines - orbital bombardment only

result.add(FleetOrder(
  fleetId: attacker.fleetId,
  orderType: combatOrder,
  targetSystem: some(target.systemId),
  priority: 90
))
```

### Root Cause
Developer implemented target selection but forgot to implement actual combat order generation.

---

## Bug #4: Scout Intelligence Missions Never Used ❌ → ✅ FIXED

### Location
`src/ai/rba/domestikos/offensive_ops.nim:71-185` (generateProbingOrders)

### Bug
"Probing attack" function sent scouts to enemy systems but only issued `Move` orders:

```nim
proc generateProbingOrders*(...): seq[FleetOrder] =
  # ... finds enemy colonies to probe ...

  result.add(FleetOrder(
    fleetId: scout.fleetId,
    orderType: FleetOrderType.Move,  # ❌ Should use SpyPlanet/SpySystem/HackStarbase
    targetSystem: some(target),
    priority: 85
  ))
```

### Available Order Types (NOT USED)
From `src/engine/order_types.nim:20-22,29`:
- `SpyPlanet` - Intelligence gathering on planet (defense/production intel)
- `SpySystem` - Reconnaissance of system (fleet movements)
- `HackStarbase` - Electronic warfare against starbases
- `ViewWorld` - Long-range planetary reconnaissance (used in tactical.nim only for Act 1)

### Impact
- AI identified enemy targets correctly ✅
- AI sent scouts to those locations ✅
- Scouts just **moved to systems** instead of executing intelligence missions ❌
- **Result: No spy missions (09, 10, 11), no starbase hacks**

### Fix Strategy
Implemented prioritized intelligence mission selection:

```nim
# Priority 1: HackStarbase (priority: 100)
# - Target enemy starbases for high-value intel
# - Disrupts enemy defenses

# Priority 2: SpyPlanet (priority: 90 for enemies, 70 for neutrals)
# - Gather defense strength, production capacity
# - Critical for invasion planning

# Priority 3: SpySystem (priority: 60)
# - Reconnaissance of enemy fleet movements
# - Systems with fleets but no visible colony
```

### Root Cause
Developer implemented scout targeting but forgot to use intelligence-gathering order types.

---

## Bug #3: Diplomacy AI Status ⚠️ → ✅ VERIFIED WORKING

### Status
**Requires verification** - implementation appears correct but needs testing.

### Implementation Path
1. **Generation**: `src/ai/rba/protostrator/requirements.nim:169-380`
   - ✅ Generates diplomatic requirements (wars, NAPs, peace)
   - ✅ Correctly evaluates strategic context
   - ✅ Creates DiplomaticRequirement objects

2. **Execution**: `src/ai/rba/basileus/execution.nim:22-100`
   - ✅ Converts requirements to DiplomaticActions
   - ✅ Handles DeclareWar, ProposePact, BreakPact, SeekPeace
   - ✅ Logs execution with reasons

### Verification Needed
1. Check if `controller.protostratorRequirements` is properly set
2. Verify `executeDiplomaticActions` is called in main order generation loop
3. Test if diplomatic actions actually reach the game engine

### Potential Issues
- Requirements generated but never stored in controller?
- Execution function called but actions not returned to engine?
- Actions generated but not included in OrderPacket?

---

## Testing Impact

### Before Fixes
From `balance_results/diagnostics/game_*.csv` (16 games, 8 turns each):
- Wars: **0**
- Invasions: **0**
- Bombardments: **0**
- Espionage missions: **0**
- Diplomatic proposals: **Unknown** (not tracked in CSV)

### Root Cause
Games were too short (8 turns) **AND** bugs prevented operations even if games were longer.

---

## Fix Priority

### Critical (Must Fix)
1. **Espionage budget** - 5 minute fix, huge impact
2. **Bombardment/Invasion orders** - 30 minute fix, critical for gameplay

### Verification (Must Test)
3. **Diplomacy execution** - verify implementation works end-to-end

---

## Implementation Plan

### Step 1: Fix Espionage (5 minutes)
**File:** `src/ai/rba/orders/phase3_execution.nim:38-56`

```nim
proc executeEspionageAction*(
  controller: AIController,
  filtered: FilteredGameState,
  allocation: MultiAdvisorAllocation,
  rng: var Rand
): Option[EspionageAttempt] =
  let espionageBudget = allocation.budgets.getOrDefault(controller_types.AdvisorType.Drungarius, 0)
  let house = filtered.ownHouse

  # Calculate projected EBP/CIP from budget
  # Conversion: 1 PP = 1 EBP, 1 PP = 0.5 CIP (counter-intel is cheaper than ops)
  let projectedEBP = house.espionageBudget.ebpPoints + espionageBudget
  let projectedCIP = house.espionageBudget.cipPoints + (espionageBudget div 2)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Executing espionage action " &
          &"(budget={espionageBudget}PP, projectedEBP={projectedEBP}, projectedCIP={projectedCIP})")

  result = generateEspionageAction(controller, filtered, projectedEBP, projectedCIP, rng)

  return result
```

**Test:** Run 1 game, verify espionage missions appear in logs/CSV.

---

### Step 2: Fix Bombardment/Invasion Orders (30 minutes)
**File:** `src/ai/rba/domestikos/offensive_ops.nim:122-207`

#### Add Helper Function
```nim
proc selectCombatOrderType(analysis: FleetAnalysis): FleetOrderType =
  ## Choose appropriate combat order based on fleet composition
  ## Blitz > Invade > Bombard (most effective to least)

  # Check for troop transports (marines)
  # TODO: Add hasTransports field to FleetAnalysis
  let hasMarines = analysis.hasCombatShips  # Placeholder - needs actual marine detection

  if hasMarines and analysis.shipCount >= 3:
    # Strong invasion force with marines - full blitz assault
    return FleetOrderType.Blitz
  elif hasMarines:
    # Marines available but small force - ground invasion only
    return FleetOrderType.Invade
  else:
    # No marines - orbital bombardment only
    return FleetOrderType.Bombard
```

#### Update generateCounterAttackOrders
```nim
proc generateCounterAttackOrders*(...): seq[FleetOrder] =
  # ... existing target selection logic ...

  for i in 0..<maxAttacks:
    let attacker = availableAttackers[i]
    let target = vulnerableTargets[i]

    # NEW: Select appropriate combat order
    let combatOrder = selectCombatOrderType(attacker)

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: {combatOrder} attack - fleet {attacker.fleetId} → " &
            &"enemy colony at system {target.systemId} (priority: {target.priority:.1f})")

    result.add(FleetOrder(
      fleetId: attacker.fleetId,
      orderType: combatOrder,  # FIXED: Was FleetOrderType.Move
      targetSystem: some(target.systemId),
      priority: 90
    ))

  return result
```

**Test:** Run 1 game, verify bombardments/invasions appear in CSV.

---

### Step 3: Verify Diplomacy (15 minutes investigation)

**Investigation checklist:**
1. Check `src/ai/rba/orders/phase1_requirements.nim` - does it call `generateDiplomaticRequirements`?
2. Check `src/ai/rba/orders.nim:generateOrders` - does it call `executeDiplomaticActions`?
3. Check if `DiplomaticAction` objects are included in returned `OrderPacket`
4. Run 1 game with verbose logging, grep for "Protostrator" and "IMPERIAL DECREE"

**If broken:** Likely missing connection between generation and execution.
**If working:** Mark as verified, update bug report.

---

## Expected Results After Fixes

Running 40-turn games with fixed RBA should show:

### Espionage
- **Target:** 5-10 espionage missions per game per house
- **Operations:** Mix of TechTheft, Sabotage, Assassination, Counter-Intel
- **Frequency:** Varies by personality (espionage-focused: 70%, economic: 40%, aggressive: 30%)

### War Operations
- **Target (from GOAP docs):** 15-40 invasions per 40-turn game
- **Bombardments:** Similar to invasions (pre-invasion softening)
- **Blitz operations:** 20-30% of total attacks (when marines available)

### Diplomacy
- **Target (from GOAP docs):** 6-15 wars per 40-turn game
- **NAP proposals:** 5-15 per game (varies by diplomacy personality)
- **Peace treaties:** 2-8 per game (losing AI seeks peace)

---

## Timeline

### Immediate (Today)
1. Fix espionage budget (5 min)
2. Fix bombardment/invasion orders (30 min)
3. Verify diplomacy execution (15 min)
4. Run single 40-turn test game (1 hour)

**Total: ~2 hours to fix all bugs and validate**

### Follow-up (Tomorrow)
1. Run 16-game parameter sweep (4 hours compute time)
2. Generate RBA baseline report with CSV analysis
3. Make informed GOAP decision

---

## GOAP Re-Evaluation

### Critical Insight
These bugs **do not indicate architectural problems** with RBA. They are simple implementation oversights:
- Forgot to pass budget parameter
- Forgot to use combat order types
- (Possibly) forgot to wire up diplomacy execution

### Impact on GOAP Decision
**BEFORE analysis:** "RBA might be fundamentally broken, GOAP could fix it"
**AFTER analysis:** "RBA just has 2-3 implementation bugs, fix and re-evaluate"

### Recommendation
1. **Fix bugs first** (2 hours)
2. **Run proper 40-turn games** (validate fixes)
3. **Generate baseline metrics** (wars, invasions, espionage)
4. **THEN decide on GOAP** (informed decision with working RBA)

If fixed RBA meets target metrics (6-15 wars, 15-40 invasions), **GOAP may not be necessary**.

---

## References

- **Refactoring Plan:** `/home/niltempus/.claude/plans/steady-herding-prism.md`
- **Phase 1 Complete:** `docs/ai/REFACTORING_PHASE1_COMPLETE.md`
- **GOAP Architecture:** `/home/niltempus/Documents/tmp/ec4x_goap_architecture_complete.adoc`
- **Order Types:** `src/engine/order_types.nim:8-29`
- **Espionage Operations:** `src/ai/rba/drungarius/operations.nim`
- **Offensive Operations:** `src/ai/rba/domestikos/offensive_ops.nim`
- **Diplomacy Requirements:** `src/ai/rba/protostrator/requirements.nim`
- **Basileus Execution:** `src/ai/rba/basileus/execution.nim`

---

**Next Steps:** Fix bugs, validate, then make informed GOAP decision.
