# AI Espionage System Audit

**Date:** 2025-11-25
**Status:** ⚠️ SEVERELY UNDERUTILIZED
**Diagnostic Data:** 0.0012 spy ops per turn (1 per 833 turns!)

---

## Executive Summary

The AI **barely uses espionage** despite it being a major game system with 10 different operations. Key issues:

1. ❌ **Zero EBP/CIP investment** - AI never allocates budget to espionage/counter-intelligence
2. ❌ **Only uses TechTheft** - Ignores 9 other espionage operations
3. ❌ **20% frequency nerf** - Artificially throttled to prevent overuse
4. ❌ **Hard prestige gate** - Won't spy if prestige < 20 (blocks Acts 1-2)
5. ❌ **No strategic targeting** - Random target selection

**Result:** Near-zero espionage activity across 384 games tested.

---

## Espionage System Overview (From Specs)

### Available Operations (10 total)

| Operation | EBP Cost | Effect | Prestige (Self/Target) |
|-----------|----------|--------|------------------------|
| **Tech Theft** | 5 | Steal 10 SRP from target | +20 / -30 |
| **Low Impact Sabotage** | 2 | Reduce 1d6 IU | +10 / -10 |
| **High Impact Sabotage** | 7 | Reduce 1d20 IU | +30 / -50 |
| **Assassination** | 10 | Reduce SRP gain by 50% for 1 turn | +50 / -70 |
| **Cyber Attack** | 6 | Cripple enemy Starbase | +20 / -30 |
| **Economic Manipulation** | 6 | Halve target NCV for 1 turn | +30 / -7 |
| **Psyops Campaign** | 3 | Reduce tax revenue 25% for 1 turn | +10 / -3 |
| **Counter-Intelligence Sweep** | 4 | Block enemy intel for 1 turn | +5 / 0 |
| **Intelligence Theft** | 8 | Steal entire intel database | +40 / -20 |
| **Plant Disinformation** | 6 | Corrupt enemy intel 20-40% for 2 turns | +15 / -15 |

### EBP/CIP Investment System

**Cost:** 40 PP per EBP or CIP point

**Penalty:** Investing > 5% of turn budget loses prestige
- Example: 1000 PP budget → Max 50 PP (1.25 EBP/CIP) before penalties
- 7% investment = -2 prestige per turn

**Detection System:**
- Each detection attempt costs 1 CIP
- CIP 0 = Auto-success for attacker
- CIP 1-5 = +1 detection modifier
- CIP 21+ = +5 detection modifier (max)

**Strategic Balance:**
- Espionage is high-risk, high-reward
- Over-investment causes reputation damage
- Under-investment leaves you vulnerable
- Optimal: ~3-5% budget allocation

---

## Current AI Implementation

### What It Does (ai_controller.nim:1654-1696)

```nim
proc generateEspionageAction(...): Option[EspionageAttempt] =
  # 1. Check EBP availability (need 5+ EBP)
  if house.espionageBudget.ebpPoints < 5:
    return none(...)

  # 2. Prestige gate (won't spy if prestige < 20)
  if house.prestige < 20:
    return none(...)

  # 3. Calculate espionage chance
  let espionageChance =
    riskTolerance * 0.5 +
    (1.0 - aggression) * 0.3 +
    techPriority * 0.2

  # 4. Apply 20% frequency nerf
  if rng.rand(1.0) > (espionageChance * 0.2):
    return none(...)

  # 5. Random target selection
  let target = targetHouses[rng.rand(targetHouses.len - 1)]

  # 6. Only TechTheft
  return some(EspionageAttempt(
    action: TechTheft,
    ...
  ))
```

### What It DOESN'T Do

```nim
# AI sets these to ZERO every turn
ebpInvestment: 0,  # ← NEVER invests in espionage budget!
cipInvestment: 0   # ← NEVER invests in counter-intelligence!
```

**Result:** Without EBP investment, AI can never reach 5 EBP threshold → Can't spy at all!

---

## Problems Identified

### 🔴 Critical: Zero Budget Investment

**Issue:** AI never allocates PP to EBP/CIP
**Impact:** Can't perform espionage (needs 5+ EBP minimum)
**Fix Required:** Add EBP/CIP budget allocation logic

**Recommended allocation:**
- Defensive AI: 2-3% to CIP (counter-intelligence)
- Balanced AI: 1-2% to EBP, 2-3% to CIP
- Aggressive AI: 0-1% (focus on military)
- Economic AI: 3-4% to EBP (tech theft, sabotage)

### 🔴 Critical: Only Uses TechTheft

**Issue:** AI ignores 9 other espionage operations
**Impact:** Missing strategic depth

**Operations AI should use:**

**Offensive (vs Leader):**
- High Impact Sabotage (7 EBP) - Cripple leader's production
- Assassination (10 EBP) - Slow leader's tech advancement
- Cyber Attack (6 EBP) - Disable starbases before invasion
- Economic Manipulation (6 EBP) - Weaken economic powerhouses

**Defensive:**
- Counter-Intelligence Sweep (4 EBP) - Protect during critical turns
- Plant Disinformation (6 EBP) - Mislead aggressive neighbors

