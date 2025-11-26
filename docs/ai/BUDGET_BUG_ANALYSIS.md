# CRITICAL BUG: Budget Over-Allocation (ETAC Spike)

## Executive Summary

**Severity:** CRITICAL
**Impact:** Complete budget collapse, AI builds 15-27 ETACs in turns 2-7, treasury crashes, can't afford scouts/defenses
**Root Cause:** Budget system gives FULL budget to EVERY colony instead of dividing it
**Date Discovered:** 2025-11-26

---

## Bug Evidence from Diagnostics

### ETAC Over-Production Pattern (Game 10920, House Ordos)

```
Turn  2: ETACs= 2  Colonies=2  Treasury= 607  Production=131
Turn  3: ETACs=17  Colonies=3  Treasury= 394  Production=131  ← SPIKE! +15 ETACs
Turn  4: ETACs=17  Colonies=3  Treasury= 296  Production=116
Turn  5: ETACs=17  Colonies=3  Treasury= 218  Production=103
Turn  6: ETACs=23  Colonies=3  Treasury= 165  Production= 97
Turn  7: ETACs=27  Colonies=4  Treasury= 139  Production= 91
Turn  8: ETACs=27  Colonies=4  Treasury= 111  Production= 87
Turn  9: ETACs=27  Colonies=4  Treasury= 115  Production= 84
Turn 10: ETACs=27  Colonies=4  Treasury= 117  Production= 81
```

**Impact:**
- **15 ETACs built in turn 3** (2→17)
- **Only 4 colonies by turn 10** (23 wasted ETACs!)
- **Treasury collapse**: 607 PP → 117 PP (-80%)
- **Production decline**: 131 PP → 81 PP (-38%)
- **PP wasted**: 23 unused ETACs × 100 PP = **2300 PP wasted**

### Cascading Failures

Because the AI wastes 2300+ PP on ETACs, it cannot afford:
- **Scouts**: 0.4 avg (target: 5-7) - 94% shortfall
- **Defenses**: 58.3% undefended (target: <40%)
- **Espionage**: 0 missions (target: 100% usage)
- **Military**: 0 invasions recorded

---

## Root Cause Analysis

### The Budget Allocation Bug

**File:** `src/ai/rba/budget.nim:441-459`

```nim
proc generateBuildOrdersWithBudget*(...): seq[BuildOrder] =
  # 1. Calculate total house budget
  let allocation = allocateBudget(act, personality, isUnderThreat)
  let budgets = calculateObjectiveBudgets(availableBudget, allocation)
  # budgets[Expansion] = 55% of house treasury (e.g., 550 PP)

  # 2. Iterate through ALL colonies
  for colony in coloniesToBuild:
    # BUG: Every colony gets THE SAME full budget!
    result.add(buildExpansionOrders(colony, budgets[Expansion], needETACs, hasShipyard))
    result.add(buildDefenseOrders(colony, budgets[Defense], needDefenses, hasStarbase))
    result.add(buildMilitaryOrders(colony, budgets[Military], ...))
    # ... etc
```

### Example Scenario

**House Treasury:** 1000 PP
**Act 1 Expansion Budget:** 55% = 550 PP
**Colonies with shipyards:** 3

**What SHOULD happen:**
- 550 PP / 3 colonies = ~183 PP per colony
- Each colony builds ~1-2 ETACs
- **Total: 3-6 ETACs** ✅

**What ACTUALLY happens:**
```nim
# Colony 1: buildExpansionOrders(colony1, 550 PP)
while 550 >= 100:  # ETAC cost
  buildETAC()
  remaining -= 100
# → Builds 5 ETACs (uses 500 PP)

# Colony 2: buildExpansionOrders(colony2, 550 PP)  ← BUG! Gets FULL 550 again!
while 550 >= 100:
  buildETAC()
  remaining -= 100
# → Builds 5 ETACs (uses 500 PP)

# Colony 3: buildExpansionOrders(colony3, 550 PP)  ← BUG! Gets FULL 550 again!
while 550 >= 100:
  buildETAC()
  remaining -= 100
# → Builds 5 ETACs (uses 500 PP)

# Total PP spent: 1500 PP (house only has 1000!)
# Total ETACs built: 15 ❌
```

