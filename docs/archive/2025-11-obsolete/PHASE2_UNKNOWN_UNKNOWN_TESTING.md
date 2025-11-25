# Phase 2 Unknown-Unknown Testing Plan

**Date:** 2025-11-24
**Purpose:** Systematic testing to discover hidden issues before Phase 3
**Status:** 🔄 In Progress

---

## Testing Philosophy

Before generating 10,000+ training examples in Phase 3, we must ensure Phase 2 AI is robust. Unknown-unknowns are issues we don't know exist yet. This testing aims to find:

1. **Rare edge cases** that only appear in specific game states
2. **Performance bottlenecks** under stress
3. **Logic errors** that cause crashes or hangs
4. **Unexpected AI behaviors** that seem broken
5. **Data inconsistencies** in diagnostics

---

## Test Categories

### 1. Stress Testing (Scale & Reliability)

**Goal:** Find crashes, deadlocks, memory leaks

- [ ] **20-game batch** (30 turns, 4 players) - Quick smoke test
- [ ] **100-game batch** (30 turns, 4 players) - Extended reliability
- [ ] **Long games** (10 games, 100 turns, 4 players) - Late-game issues
- [ ] **High player count** (10 games, 30 turns, 8-12 players) - Scalability
- [ ] **Small maps** (10 games, 30 turns, 2-4 players) - Edge case: limited space
- [ ] **Large maps** (10 games, 30 turns, 6-8 players) - Edge case: sparse systems

**Success Criteria:**
- Zero crashes
- No infinite loops or hangs (all games complete)
- Reasonable execution time (< 10s per game for 30 turns)

---

### 2. AI Strategy Matrix Testing

**Goal:** Ensure all personality combinations work

Test all 4 strategies against each other:
- Aggressive (aggression 0.8, expansion 0.7, tech 0.3, caution 0.2)
- Economic (aggression 0.2, expansion 0.5, tech 0.6, caution 0.7)
- Balanced (aggression 0.5, expansion 0.5, tech 0.5, caution 0.5)
- Turtle (aggression 0.1, expansion 0.3, tech 0.7, caution 0.9)

**Matrix:** 4 strategies × 4 opponents = 16 combinations

- [ ] Aggressive vs Aggressive (5 games)
- [ ] Aggressive vs Economic (5 games)
- [ ] Aggressive vs Balanced (5 games)
- [ ] Aggressive vs Turtle (5 games)
- [ ] Economic vs Economic (5 games)
- [ ] Economic vs Balanced (5 games)
- [ ] Economic vs Turtle (5 games)
- [ ] Balanced vs Balanced (5 games)
- [ ] Balanced vs Turtle (5 games)
- [ ] Turtle vs Turtle (5 games)

**Success Criteria:**
- All combinations complete without errors
- No strategy dominates 100% (indicates broken balance)
- AI behaviors match strategy profiles

---

### 3. Fog-of-War Violation Testing

**Goal:** Ensure AI never cheats (accesses omniscient data)

- [ ] **Manual inspection** of ai_controller.nim for any `GameState` usage
- [ ] **Runtime checks** - Add assertions that AI only uses FilteredGameState
- [ ] **Intel tracking** - Verify AI only acts on visible/known information

**Test Scenarios:**
- [ ] AI attacks colony it has never seen (should not happen)
- [ ] AI moves fleet to system it has no intel on (should not happen)
- [ ] AI targets specific enemy assets without scouting (should not happen)

**Success Criteria:**
- Zero fog-of-war violations detected
- All AI decisions use only FilteredGameState data

---

### 4. Diagnostic Data Quality Testing

**Goal:** Validate diagnostic metrics are accurate

**Metrics to Validate:**
- [ ] `capacity_violations` - Should be 0 (auto-loading works)
- [ ] `fighters_disbanded` - Should be 0 or very low
- [ ] `idle_carriers` - Should be 0 or very low
- [ ] `total_espionage` - Should be > 0 in 100% of games
- [ ] `spy_planet` + `hack_starbase` = `total_espionage`
- [ ] `invasions_no_eli` - Should be 0 or very low (scouts attached)
- [ ] `undefended_colonies` / `total_colonies` - Should be < 50%
- [ ] `mothball_used` / `mothball_total` - Reserve fleet usage
- [ ] `invalid_orders` - Should be 0

**Success Criteria:**
- All metrics within expected ranges
- No NaN or null values
- Metrics add up correctly

---

### 5. Game State Consistency Testing