**Intelligence Warfare:**
- Intelligence Theft (8 EBP) - Steal strategic knowledge
- Psyops Campaign (3 EBP) - Economic harassment (cheap!)

### 🟡 High: Random Target Selection

**Issue:** No strategic targeting
**Impact:** Wastes espionage on irrelevant targets

**Strategic targeting needed:**
- Spy on **prestige leader** (disrupt their lead)
- Sabotage **economic powerhouses** (reduce production)
- Cyber attack **invasion targets** (soften defenses)
- Tech theft from **tech leaders** (catch up)
- Counter-intel during **own invasions** (protect plans)

### 🟡 High: 20% Frequency Nerf

**Issue:** Comment says "dramatically reduce" frequency
**Impact:** Even high-espionage AIs barely spy

**Analysis:**
- High espionage personality: 78% base chance
- After 20% nerf: 15.6% per turn
- With prestige gate: ~5% actual usage

**Recommendation:** Remove or reduce nerf to 0.5x (50% chance)

### 🟢 Medium: Prestige Gate Too High

**Issue:** Won't spy if prestige < 20
**Impact:** Blocks Acts 1-2 espionage entirely

**Analysis:**
- Act 1 avg prestige: ~400-700
- Act 2 avg prestige: ~400-800
- Prestige < 20 only happens at game end (collapse)

**Recommendation:** Lower to prestige < 0 (only block if collapsing)

---

## Recommended Implementation

### Phase 1: Add EBP/CIP Budget Allocation

**Location:** `ai_controller.nim:1847-1848`

```nim
proc calculateEspionageInvestment(house: House, personality: AIPersonality,
                                  availableBudget: int, act: GameAct): (int, int) =
  ## Calculate EBP and CIP investment based on personality and game phase
  ##
  ## Optimal investment: 3-5% of budget
  ## Over 5% → Prestige penalties

  # Base allocation by personality
  let ebpPercent =
    personality.riskTolerance * 0.02 +        # 0-2%
    (1.0 - personality.aggression) * 0.02 +   # 0-2%
    personality.techPriority * 0.01           # 0-1%

  let cipPercent =
    (1.0 - personality.riskTolerance) * 0.02 + # 0-2%
    personality.defensiveFocus * 0.02          # 0-2%

  # Scale by game act
  let actMultiplier = case act
    of GameAct.Act1_Expansion: 0.3      # Low espionage early
    of GameAct.Act2_Conflict: 0.7       # Ramp up
    of GameAct.Act3_TotalWar: 1.0       # Full espionage
    of GameAct.Act4_Endgame: 1.2        # All-in

  # Calculate PP allocation (max 5% to avoid prestige loss)
  let ebpBudget = min(int(availableBudget.float * ebpPercent * actMultiplier),
                      int(availableBudget.float * 0.05))
  let cipBudget = min(int(availableBudget.float * cipPercent * actMultiplier),
                      int(availableBudget.float * 0.05))

  # Convert PP to EBP/CIP (40 PP per point)
  let ebpPoints = ebpBudget div 40
  let cipPoints = cipBudget div 40

  return (ebpPoints, cipPoints)
```

**Usage:**
```nim
let (ebpInvest, cipInvest) = calculateEspionageInvestment(
  house, personality, availableBudget, act)

result = OrderPacket(
  ...
  ebpInvestment: ebpInvest,  # ← Was 0
  cipInvestment: cipInvest   # ← Was 0
)
```

### Phase 2: Add Strategic Operation Selection

**Location:** `ai_controller.nim:1654` (replace current function)

```nim
proc selectEspionageOperation(controller: AIController,
                              filtered: FilteredGameState,
                              target: HouseId): EspionageAction =
  ## Choose espionage operation based on strategic context

  let p = controller.personality
  let house = filtered.ownHouse
  let ebp = house.espionageBudget.ebpPoints

  # Get target's relative strength
  let targetPrestige = filtered.housePrestige.getOrDefault(target, 0)
  let myPrestige = house.prestige
  let prestigeGap = targetPrestige - myPrestige

  # High-value operations when behind
  if prestigeGap > 200 and ebp >= 10:
    return EspionageAction.Assassination  # Slow down leader

  if prestigeGap > 100 and ebp >= 7:
    return EspionageAction.HighImpactSabotage  # Cripple production

  # Economic warfare
  if p.economicFocus > 0.6 and ebp >= 6:
    return EspionageAction.EconomicManipulation

  # Tech theft (default)
  if ebp >= 5:
    return EspionageAction.TechTheft

  # Cheap harassment
  if ebp >= 3:
    return EspionageAction.PsyopsCampaign

  # Low-cost sabotage
  if ebp >= 2:
    return EspionageAction.LowImpactSabotage

  # No operation if insufficient EBP
  return EspionageAction.TechTheft  # Fallback (won't execute if < 5 EBP)
```

### Phase 3: Add Strategic Targeting

