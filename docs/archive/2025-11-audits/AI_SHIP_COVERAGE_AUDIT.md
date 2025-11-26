# AI Ship Building Coverage Audit

**Date:** 2025-11-25
**Context:** Post-balance testing analysis
**Issue:** AI not utilizing full tech stack

---

## Ship Types Available in Game (19 total)

From `src/common/types/units.nim` and `docs/specs/reference.md`:

### Combat Ships
| Ship Class | CST | Cost | AS | DS | Currently Built by AI? |
|------------|-----|------|----|----|------------------------|
| **Corvette (CT)** | 1 | 20 PP | 2 | 3 | ❌ NO |
| **Frigate (FG)** | 1 | 30 PP | 3 | 4 | ✅ YES (early backbone) |
| **Destroyer (DD)** | 1 | 40 PP | 5 | 6 | ❌ NO |
| **Light Cruiser (CL)** | 1 | 60 PP | 8 | 9 | ❌ NO |
| **Heavy Cruiser (CA)** | 2 | 80 PP | 12 | 13 | ❌ NO |
| **Battle Cruiser (BC)** | 3 | 100 PP | 16 | 18 | ⚠️ PARTIAL (called "Cruiser") |
| **Battleship (BB)** | 4 | 150 PP | 20 | 25 | ❌ NO |
| **Dreadnought (DN)** | 5 | 200 PP | 28 | 30 | ✅ YES (late-game) |
| **Super Dreadnought (SD)** | 6 | 250 PP | 35 | 40 | ❌ NO |

### Special Purpose Ships
| Ship Class | CST | Cost | Purpose | Built by AI? |
|------------|-----|------|---------|--------------|
| **Scout (SC)** | 1 | 50 PP | Reconnaissance | ✅ YES |
| **Raider (RR)** | 3 | 150 PP | CLK stealth attacks | ✅ YES |
| **Fighter Squadron (FS)** | 3 | 20 PP | Carrier-based combat | ✅ YES |
| **Carrier (CV)** | 3 | 120 PP | Fighter transport | ✅ YES |
| **Super Carrier (CX)** | 5 | 200 PP | Heavy fighter transport | ❌ NO |
| **Starbase (SB)** | 3 | 300 PP | Orbital fortress | ✅ YES |

### Support Ships
| Ship Class | CST | Cost | Purpose | Built by AI? |
|------------|-----|------|---------|--------------|
| **ETAC** | 1 | 80 PP | Colony ship | ✅ YES |
| **Troop Transport (TT)** | 1 | 100 PP | Marine transport | ✅ YES |

### Siege Weapons
| Ship Class | CST | Cost | Purpose | Built by AI? |
|------------|-----|------|---------|--------------|
| **Planet-Breaker (PB)** | 10 | 400 PP | Shield-penetrating bombardment | ❌ NO |

---

## Current AI Build Logic (src/ai/rba/budget.nim)

### What AI Actually Builds:

**Expansion:**
- ✅ ETAC (colony ships)

**Defense:**
- ✅ Starbase
- ✅ Ground Batteries (up to 5 per colony)

**Military:**
- ✅ Frigate (30 PP) - early game
- ⚠️ "Cruiser" (code says Cruiser, likely Battle Cruiser 100 PP) - mid game
- ✅ Dreadnought (200 PP) - late game

**Intelligence:**
- ✅ Scout (up to 10 per house)

**Special Units:**
- ✅ Carrier (150 PP)
- ✅ Troop Transport (100 PP)
- ✅ Raider (100 PP) - when CLK researched
- ✅ Fighter (20 PP) - cheap filler

---

## Missing Ships: Critical Analysis

### ❌ Corvettes (CT) - 20 PP, AS 2, DS 3
**Why Missing Matters:** Cheapest combat ship, cost-effective early screening units
**Impact:** AI overbuilds expensive Frigates when Corvettes could fill gaps
**Priority:** LOW (Frigates work fine)

### ❌ Destroyers (DD) - 40 PP, AS 5, DS 6
**Why Missing Matters:** Bridge between Frigates (30 PP) and "Cruisers" (100 PP)
**Impact:** No mid-tier option, AI jumps from 30 PP → 100 PP (3.3x cost leap)
**Priority:** MEDIUM (fills strategic gap)

### ❌ Light Cruisers (CL) - 60 PP, AS 8, DS 9
**Why Missing Matters:** Cost-effective mid-game workhorse
**Impact:** Better PP/AS ratio than current "Cruiser" build
**Priority:** MEDIUM

### ❌ Heavy Cruisers (CA) - 80 PP, AS 12, DS 13
**Why Missing Matters:** Strong mid-game combat ship
**Impact:** Another missing tier in progression
**Priority:** MEDIUM