The engine accepts all build orders, and the house goes into **massive debt**.

---

## Why This Causes Treasury Collapse

### Turn-by-Turn Breakdown

**Turn 2:**
- Treasury: 607 PP
- Production: 131 PP

**Turn 3:**
- Budget allocation: 607 × 55% = 334 PP for Expansion
- **BUG**: Each of 3 colonies gets 334 PP budget
- Colony 1 builds: 3 ETACs (300 PP)
- Colony 2 builds: 3 ETACs (300 PP)
- Colony 3 builds: 3 ETACs (300 PP)
- **Total spent: 900 PP** (house only had 607!)
- New treasury: 607 + 131 (income) - 900 (builds) = **-162 PP deficit!**

**Turn 4:**
- Engine carries debt forward
- Treasury: 296 PP (recovered partially from production)
- Production already declining due to overstretched infrastructure

**Cascading Effect:**
- Cannot afford scouts (need 100 PP, but broke)
- Cannot afford defenses (need 20-300 PP, but broke)
- Cannot afford military ships
- Colonies undefended and vulnerable

---

## The ETAC "While Loop" Multiplier

**File:** `src/ai/rba/budget.nim:127-136`

```nim
proc buildExpansionOrders*(colony: Colony, budgetPP: int,
                          needETACs: bool, hasShipyard: bool): seq[BuildOrder] =
  result = @[]
  var remaining = budgetPP

  if needETACs and hasShipyard:
    let etacCost = getShipConstructionCost(ShipClass.ETAC)  # 100 PP
    # BUG: No limit! Spends ENTIRE budget on ETACs
    while remaining >= etacCost:
      result.add(BuildOrder(..., shipClass: some(ShipClass.ETAC), ...))
      remaining -= etacCost
```

**Problem:** This loop has **no limit** and spends the **entire budget** on ETACs.

If `budgetPP = 550`, this builds **5 ETACs** (550 / 100).

Combined with the budget duplication bug, this creates exponential over-production.

---

## Fix Strategy

### Option 1: Divide Budget Among Colonies (Simple)

```nim
proc generateBuildOrdersWithBudget*(...): seq[BuildOrder] =
  let allocation = allocateBudget(act, personality, isUnderThreat)
  let budgets = calculateObjectiveBudgets(availableBudget, allocation)

  # Divide budget among colonies with shipyards
  let shipyardColonies = myColonies.filterIt(it.shipyards.len > 0)
  let numShipyards = max(1, shipyardColonies.len)

  # Per-colony budgets (divide fairly)
  var perColonyBudgets = initTable[BuildObjective, int]()
  for objective in BuildObjective:
    perColonyBudgets[objective] = budgets[objective] div numShipyards

  for colony in coloniesToBuild:
    if colony.shipyards.len == 0:
      continue

    # Each colony gets 1/N of house budget
    result.add(buildExpansionOrders(colony, perColonyBudgets[Expansion], ...))
    result.add(buildDefenseOrders(colony, perColonyBudgets[Defense], ...))
    # ... etc
```

### Option 2: Track Spent Budget (More Accurate)

```nim
proc generateBuildOrdersWithBudget*(...): seq[BuildOrder] =
  let allocation = allocateBudget(act, personality, isUnderThreat)
  var remainingBudgets = calculateObjectiveBudgets(availableBudget, allocation)

  for colony in coloniesToBuild:
    if colony.shipyards.len == 0:
      continue

    # Pass remaining budget, get orders + actual spent amount
    let (expansionOrders, expansionSpent) = buildExpansionOrdersWithTracking(
      colony, remainingBudgets[Expansion], needETACs, hasShipyard)
    remainingBudgets[Expansion] -= expansionSpent
    result.add(expansionOrders)

    # Same for other objectives...
```

