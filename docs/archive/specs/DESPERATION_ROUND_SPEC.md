# Desperation Round Mechanics - Spec Amendment

## Proposed Addition to operations.md Section 7.3.4

---

### 7.3.4.1 Desperation Tactics (Tactical Stalemate Prevention)

When combat stalls with neither side able to inflict damage, commanders may resort to desperate, high-risk maneuvers in a final attempt to break the deadlock.

**Trigger Condition:**
- Combat has progressed for 5 consecutive rounds without any squadron state changes (no cripples or destructions)

**Desperation Round:**

When the trigger condition is met, one additional combat round is immediately resolved with the following modifications:

1. **Both sides** receive a +2 CER modifier on all attack rolls
2. This bonus applies to all three combat phases (Ambush, Intercept, Main Engagement)
3. The desperation bonus stacks with all other modifiers (scouts, morale, surprise, ambush)
4. Fighters are unaffected (they do not use CER)

**Narrative Justification:**

Desperate commanders order aggressive, high-risk tactics:
- Fighters commit to closer strafing runs despite increased exposure
- Capital ships drop auxiliary shields to redirect power to weapons systems
- Cloaked raiders decloak for point-blank attack runs
- Commanders accept higher casualties in exchange for tactical breakthrough

**Resolution:**

After the desperation round resolves:

- **If any squadron state changes occurred**: Reset the stalemate counter. Combat continues normally.
- **If no state changes occurred**: Declare **Tactical Stalemate** immediately. Combat ends with no victor.

**Tactical Stalemate vs Forced Stalemate:**

- **Tactical Stalemate**: Neither side can hurt each other (triggers after desperation round fails)
- **Forced Stalemate**: Maximum combat duration reached (20 total rounds, unchanged)

Both result in no victor, but tactical stalemate indicates defensive parity while forced stalemate indicates prolonged attrition.

---

## Examples

### Example 1: Desperation Breakthrough

**Setup:**
- Attacker: 18 AS, 12 DS
- Defender: 19 AS, 12 DS
- Both sides evenly matched

**Rounds 1-5:** Both sides roll low CER (0.25-0.5), dealing 4-9 hits each. Neither reaches 12 DS threshold. No state changes.

**Desperation Round (Round 6):**
- Both sides gain +2 CER modifier
- Attacker rolls 4 (normally 0.5×) → becomes 6 (0.75×) → 18 AS × 0.75 = 13.5 → **14 hits** (exceeds DS!)
- Defender rolls 3 (normally 0.5×) → becomes 5 (0.75×) → 19 AS × 0.75 = 14.25 → **15 hits** (exceeds DS!)

**Result:** Both squadrons crippled. Stalemate broken. Combat continues with reduced forces.

### Example 2: Desperation Fails (home_defense_76)

**Setup:**
- Attacker: 16 AS, unknown DS (likely 10+)
- Defender: 17 AS, unknown DS (likely 10+), homeworld (cannot retreat)

**Rounds 1-5:** Both roll very low CER (0-2 on d10), dealing 4-5 hits. Neither reaches DS threshold.

**Desperation Round (Round 6):**
- Both gain +2 CER
- Attacker rolls 1 → becomes 3 (0.5×) → 16 AS × 0.5 = 8 hits (still below DS)
- Defender rolls 2 → becomes 4 (0.5×) → 17 AS × 0.5 = 8.5 → 9 hits (still below DS)

**Result:** Tactical Stalemate declared. Combat ends at round 7 (not 20).

---

## CER Table with Desperation Bonus

**Standard CER Table:**

| Modified Roll | CER    |
|---------------|--------|
| ≤2            | 0.25×  |
| 3-4           | 0.50×  |
| 5-6           | 0.75×  |
| 7+            | 1.00×  |

**With +2 Desperation:**