### ⚠️ Battle Cruisers (BC) - 100 PP, AS 16, DS 18
**Status:** PROBABLY BUILT (code calls it "Cruiser")
**Issue:** Need to verify ShipClass enum used
**Priority:** LOW (likely working)

### ❌ Battleships (BB) - 150 PP, AS 20, DS 25
**Why Missing Matters:** Late-game heavy hitter between BC and DN
**Impact:** Another tier gap (100 PP → 200 PP jump)
**Priority:** MEDIUM

### ❌ Super Dreadnoughts (SD) - 250 PP, AS 35, DS 40
**Why Missing Matters:** Ultimate late-game capital ship
**Impact:** AI never builds strongest combat unit
**Priority:** HIGH (endgame balance)

### ❌ Super Carriers (CX) - 200 PP, CL 5
**Why Missing Matters:** Holds 5-8 fighters vs CV's 3-5
**Impact:** AI can't maximize fighter doctrine investment
**Priority:** HIGH (fighter doctrine synergy)

### ❌ Planet-Breakers (PB) - 400 PP, AS 50 (shield penetration)
**Why Missing Matters:** ONLY counter to planetary shields
**Impact:** AI cannot break defensive stalemates in Acts 3-4
**Priority:** **CRITICAL** (explains balance issues)

---

## Impact on Balance Testing Results

### Economic Strategy Dominance (70-80% win rate)
**Cause:** No late-game counters to fortified colonies
- Economic builds shields + batteries
- Aggressive can't crack defenses (no Planet-Breakers)
- Economic snowballs unchallenged

### Aggressive Strategy Collapse After Act 1
**Cause:** Missing capital ship progression
- Jumps Frigate (30 PP) → "Cruiser" (100 PP) → Dreadnought (200 PP)
- Missing 5 ship tiers: DD, CL, CA, BB, SD
- Can't efficiently scale military spending

### Turtle Strategy Becomes Viable Acts 3-4
**Cause:** No Planet-Breakers to counter shields
- Turtle builds SLD5-6 shields
- Aggressive has no shield penetration
- Shields are nearly invincible

### Fighter Doctrine Underutilized
**Cause:** No Super Carriers
- CV holds 3-5 fighters max
- CX holds 5-8 fighters (60% more capacity)
- Fighter Doctrine investment wasted without CX

---

## Recommended Implementation Priority

### 🔴 CRITICAL (Breaks Late-Game Balance)
1. **Planet-Breakers** - Essential for siegecraft, counters shields
   - Requires CST 10 tech gate
   - 1 per colony ownership limit logic
   - Build when planning invasions of SLD4+ colonies

2. **Super Carriers** - Maximizes Fighter Doctrine investment
   - Requires CST 5 (same as Dreadnought)
   - Build when FD researched + CV capacity full

3. **Super Dreadnoughts** - Strongest combat unit
   - Requires CST 6
   - Build in Act 4 when treasury > 1000 PP

### 🟡 HIGH (Improves Strategic Depth)
4. **Battleships** - Missing late-game tier
5. **Heavy Cruisers** - Cost-effective mid-game

### 🟢 MEDIUM (Nice to Have)
6. **Destroyers** - Early-mid bridge ship
7. **Light Cruisers** - Cost-efficient option

### ⚪ LOW (Optional)
8. **Corvettes** - Redundant with Frigates

---

## Proposed Implementation

### Phase 1: Add Missing Ship Types to Military Build Logic

**Current logic (budget.nim:174-180):**
```nim
let shipClass =
  if remaining >= 200 and militaryCount > 8:
    ShipClass.Dreadnought  # Late-game heavy hitters
  elif remaining >= 120 and militaryCount > 4:
    ShipClass.Cruiser      # Mid-game workhorses
  else:
    ShipClass.Frigate      # Early-game backbone
```

**Proposed logic:**
```nim
let shipClass =
  if remaining >= 250 and act >= GameAct.Act4 and cstLevel >= 6:
    ShipClass.SuperDreadnought  # Act 4 ultimate weapon
  elif remaining >= 200 and act >= GameAct.Act3 and cstLevel >= 5:
    ShipClass.Dreadnought       # Act 3-4 heavy hitter
  elif remaining >= 150 and act >= GameAct.Act3 and cstLevel >= 4:
    ShipClass.Battleship        # Act 3 backbone
  elif remaining >= 100 and act >= GameAct.Act2 and cstLevel >= 3:
    ShipClass.Battlecruiser     # Act 2-3 workhorse
  elif remaining >= 80 and cstLevel >= 2:
    ShipClass.HeavyCruiser      # Mid-game
  elif remaining >= 60:
    ShipClass.LightCruiser      # Early-mid
  elif remaining >= 40:
    ShipClass.Destroyer         # Early bridge
  else:
    ShipClass.Frigate           # Early backbone
```