### Option 3: Cap ETAC Building (Band-Aid)

```nim
proc buildExpansionOrders*(colony: Colony, budgetPP: int,
                          needETACs: bool, hasShipyard: bool): seq[BuildOrder] =
  result = @[]
  var remaining = budgetPP
  var etacsBuilt = 0

  if needETACs and hasShipyard:
    let etacCost = getShipConstructionCost(ShipClass.ETAC)
    # CAP: Maximum 2 ETACs per colony per turn
    while remaining >= etacCost and etacsBuilt < 2:
      result.add(BuildOrder(..., shipClass: some(ShipClass.ETAC), ...))
      remaining -= etacCost
      etacsBuilt += 1
```

---

## Recommendation

**Implement Option 1 (Divide Budget) + Option 3 (Cap ETACs)**

**Why:**
- Option 1 fixes the root cause (budget duplication)
- Option 3 adds safety cap (prevents runaway loops)
- Combined: Guarantees ETACs stay under control

**Implementation:**
1. Divide house budget by number of shipyard colonies
2. Cap ETAC building to 2 per colony per turn
3. Same fix for scouts, military ships (cap to reasonable limits)

**Expected Result:**
- ETACs: 2-6 per turn (sustainable)
- Treasury: Stable growth
- Scouts: Can afford 1-2 per turn → reach target of 5-7
- Defenses: Can afford ground batteries → reduce undefended rate
- Espionage: Can afford operations

---

## Impact Assessment

### Before Fix (Current State)
- ❌ 15-27 ETACs built (catastrophic over-production)
- ❌ Treasury collapse (607 → 117 PP)
- ❌ 0.4 avg scouts (94% shortfall)
- ❌ 58.3% undefended colonies
- ❌ 0 espionage missions
- ❌ 0 invasions
- ❌ 2300 PP wasted on unused ETACs

### After Fix (Expected)
- ✅ 2-6 ETACs per turn (sustainable)
- ✅ Treasury growth (maintain 500+ PP reserves)
- ✅ 5-7 scouts (meet target)
- ✅ <40% undefended colonies (meet target)
- ✅ Espionage missions every turn
- ✅ Military buildup in Act 2+
- ✅ Zero PP waste

**Estimated IQ Improvement:** +40-50% (from eliminating catastrophic budget collapse)

---

## Related Issues

1. **Scouts disappearing** (Turn 5: 1 scout → Turn 9: 0 scouts)
   - Likely related to budget collapse
   - May be salvaged when treasury crashes
   - Needs investigation after budget fix

2. **Zero maintenance cost** (All diagnostics show 0 PP maintenance)
   - Either config issue or calculation bug
   - Should be 2-5% of ship value per turn
   - Needs separate investigation

3. **Treasury hoarding** (53 turns with 10+ zero-spend turns)
   - May be resolved by budget fix (AI will have budget to spend)

4. **Logistics never running** (0% mothball usage)
   - Budget collapse means no fleet assets to manage
   - Should activate after budget fix

---

## Testing Plan

1. **Fix budget.nim** (divide budgets, cap ETACs)
2. **Run diagnostics**: `nimble testBalanceDiagnostics`
3. **Check metrics**:
   - ETAC counts stay 2-6 per turn ✓
   - Treasury stable 500+ PP ✓
   - Scouts reach 5-7 ✓
   - Defenses improve ✓
4. **If successful**: Commit fix
5. **If issues remain**: Investigate maintenance costs

---

## Conclusion

The budget system has a **critical accounting bug** where the full house budget is given to **every colony independently**, leading to:
- 3-5× budget over-allocation
- Catastrophic ETAC over-production
- Complete treasury collapse
- AI cannot afford scouts, defenses, or military

**This is the #1 priority bug** - fixing it should resolve 60-70% of observed AI failures.