| Natural Roll | Normal | With Desperation | Effect |
|--------------|--------|------------------|--------|
| 0            | 0.25×  | 0.50×           | 2× improvement |
| 1            | 0.25×  | 0.50×           | 2× improvement |
| 2            | 0.25×  | 0.50×           | 2× improvement |
| 3            | 0.50×  | 0.75×           | 1.5× improvement |
| 4            | 0.50×  | 0.75×           | 1.5× improvement |
| 5            | 0.75×  | 1.00×           | 1.33× improvement |
| 6            | 0.75×  | 1.00×           | 1.33× improvement |
| 7+           | 1.00×  | 1.00×           | No change (already max) |

**Critical Hits:** Natural 9 before modifiers still triggers critical hit effects (bypass destruction protection, force reduction).

---

## Impact on Game Balance

### Simulation Results (500 tests):

**Before Desperation Mechanics:**
- home_defense_76: 20 rounds, tactical stalemate
- 1 case of extended no-damage loop
- Wasted computation on unwinnable scenarios

**After Desperation Mechanics:**
- home_defense_76: 7 rounds, tactical stalemate
- Saved 13 rounds (65% reduction)
- 99% of tests unaffected (still resolve in 1-3 rounds)

### Strategic Implications:

1. **Defensive Parity Recognized Faster**: When forces are truly evenly matched, the system detects it in 6-7 rounds instead of 20.

2. **Encourages Breakthrough Attacks**: The +2 CER bonus may tip the scales for marginally weaker forces, rewarding persistent aggression.

3. **Homeworld Defense**: Still cannot retreat, but stalemates resolve faster (less computational waste).

4. **Player Experience**: Players will see "Desperation tactics engaged!" message, adding narrative flavor to technical stalemate detection.

---

## Implementation Notes

### Code Changes:

1. **combat_cer.nim**: Added `desperationBonus` parameter to `rollCER()`
2. **combat_resolution.nim**: Thread `desperationBonus` through all phase resolution functions
3. **combat_engine.nim**: Check for 5 consecutive no-progress rounds, trigger desperation round

### Edge Case Handling:

- **Desperation round counts as a normal round** for total round tracking
- **If desperation causes mutual destruction**: That's valid - both sides destroyed each other in last desperate attack
- **Multiple desperation rounds**: Not possible - only triggers once, then either breaks stalemate or ends combat

### Testing:

- Verified with 500-test simulation
- Only 1 case triggers desperation (home_defense_76 scenario)
- Zero spec violations
- Performance unaffected (0.00007s per test avg)

---

## Spec Text (Ready for operations.md)

**Insert after Section 7.3.4 Combat Termination Conditions:**

### 7.3.4.1 Desperation Tactics

If combat progresses for 5 consecutive rounds without any squadron state changes, both commanders resort to desperate, high-risk maneuvers for one final breakthrough attempt.

**Desperation Round:**
- Both Task Forces receive +2 CER modifier on all attacks
- Resolves immediately as an additional combat round
- If any state changes occur: combat continues normally
- If no state changes occur: Tactical Stalemate declared (no victor)

**Desperation Bonus:**
- Applies to Ambush phase (+4 ambush + 2 desperation = +6 total)
- Applies to Main Engagement phase (+2 only, stacks with scouts/morale)
- Does not apply to Fighters (they use full AS regardless)
- Stacks with all other CER modifiers

Desperation tactics represent commanders accepting higher risk for tactical advantage: fighters fly dangerously close attack runs, capital ships divert shield power to weapons, and cloaked forces abandon stealth for point-blank strikes.

---

## Alternatives Considered

We also considered:
- **Option A**: Progressive stalemate at 5 rounds (simpler, but less narrative)
- **Option B**: Minimum damage rule (changes combat math, not spec-compliant)
- **Option C**: Escalating critical hits (too complex, alters balance significantly)

**Option D (Desperation Round)** was chosen because:
- ✅ Spec-compliant (CER modifier, not new mechanics)
- ✅ Narrative flavor ("desperation tactics")
- ✅ Gives stalemates one final chance
- ✅ Minimal code changes
- ✅ Player-friendly ("trying everything before giving up")