```nim
proc selectEspionageTarget(controller: AIController,
                          filtered: FilteredGameState): HouseId =
  ## Choose espionage target strategically

  let house = filtered.ownHouse
  let myPrestige = house.prestige

  var targets: seq[tuple[houseId: HouseId, priority: float]] = @[]

  for houseId, prestige in filtered.housePrestige:
    if houseId == controller.houseId:
      continue

    var priority = 0.0

    # Target prestige leaders (disrupt them)
    let prestigeGap = prestige - myPrestige
    if prestigeGap > 0:
      priority += prestigeGap.float * 0.01

    # Target diplomatic enemies
    let relation = house.diplomaticRelations.getOrDefault(houseId, Neutral)
    if relation == Enemy:
      priority += 100.0

    # Target neighbors (more vulnerable)
    # TODO: Check if they border our territory

    # Bonus for economic powerhouses (if we can see their production)
    # TODO: Check intelligence database for production intel

    targets.add((houseId, priority))

  # Sort by priority (highest first)
  targets.sort(proc(a, b: auto): int = cmp(b.priority, a.priority))

  if targets.len > 0:
    return targets[0].houseId

  # Fallback: random
  let allHouses = toSeq(filtered.housePrestige.keys)
  return allHouses[rng.rand(allHouses.len - 1)]
```

### Phase 4: Add Defensive Counter-Intelligence

```nim
proc shouldUseCounterIntel(controller: AIController,
                           filtered: FilteredGameState): bool =
  ## Decide if we should use Counter-Intelligence Sweep this turn

  let house = filtered.ownHouse

  # Protect during invasions
  for op in controller.operations:
    if op.opType == OperationType.Invasion and op.status == InProgress:
      return true  # Protect invasion plans

  # Protect when prestige is high (we're winning)
  if house.prestige > 800:
    return true  # Leaders are targets

  # Protect during critical turns (every 5 turns?)
  if filtered.turn mod 5 == 0:
    return true

  return false
```

---

## Expected Impact

### With Full Espionage Implementation:

**Espionage Frequency:**
- Currently: 0.0012 ops/turn (1 per 833 turns)
- Expected: 0.2-0.4 ops/turn (1 per 2.5-5 turns)
- **Increase: 165-333x**

**Strategic Depth:**
- Leaders face sabotage/assassination pressure
- Economic AI can disrupt rivals
- Defensive AI protects with counter-intel
- Intelligence warfare (theft, disinformation)

**Balance Impact:**
- **Economic Strategy:** More vulnerable to sabotage (currently invincible)
- **Aggressive Strategy:** Can soften targets before invasion (cyber attacks)
- **Balanced Strategy:** Espionage flexibility advantage
- **Turtle Strategy:** Counter-intel protects defensive posture

---

## Files Requiring Changes

1. **tests/balance/ai_controller.nim**
   - `calculateEspionageInvestment()` - NEW function
   - `selectEspionageOperation()` - Replace existing
   - `selectEspionageTarget()` - NEW function
   - `shouldUseCounterIntel()` - NEW function
   - `generateAIOrders()` - Update ebpInvestment/cipInvestment

2. **tests/balance/diagnostics.nim**
   - Track espionage by operation type
   - Track EBP/CIP investment levels
   - Track detection rates

3. **src/ai/rba/budget.nim** (optional)
   - Add EspionageBudget objective to allocation system
   - Currently: Expansion, Defense, Military, Intelligence, SpecialUnits, Technology
   - Add: Espionage (EBP/CIP allocation)

---

## Testing Recommendations

### Diagnostic Metrics to Track

1. **Espionage Frequency**
   - Operations per turn by type
   - EBP/CIP investment levels
   - Detection rates

2. **Strategic Usage**
   - Target selection (leader vs random)
   - Operation type by game phase
   - Counter-intel usage frequency

3. **Balance Impact**
   - Prestige changes from espionage
   - Production lost to sabotage
   - SRP stolen via tech theft
   - Starbase downtime from cyber attacks

### Test Scenarios

1. **Espionage Personality Test** (high riskTolerance, low aggression)
   - Should spy frequently (20-40% of turns)
   - Should invest 4-5% in EBP
   - Should target prestige leaders

2. **Defensive Personality Test** (low riskTolerance, high defensiveFocus)
   - Should invest 3-4% in CIP
   - Should use Counter-Intel frequently
   - Should resist enemy espionage

3. **Balanced 4-Act Test**
   - Measure espionage impact on win rates
   - Track prestige volatility (espionage creates swings)
   - Verify no AI over-invests (> 5% penalty)

---

## Conclusion

The espionage system is **fully implemented in the engine** but **completely unutilized by the AI**. This represents a major missed strategic layer.

**Priority: HIGH**
- Espionage can significantly impact late-game balance
- Currently Economic strategy is invincible (no sabotage pressure)
- Adds strategic depth and unpredictability
- Relatively small code change (1 file, ~200 lines)

**Recommendation:** Implement Phases 1-2 (budget + operations), test impact, then add Phases 3-4 (targeting + counter-intel) if needed.

---

**Generated:** 2025-11-25
**Context:** 4-act balance testing revealed near-zero espionage usage
**Estimated Implementation Time:** 2-3 hours for Phases 1-2