### Phase 2: Add Super Carrier Logic

**Add to buildSpecialUnitsOrders():**
```nim
# Prioritize Super Carriers over regular Carriers when available
if canAffordMoreShips and needCarriers and remaining >= 200 and cstLevel >= 5:
  result.add(BuildOrder(
    shipClass: some(ShipClass.SuperCarrier),  # CX - better capacity
    ...
  ))
  remaining -= 200
elif canAffordMoreShips and needCarriers and remaining >= 120:
  result.add(BuildOrder(
    shipClass: some(ShipClass.Carrier),  # CV - fallback
    ...
  ))
  remaining -= 120
```

### Phase 3: Add Planet-Breaker Logic

**New function:**
```nim
proc buildSiegeOrders*(colony: Colony, budgetPP: int,
                      planetBreakerCount: int, colonyCount: int,
                      cstLevel: int, needSiege: bool): seq[BuildOrder] =
  ## Generate siege weapon orders (Planet-Breakers)
  ##
  ## Planet-Breakers require:
  ## - CST 10 (highest tier)
  ## - 400 PP cost
  ## - Max 1 per owned colony
  ## - Strategic asset for breaking SLD4+ colonies

  result = @[]
  var remaining = budgetPP

  # Only build if we can afford it and haven't hit colony limit
  if not needSiege or cstLevel < 10 or planetBreakerCount >= colonyCount:
    return

  if remaining >= 400:
    result.add(BuildOrder(
      colonySystem: colony.systemId,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.PlanetBreaker),
      buildingType: none(string),
      industrialUnits: 0
    ))
```

**Add to budget allocation:**
```nim
# Act 4: Add siege budget for Planet-Breakers
of GameAct.Act4_Endgame:
  {
    Expansion: 0.00,
    Defense: 0.10,
    Military: 0.50,      # Reduced from 60%
    Intelligence: 0.05,
    SpecialUnits: 0.15,
    Technology: 0.10,
    Siege: 0.10          # NEW: Planet-Breaker budget
  }.toTable()
```

### Phase 4: Add Tech-Gated Unlock System

Track tech levels in AI controller:
```nim
proc getTechLevel(house: House, field: TechField): int =
  ## Get current tech level for a field
  return house.techLevels[field]

proc getCST Level(house: House): int =
  ## Get current Construction tech level
  return getTechLevel(house, TechField.CST)
```

---

## Testing Impact Predictions

### With Full Ship Roster:

**Aggressive Strategy:**
- ✅ Smoother military scaling (no 30→100→200 PP gaps)
- ✅ Better PP efficiency (Light/Heavy Cruisers, Battleships)
- ✅ Planet-Breakers break shield stalemates
- **Predicted Win Rate:** 9% → 25-30% (Acts 2-4)

**Economic Strategy:**
- ⚠️ Shields no longer invincible (Planet-Breaker counter)
- ⚠️ Must invest in ground batteries AND shields
- **Predicted Win Rate:** 75% → 50-60% (still strong, less dominant)

**Turtle Strategy:**
- ⚠️ Shields now vulnerable to Planet-Breakers
- ✅ Can build own Planet-Breakers for defense
- **Predicted Win Rate:** 16-20% → 15-20% (similar)

**Balanced Strategy:**
- ✅ Benefits from all ship types
- ✅ Flexibility advantage (can build anything)
- **Predicted Win Rate:** 0% → 10-15% (still weak, but functional)

---

## Files Requiring Changes

1. **src/ai/rba/budget.nim** - Add all missing ships to build logic
2. **tests/balance/ai_controller.nim** - Update build flags/conditions
3. **tests/balance/diagnostics.nim** - Track Planet-Breaker usage
4. **src/ai/rba/strategic.nim** - Add siege planning logic
5. **config/ships.toml** - Verify all ship costs correct

---

## Conclusion

The AI is currently using only **9 of 19 ship types (47% coverage)**. Missing ships include:

- 5 capital ship tiers (DD, CL, CA, BB, SD)
- Super Carriers (fighter doctrine synergy)
- Planet-Breakers (shield penetration)

This explains major balance issues:
- Economic dominance (no siege counters)
- Aggressive collapse (inefficient military spending)
- Turtle viability (invincible shields)

**Recommendation:** Implement all missing ships with tech-gated unlocks. Priority: Planet-Breakers → Super Carriers → Capital ship progression.

---

**Generated:** 2025-11-25
**Context:** 4-act balance testing analysis
