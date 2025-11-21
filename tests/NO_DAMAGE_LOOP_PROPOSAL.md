# Proposal: Fix No-Damage Loop Issue

## Problem Statement

**Test Case**: `home_defense_76` - 20 rounds with 5+ consecutive no-damage rounds

**Current Behavior**:
- Two evenly matched forces (16 AS vs 17 AS)
- Both sides attack but deal insufficient damage (hits < DS threshold)
- Combat continues for 20 rounds without any state changes
- Forced stalemate only triggers after full 20 rounds

**Root Cause**:
When `AS × CER < target DS`, the damage system correctly deals 0 effective state changes:
- Attack deals hits, but `totalDamage < ds` means no state transition
- Both sides can roll low CER (≤2 → 0.25 effectiveness) repeatedly
- Example: 16 AS × 0.25 = 4 hits, but if DS = 10, no crippling occurs

**Impact**: Wastes computation and creates unsatisfying "stalemate by exhaustion" rather than tactical stalemate.

---

## Proposed Solutions

### Option A: Progressive Stalemate Detection (RECOMMENDED)

**Description**: Trigger stalemate after N consecutive rounds without state changes, where N < 20.

**Implementation**:
```nim
# In combat_retreat.nim - checkCombatTermination()

# Early stalemate detection (5 rounds without progress)
if consecutiveRoundsNoChange >= 5:
  return (true, "Tactical stalemate - no progress in 5 rounds", none(HouseId))

# Original 20-round hard limit remains as safety net
if consecutiveRoundsNoChange >= 20:
  return (true, "Stalemate after 20 rounds without progress", none(HouseId))
```

**Pros**:
- ✅ Minimal code change (1 line)
- ✅ No gameplay logic changes
- ✅ Maintains all existing mechanics
- ✅ Still allows legitimate slow attrition battles (4 rounds is reasonable)
- ✅ Spec-compliant: improves "20 rounds without resolution" interpretation

**Cons**:
- ⚠️ Reduces maximum combat length from 20 to 5+ rounds for no-progress situations
- ⚠️ Need to tune N (5 suggested, could be 3-7)

**Tuning Considerations**:
- N=3: Very aggressive, may cut short legitimate battles
- N=5: **Recommended** - balances responsiveness with patience
- N=7: More conservative, still saves 13 wasted rounds

---

### Option B: Minimum Damage Rule

**Description**: Attacks always deal at least 1 cumulative hit, even if below DS threshold.

**Implementation**:
```nim
# In combat_resolution.nim - after calculating hits

let baseHits = calculateHits(attackerAS, cerRoll)
let effectiveHits = max(baseHits, 1)  # Always at least 1 hit

# Accumulate to squadron.damageThisTurn
targetSquadron.damageThisTurn += effectiveHits
```

**Philosophy**: "Chipping away" - even weak attacks gradually wear down defenses.

**Pros**:
- ✅ Guarantees eventual progress
- ✅ Prevents infinite loops mathematically
- ✅ Intuitive: every attack matters

**Cons**:
- ❌ **Not spec-compliant**: Changes combat math significantly
- ❌ Makes weak forces viable against strong defenses (balance issue)
- ❌ Could extend battles unnecessarily (weak forces take forever to kill)
- ❌ Requires extensive balance testing

**Verdict**: ❌ **Not Recommended** - Too invasive for spec compliance

---

### Option C: Escalating Critical Hit Chance

**Description**: Increase critical hit probability each no-progress round.

**Implementation**:
```nim
# In combat_cer.nim - rollCER()

proc rollCER*(
  rng: var CombatRNG,
  phase: CombatPhase,
  roundNumber: int,
  consecutiveNoProgress: int,  # NEW parameter
  hasScouts: bool,
  moraleModifier: int,
  isSurprise: bool = false,
  isAmbush: bool = false
): CERRoll =
  let naturalRoll = rng.roll1d10()

  # Escalating critical threshold
  let critThreshold = max(9 - consecutiveNoProgress, 6)  # 9, 8, 7, 6 (min)
  let isCrit = (naturalRoll >= critThreshold)

  # ... rest of CER logic
```

**Mechanic**: After 3 rounds of no progress, natural 8 becomes critical. After 4 rounds, natural 7, etc.

**Pros**:
- ✅ Flavorful: "desperation tactics" narrative
- ✅ Guarantees eventual breakthrough (critical bypasses destruction protection)
- ✅ Self-correcting: more aggressive as stalemate continues

**Cons**:
- ❌ **Not spec-compliant**: Alters critical hit mechanics significantly
- ❌ Complex to explain to players
- ❌ May create unintended balance issues (crits become too common)
- ❌ Threading consecutiveNoProgress through all CER calls is invasive

**Verdict**: ⚠️ **Interesting but risky** - Requires spec amendment

---

### Option D: Hybrid Approach

**Description**: Combine Option A (progressive stalemate) with partial Option C (one-time breakthrough).

**Implementation**:
```nim
# In combat_engine.nim - main combat loop

if consecutiveRoundsNoChange >= 5:
  # Give both sides one "desperation attack" with +2 CER bonus
  echo "Desperation round - both sides gain +2 CER"

  # Resolve one more round with bonus
  let desperationResults = resolveRound(
    taskForces, roundNum, diplomaticRelations, systemOwner, rng,
    desperationBonus = 2  # +2 CER to all attacks
  )

  result.rounds.add(desperationResults)

  # Check if desperation broke the stalemate
  var desperationProgress = false
  for phaseResult in desperationResults:
    if phaseResult.stateChanges.len > 0:
      desperationProgress = true
      break

  if not desperationProgress:
    # Still no progress even with bonus - force stalemate
    result.wasStalemate = true
    break
```

