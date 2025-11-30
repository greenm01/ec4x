# Combat Activity Analysis - CRITICAL ISSUE FOUND

**Game**: 4-player, 40 turns, seed 12345
**Date**: 2025-11-30

## CRITICAL FINDING: ZERO COMBAT OCCURRING

### The Problem

In a 40-turn game across Acts 1-4 (including Act 2: Rising Tensions, Act 3: Total War, Act 4: Endgame), **ZERO planets changed hands through combat**.

### Evidence

**Colony Changes (Entire Game)**:
- All houses: **ONLY GAINED** colonies, never lost any
- Corrino: 2 → 7 (+5, -0)
- Atreides: 2 → 5 (+3, -0)
- Harkonnen: 2 → 9 (+7, -0)
- Ordos: 2 → 7 (+5, -0)

**Timeline**:
- Turns 2-12: Rapid expansion (8 → 28 total colonies)
- Turns 13-41: **COMPLETE STAGNATION** (28 colonies, zero change for 29 turns!)

**Military Forces at Turn 41**:
- Corrino: 4 ships, 4 squadrons
- Atreides: 10 ships, 10 squadrons
- Harkonnen: 3 ships, 3 squadrons (winner with only 3 ships!)
- Ordos: 16 ships, 16 squadrons
- **NO STARBASES** - Zero defensive structures built by anyone

### What Should Be Happening

Based on Act descriptions:

**Act 2: Rising Tensions (turns 8-15)**
- Should have: Border skirmishes, contested systems
- Actually had: Zero combat, 28 → 28 colonies

**Act 3: Total War (turns 16-25)**
- Should have: Major invasions, planets changing hands frequently
- Actually had: Zero combat, 28 → 28 colonies (frozen)

**Act 4: Endgame (turns 26+)**
- Should have: Desperate final pushes, territorial collapse
- Actually had: Zero combat, 28 → 28 colonies (still frozen)

### Root Causes (Hypotheses)

1. **AI Never Declares War**
   - All houses may still be at peace
   - No war = no invasions allowed

2. **AI Doesn't Build Invasion Forces**
   - Only 3-16 ships total per house
   - No ground armies visible in metrics
   - Insufficient military to attempt invasions

3. **AI Doesn't Attack**
   - Ships exist but never engage
   - Standing orders may be purely defensive
   - No offensive fleet operations

4. **Map Is Fully Claimed**
   - 28/37 systems colonized by turn 12
   - 9 systems left unclaimed forever
   - No contested territory (everyone has their space)

5. **Defensive Advantage Too Strong**
   - Maybe invasions are attempted but always fail
   - Ground defenses might be impenetrable

### Expected vs Actual

| Metric | Expected (40 turns) | Actual | Gap |
|--------|---------------------|--------|-----|
| Planets conquered | 10-20+ | 0 | -100% |
| Planets lost | 10-20+ | 0 | -100% |
| Territory changes | Frequent | None | -100% |
| Military buildup | Large fleets | 3-16 ships | -95% |
| Starbases built | Most colonies | 0 | -100% |
| Combat engagements | Dozens | Unknown (0?) | -100% |

### Prestige Impact

Remember those tiny prestige losses (-21 to -25)?

**Prestige penalties that SHOULD be firing**:
- Lose planet: -100 prestige (never fired)
- Lose starbase: -50 prestige (never fired, no starbases exist)
- Invade planet: +100 prestige (never earned by anyone)
- System capture: +100 prestige (never earned)
- Fleet victory: +30 prestige (questionable if any occurred)

**This explains why prestige only accumulates**:
- The big penalties (-100) never trigger
- Only small penalties fire (tax: -2, espionage fail: -20)
- No one is fighting!

### Game Pacing

**Expansion Phase** (Turns 2-12):
- Duration: 10 turns
- Activity: Rapid colonization (8 → 28 colonies)
- Status: Working correctly

**Static Phase** (Turns 13-41):
- Duration: 29 turns (73% of game!)
- Activity: **NOTHING** (28 colonies frozen)
- Status: **BROKEN** - No combat, no territory changes, no conflict

### Why Harkonnen "Won"

Harkonnen won because they colonized 9 systems in the first 12 turns, vs 5-7 for others.

**The game was decided by turn 12** - the remaining 29 turns were just waiting for prestige to accumulate from existing colonies.

---

## Required Fixes

### Critical (Game-Breaking)

1. **AI Must Declare War**
   - Investigate: Are houses at war? Check diplomatic status
   - Fix: Ensure Act 2+ triggers war declarations

2. **AI Must Build Invasion Forces**
   - Current: 3-16 total ships (pathetic for turn 41)
   - Target: 50-100+ ships by turn 40
   - Fix: Increase military production priorities in Act 2+

3. **AI Must Attack Enemy Colonies**
   - Investigate: Do offensive fleet orders exist?
   - Fix: Domestikos must generate invasion orders

4. **AI Must Build Starbases**
   - Current: 0 starbases across all houses
   - Target: 1-2 starbases per house minimum
   - Fix: Defense requirements must include starbases

### High Priority

5. **Act Transitions Must Shift Priorities**
   - Act 1: Expansion (working)
   - Act 2: Build military + declare war (not working)
   - Act 3: Aggressive invasions (not working)
   - Act 4: Desperation moves (not working)

6. **Resource Allocation for War**
   - Current: 90%+ economy, <10% military
   - Target: Act 2: 40% military, Act 3: 60% military

7. **Invasion Mechanics**
   - Investigate: Are invasions possible? What's required?
   - Test: Can AI successfully invade with proper forces?

---

## Diagnostic Commands

To investigate root causes:

```bash
# Check diplomatic status
grep -i "war\|peace\|diplomacy" balance_results/diagnostics/game_12345.csv

# Check if any invasions were attempted
grep -i "invasion\|invade" balance_results/diagnostics/game_12345.csv

# Check military production over time
# (compare turn 10 vs turn 40 ship counts)
```

---

## Comparison to Expected Gameplay

### What a 40-Turn Game Should Look Like

**Act 1 (Turns 1-7): Land Grab** ✓ WORKING
- Rapid expansion
- Peaceful colonization
- 8 → 19 colonies

**Act 2 (Turns 8-15): Rising Tensions** ✗ BROKEN
- Border conflicts
- First invasions
- Expected: 3-5 planets change hands
- Actual: 0 planets changed hands

**Act 3 (Turns 16-25): Total War** ✗ BROKEN
- Major campaigns
- Territorial gains/losses
- Expected: 10-15 planets change hands
- Actual: 0 planets changed hands

**Act 4 (Turns 26-40): Endgame** ✗ BROKEN
- Winner consolidates
- Losers collapse
- Expected: 5-10 final conquests
- Actual: 0 planets changed hands

### What Actually Happened

- **73% of the game** (turns 13-41) had ZERO territorial changes
- Winner was determined entirely by expansion (turns 2-12)
- Acts 2-4 are cosmetic labels with no gameplay difference
- "Total War" act had zero warfare

---

## Conclusion

**The combat system is completely non-functional in AI vs AI games.**

The game has two phases:
1. **Expansion** (10 turns): Working correctly
2. **Static accumulation** (30 turns): Completely broken

No invasions, no warfare, no territory changes, no starbases, minimal military. The game plays out as a pure expansion race where the first 10 turns determine the winner, and the next 30 turns are spent watching prestige accumulate from existing colonies.

This is the **#1 critical issue** for game balance - the warfare mechanics are not being triggered by the AI at all.