**Goal:** Ensure game state never becomes corrupted

**Checks:**
- [ ] Fleet location matches squadron locations
- [ ] Fighter ownership (colony vs carrier) is consistent
- [ ] Colony production values are reasonable (not negative, not absurdly high)
- [ ] Squadron CR/CC values match ship stats
- [ ] Prestige scores are monotonically increasing (or stay same, never decrease without reason)
- [ ] Treasury never goes negative (or if it does, handled gracefully)

**Success Criteria:**
- No state inconsistencies detected
- All invariants maintained throughout game

---

### 6. AI Decision Quality Testing

**Goal:** Ensure AI makes sensible decisions

**Manual Review of 5-10 Games:**
- [ ] Colonization timing (early game priority)
- [ ] Military buildup (proportional to strategy)
- [ ] Research allocation (matches tech priority)
- [ ] Espionage usage (HackStarbase vs SpyPlanet balance)
- [ ] Fleet positioning (defends important colonies)
- [ ] Retreat behavior (uses fallback routes correctly)
- [ ] Invasion targeting (attacks vulnerable enemies)

**Red Flags:**
- AI builds nothing for multiple turns
- AI sends empty fleets
- AI never researches key techs (EL, SL, WEP)
- AI abandons homeworld
- AI violates own diplomatic pacts immediately

**Success Criteria:**
- AI behaviors seem rational
- No obviously broken decisions

---

### 7. Performance Profiling

**Goal:** Identify bottlenecks before Phase 3

- [ ] **Time per turn** - Should be < 1 second for 4-player game
- [ ] **Memory usage** - Should be stable (no leaks)
- [ ] **CPU usage** - Should be efficient (no spinning)

**Tools:**
- Use `time` command for execution time
- Use `valgrind` or similar for memory profiling (optional)
- Profile `generateAIOrders()` function

**Success Criteria:**
- 30-turn game completes in < 30 seconds (1s per turn)
- Memory usage < 100MB per game
- No obvious performance issues

---

### 8. Edge Case Scenarios

**Goal:** Test unusual but valid game states

- [ ] **One house eliminated early** (turn 5) - Others continue
- [ ] **Stalemate** - No combat for 20+ turns
- [ ] **Resource scarcity** - All players bankrupt
- [ ] **Tech gap** - One player has EL5, others at EL1
- [ ] **Diplomatic web** - All houses have non-aggression pacts
- [ ] **Empty map** - Most systems uncolonized
- [ ] **Crowded map** - All systems colonized

**Success Criteria:**
- Game handles all edge cases gracefully
- No crashes or undefined behavior

---

## Testing Workflow

### Phase 1: Quick Smoke Test (30 minutes)
1. Run 20-game diagnostic batch (30 turns, 4 players)
2. Check for crashes
3. Validate diagnostic CSV format
4. Quick scan for obvious issues

### Phase 2: Extended Reliability (2 hours)
5. Run 100-game diagnostic batch (30 turns, 4 players)
6. Analyze for rare crashes
7. Check success rate (should be 100%)
8. Generate summary statistics

### Phase 3: Deep Analysis (4 hours)
9. Run strategy matrix tests (80 games total)
10. Manual review of 10 random games
11. Fog-of-war violation checks
12. Data quality validation
13. Performance profiling

### Phase 4: Edge Case Testing (2 hours)
14. Create custom test scenarios
15. Run edge case games
16. Document any issues found

---

## Success Criteria for Phase 2 Sign-Off

**Before proceeding to Phase 3, we must achieve:**

✅ **Zero crashes** in 100+ game batch
✅ **Zero fog-of-war violations** detected
✅ **All diagnostic metrics** within expected ranges
✅ **All AI strategies** functional
✅ **Performance** acceptable (< 1s per turn average)
✅ **No critical bugs** identified

**If any criteria fail:**
- Document the issue
- Fix if critical
- Re-run tests
- Do not proceed to Phase 3 until resolved

---

## Issue Tracking

### Critical Issues (Block Phase 3)
- None identified yet

### Major Issues (Should fix before Phase 3)
- TBD

### Minor Issues (Can defer to later)
- TBD

---

## Test Execution Log

### Run 1: Initial Smoke Test (2025-11-24)
- **Command:** `python3 run_parallel_diagnostics.py 20 30 8`
- **Status:** 🔄 Running
- **Results:** Pending

---

**Last Updated:** 2025-11-24
**Next Update:** After smoke test completes