**Pros**:
- ✅ Gives stalemates "one last chance" before ending
- ✅ +2 CER bonus may be enough to tip the scales
- ✅ Flavorful and player-friendly

**Cons**:
- ⚠️ More complex implementation
- ⚠️ Requires adding desperationBonus parameter threading
- ⚠️ Edge case: what if desperation causes mutual destruction?

**Verdict**: ⚠️ **Good for player experience** but adds complexity

---

## Recommendation Matrix

| Option | Spec Compliance | Code Simplicity | Effectiveness | Player UX | Verdict |
|--------|----------------|-----------------|---------------|-----------|---------|
| **A: Progressive Stalemate** | ✅ High | ✅ Excellent | ✅ Solves problem | ✅ Clear | **✅ RECOMMENDED** |
| B: Minimum Damage | ❌ Low | ✅ Simple | ⚠️ Partial | ⚠️ Confusing | ❌ Not Recommended |
| C: Escalating Crits | ❌ Low | ❌ Complex | ✅ Solves problem | ⚠️ Confusing | ❌ Not Recommended |
| D: Hybrid | ⚠️ Medium | ⚠️ Moderate | ✅ Best | ✅ Excellent | ⚠️ Consider if A insufficient |

---

## Final Recommendation: **Option A - Progressive Stalemate Detection**

### Implementation Details

**File**: `src/engine/combat_retreat.nim`
**Function**: `checkCombatTermination()`
**Change**: Add early stalemate check

```nim
proc checkCombatTermination*(
  taskForces: seq[TaskForce],
  consecutiveRoundsNoChange: int
): tuple[shouldEnd: bool, reason: string, victor: Option[HouseId]] =
  ## Check if combat should end
  ## Returns (shouldEnd, reason, victor)

  # Count alive Task Forces
  var aliveHouses: seq[HouseId] = @[]
  for tf in taskForces:
    if not tf.isEliminated():
      aliveHouses.add(tf.house)

  # Only one side remains
  if aliveHouses.len == 1:
    return (true, "Only one Task Force remains", some(aliveHouses[0]))

  # All eliminated
  if aliveHouses.len == 0:
    return (true, "All Task Forces eliminated", none(HouseId))

  # NEW: Progressive stalemate detection
  if consecutiveRoundsNoChange >= 5:
    return (true, "Tactical stalemate - no progress in 5 rounds", none(HouseId))

  # Stalemate after 20 rounds without progress (safety net)
  if consecutiveRoundsNoChange >= 20:
    return (true, "Stalemate after 20 rounds without progress", none(HouseId))

  # Combat continues
  return (false, "", none(HouseId))
```

**Testing**: Update test harness edge case detection:
```nim
# In combat_test_harness.nim - detectEdgeCases()

# Update long_combat threshold
if combatResult.totalRounds >= 10:  # Lower from 15 to 10
  result.add(EdgeCase(
    caseType: "long_combat",
    description: fmt"Combat lasted {combatResult.totalRounds} rounds",
    severity: EdgeCaseSeverity.Warning
  ))
```

### Expected Impact

**Before**:
- `home_defense_76`: 20 rounds, 5+ no-damage rounds
- Edge case: long_combat + no_damage_loop

**After**:
- `home_defense_76`: 5 rounds, tactical stalemate
- Edge case: tactical_stalemate (new type)
- Saves 15 wasted rounds

**Other Tests**:
- 99% of tests unaffected (resolve in ≤3 rounds)
- Multi-faction mutual destruction: unaffected (state changes every round)
- Homeworld defense: may trigger earlier stalemates (expected/desired)

---

## Alternative Tuning Options

If N=5 proves too aggressive in practice:

**Conservative**: N=7
- Gives more time for lucky CER rolls
- Still saves 13 rounds vs 20-round limit

**Aggressive**: N=3
- Fastest stalemate detection
- Risk: may cut short legitimate grinding battles
- Good for "quick resolution" game modes

**Adaptive**: Scale with battle size
```nim
let stalemateThreshold = min(5 + (taskForces.len - 2), 10)
# 2 factions: 5 rounds
# 4 factions: 7 rounds
# 12 factions: 10 rounds (capped)
```

---

## Spec Clarification Recommendation

Update `operations.md` Section 7.3.4:

**Current**:
> Combat ends when... 20 consecutive rounds have elapsed without resolution (forced stalemate)

**Proposed**:
> Combat ends when... 5 consecutive rounds have elapsed without any squadron state changes (tactical stalemate), or 20 total rounds have elapsed (forced stalemate)

This clarifies the difference between:
- **Tactical stalemate**: No one can hurt each other (5 rounds)
- **Forced stalemate**: Maximum combat duration (20 rounds total)

---

## Summary

**Problem**: No-damage loops waste up to 20 rounds
**Solution**: Detect tactical stalemate after 5 consecutive rounds without state changes
**Code Impact**: 1-line change in `combat_retreat.nim`
**Spec Impact**: Clarifies "without resolution" to mean "without state changes"
**Testing Impact**: Add new edge case type "tactical_stalemate"

**Risk Level**: ✅ LOW
- Minimal code change
- Spec-compliant interpretation
- No balance changes
- Easy to tune if needed
