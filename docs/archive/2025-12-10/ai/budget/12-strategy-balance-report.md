# 12-Strategy Balance Analysis Report

**Date:** 2025-11-30
**Games Analyzed:** 292 games (12 players each, 15 turns per game)
**Total Samples:** 3,504 house measurements
**Test Scope:** Baseline (untuned) AI personalities

## Executive Summary

This report analyzes unit cost effectiveness, tech tree scaling, and strategic balance across 292 twelve-player games. The test revealed significant balance issues with **Balanced and Aggressive strategies severely underperforming** due to tech progression disadvantages. The **fighter budget fix is working correctly**, with science-focused strategies (Economic, Turtle) successfully building fighters while military-focused strategies lag behind in CST research.

**Critical Finding:** The current 4-strategy rotation (Economic, Balanced, Turtle, Aggressive) shows that science/economy strategies dominate due to superior tech progression, not military superiority. The other 8 AI personalities were not tested in this run.

---

## 1. Test Methodology

### Configuration
- **Game Length:** 15 turns (Act2_RisingTensions phase)
- **Players per Game:** 12 houses
- **Map Scale:** 12 rings (~469 systems)
- **Strategy Rotation:** Only 4 strategies tested (Economic, Balanced, Turtle, Aggressive)
  - Economic: 876 samples (3 houses per game)
  - Balanced: 876 samples (3 houses per game)
  - Turtle: 876 samples (3 houses per game)
  - Aggressive: 876 samples (3 houses per game)

### Strategies Not Tested
The following 8 personalities were **not included** in this test run:
- Diplomatic
- Espionage
- Expansionist
- Isolationist
- MilitaryIndustrial
- Opportunistic
- Raider
- TechRush

These strategies remain untuned and untested.

### Anti-Cheese Features
Per reference.md, the game includes anti-spam/anti-cheese mechanisms:
- Fighter squadron limits (based on tech level)
- Starbase requirements (1 per 3 colonies minimum)
- Capacity violation penalties
- Tech theft diminishing returns
- Budget constraints and strategic triage

---

## 2. Strategy Performance

### Win Rate Rankings
| Strategy | Games | Win Rate | Avg Prestige | Std Dev |
|----------|-------|----------|--------------|---------|
| **Turtle** | 876 | **16.7%** | 1,731.6 | ±127 |
| **Economic** | 876 | **16.1%** | 1,724.7 | ±145 |
| **Aggressive** | 876 | **0.6%** | 1,501.6 | ±200 |
| **Balanced** | 876 | **0.0%** | 1,495.2 | ±200 |

### Key Observations

**Turtle and Economic dominate** with near-equal performance (~16% win rate each). This is a **balanced outcome** between these two strategies in the 12-player environment.

**Balanced strategy has 0.0% win rate** across 876 samples - this is a critical balance failure. Despite the name "Balanced", this strategy cannot compete.

**Aggressive strategy barely registers** at 0.6% win rate (5 wins out of 876 games). This strategy is fundamentally non-competitive.

**High variance in losing strategies** (±200 prestige) suggests inconsistent performance and frequent early eliminations.

---

## 3. Military Composition Analysis

### Unit Building Patterns by Strategy

| Strategy | Fighters | Capitals | Escorts | Scouts | Total Fleet |
|----------|----------|----------|---------|--------|-------------|
| **Economic** | 2.6 | 0.9 | 9.8 | 0.8 | 14.1 |
| **Turtle** | 2.4 | 0.9 | 9.6 | 0.8 | 13.7 |
| **Balanced** | 0.6 | 0.9 | 10.5 | 2.0 | 14.0 |
| **Aggressive** | 0.5 | 0.8 | 10.7 | 2.0 | 13.9 |

### Fighter Adoption Analysis

**Fighter Budget Fix Validated:** Economic and Turtle strategies successfully build fighters (2.6 and 2.4 avg) after moving fighters from SpecialUnits to Military budget.

**Tech Gating Working:** Aggressive and Balanced strategies show minimal fighter adoption (0.5-0.6 avg) because they **don't reach CST3** by Turn 15 due to prioritizing weapons/military tech over construction tech.

**Strategic Divergence:**
- **Science-focused strategies** (Economic, Turtle): Invest in CST research → unlock fighters → gain cost-efficient defense
- **Military-focused strategies** (Aggressive, Balanced): Invest in WPN research → miss fighter unlock → forced into expensive escort ships

This creates a **tech advantage snowball effect** where science strategies get better value per PP spent.

### Scout Usage Patterns

**Economic/Turtle:** 0.8 scouts (minimal investment in intel gathering)
**Aggressive/Balanced:** 2.0 scouts (2.5x more scouts, but at what cost?)

**Analysis:** Aggressive/Balanced strategies over-invest in scouts (50PP each) for intelligence gathering, but this doesn't translate to wins. Winner analysis shows that **winners build 64% fewer scouts than losers** - excessive scouting is a losing pattern.

---

## 4. Unit Cost Effectiveness

### PP per Power Point Efficiency Rankings

| Unit | Cost (PP) | Power | PP/Pwr | Efficiency |
|------|-----------|-------|--------|------------|
| **Fighter** | 20 | 7 | **2.86** | ⭐ BEST |
| **Battlecruiser** | 100 | 34 | **2.94** | ⭐ BEST |
| **Starbase** | 300 | 95 | **3.16** | ✓ Good |
| **Heavy Cruiser** | 80 | 25 | **3.20** | ✓ Good |
| **Light Cruiser** | 60 | 17 | **3.53** | ✓ Good |
| **Dreadnought** | 200 | 58 | **3.45** | ✓ Good |
| **Carrier** | 80 | 23 | **3.48** | ✓ Good |
| **Battleship** | 150 | 45 | **3.33** | ✓ Good |

### Winner vs Loser Unit Composition

| Unit | Winners Avg | Losers Avg | Difference | Advantage |
|------|-------------|------------|------------|-----------|
| **Carrier** | 1.9 | 1.3 | +0.6 | **+43%** ✓ |
| **Fighter** | 1.8 | 1.4 | +0.4 | +28% ✓ |
| **Light Cruiser** | 2.8 | 2.4 | +0.4 | +17% ✓ |
| **Battlecruiser** | 0.6 | 0.5 | +0.1 | +20% ✓ |
| **Heavy Cruiser** | 2.7 | 5.0 | **-2.3** | **-46%** ✗ |
| **Scout** | 0.8 | 2.1 | **-1.3** | **-64%** ✗ |
| **Starbase** | 0.8 | 0.8 | 0.0 | +0% = |

### Key Unit Insights

**Carriers are winner assets (+43%)** - Winners invest significantly more in carrier capability despite carriers having moderate efficiency (3.48 PP/pwr). This suggests **strategic mobility and fighter projection** are high-value capabilities.

**Heavy Cruisers are loser traps (-46%)** - Losing strategies massively over-invest in Heavy Cruisers (5.0 avg vs 2.7 for winners). Despite decent efficiency (3.20 PP/pwr), Heavy Cruisers don't translate to wins.

**Scouts are losing investments (-64%)** - Excessive scout production correlates strongly with losing. Intelligence gathering has diminishing returns.

**Most Common Units in Winning Armies:**
1. Destroyer (7.0 units, 279 PP invested)
2. ETAC (10.1 units, 254 PP invested)
3. Troop Transport (8.2 units, 206 PP invested)
4. Heavy Cruiser (2.7 units, 216 PP invested)
5. Light Cruiser (2.8 units, 169 PP invested)

Destroyers and ETACs dominate winning strategies - these provide solid defensive value and economic growth respectively.

---

## 5. Technology Progression

### Tech Levels by Strategy (Turn 15)

| Strategy | ECO | SCI | WPN | CST | Total Tech |
|----------|-----|-----|-----|-----|------------|
| **Economic** | 2.5 | **5.9** | 1.0 | **4.0** | **13.4** |
| **Turtle** | 2.5 | **5.8** | 1.0 | **4.0** | **13.3** |
| **Aggressive** | 1.5 | 4.7 | **3.0** | 2.6 | 11.8 |
| **Balanced** | 1.5 | 4.6 | **3.0** | 2.6 | 11.7 |

### Critical Analysis

**Science Advantage:** Economic/Turtle reach **SCI 6** while Aggressive/Balanced reach only **SCI 5**. This 1-level advantage compounds across all research.

**CST Tech Gap:** Economic/Turtle reach **CST 4** (fighter unlock at CST3) while Aggressive/Balanced reach only **CST 2.6** (no fighters). This is the **primary cause of strategic failure** for military-focused strategies.

**Weapons Investment Wasted:** Aggressive/Balanced invest heavily in WPN research (3.0 vs 1.0) but this doesn't translate to wins because:
1. They lack the economic base to afford expensive units
2. They miss fighter tech unlock
3. Higher-tier weapons require higher ship classes they can't afford

**Total Tech Disparity:** Economic/Turtle achieve 13.3-13.4 total tech levels vs 11.7-11.8 for Aggressive/Balanced. This **1.6-level advantage** represents a fundamental research output gap.

### Tech Scaling Feedback Loop

```
Science Strategies (Economic/Turtle):
├─ Invest in SCI/CST research
├─ Unlock fighters early (CST3)
├─ Build cost-efficient defense (2.86 PP/pwr fighters)
├─ Free up budget for economic growth
├─ Higher research output from larger economy
└─ Tech snowball continues

Military Strategies (Aggressive/Balanced):
├─ Invest in WPN research
├─ Miss fighter unlock (stuck at CST2.6)
├─ Forced into expensive escorts (3.20-3.53 PP/pwr)
├─ Military spending crowds out economic investment
├─ Lower research output from smaller economy
└─ Fall further behind in tech race
```

**Conclusion:** The tech tree **systematically punishes military-focused strategies** in the early-mid game. By Turn 15, they're already at an insurmountable disadvantage.

---

## 6. Balance Issues Identified

### Critical Issues

#### 1. Balanced Strategy 0% Win Rate
**Severity:** CRITICAL
**Samples:** 876 games, 0 wins

**Root Cause:** The "Balanced" strategy attempts to balance military and research investment, but in practice:
- Doesn't invest enough in SCI/CST to unlock fighters (2.6 CST vs 4.0 needed)
- Doesn't invest enough in WPN to out-muscle Aggressive (3.0 vs Aggressive's 3.0)
- Ends up being mediocre at everything, excellent at nothing

**Recommendation:** Rebalance "Balanced" to either:
- Option A: True hybrid (50/50 research split, reach CST3 + WPN3 by Turn 15)
- Option B: Opportunistic pivot (start research-focused, switch to military once fighters unlock)

#### 2. Aggressive Strategy 0.6% Win Rate
**Severity:** CRITICAL
**Samples:** 876 games, 5 wins

**Root Cause:**
- Overinvests in WPN research (3.0) at expense of CST (2.6)
- Misses fighter unlock entirely
- Forced into expensive scout production (2.0 avg)
- Heavy Cruiser overinvestment (military budget trap)

**Recommendation:** Adjust Aggressive strategy to:
- Set minimum CST research goal (reach CST3 by Turn 10-12)
- Reduce scout production cap (current 2.0 → target 1.0)
- Shift from Heavy Cruiser focus to fighter + escort mix

#### 3. Tech Tree Gating Imbalance
**Severity:** HIGH
**Impact:** All military-focused strategies

**Root Cause:** Fighter unlock requires CST3, but CST is typically a low priority for military strategies. This creates a **trap choice** where military strategies:
- Follow their strategic personality (prioritize WPN)
- Miss the most efficient combat unit (fighters)
- Forced into 12-25% less efficient units

**Recommendation:** Consider one of:
- Option A: Move fighter unlock to WPN3 or CST2 (earlier unlock)
- Option B: Add alternative unlock path (WPN3 + CST1 = light fighters)
- Option C: Buff escort efficiency to compensate (reduce DD/CL costs by 10-15%)

#### 4. Scout Overproduction
**Severity:** MEDIUM
**Impact:** Aggressive and Balanced strategies

**Root Cause:** These strategies build 2.0 scouts on average vs 0.8 for winners. Scouts cost 50PP each but provide no combat value.

**Analysis:** The game already has anti-spam features per reference.md, but scout production isn't adequately constrained. Aggressive/Balanced strategies waste ~60PP (1.2 scouts × 50PP) that could buy 3 fighters (180 power) or 1.5 destroyers.

**Recommendation:**
- Reduce scout build priority for military strategies
- Add diminishing returns for intelligence gathering (already in game per reference.md, may need tuning)
- Consider scout maintenance cost or capacity limit

### Moderate Issues

#### 5. Heavy Cruiser Investment Trap
**Severity:** MEDIUM
**Impact:** All strategies, especially Balanced/Aggressive

**Root Cause:** Heavy Cruisers have decent efficiency (3.20 PP/pwr) and are affordable (80PP), making them attractive mid-game purchases. However, winners build 46% fewer Heavy Cruisers than losers.

**Analysis:** Heavy Cruisers may be:
- Less effective in actual combat than stats suggest
- Poor fleet composition choice (better to specialize in fighters or capitals)
- Opportunity cost trap (80PP could buy 4 fighters = 28 power vs Heavy Cruiser 25 power)

**Recommendation:**
- Analyze combat logs to understand Heavy Cruiser underperformance
- Consider slight stat buff or cost reduction (80PP → 70PP)
- May be working as intended (versatile but not specialized)

#### 6. Carrier Adoption Rate
**Severity:** LOW
**Impact:** All strategies

**Root Cause:** Carriers show strong winner correlation (+43%) but overall adoption is low (1.9 avg for winners). Current carrier cost is 80PP after the recent balance fix (down from 120PP).

**Analysis:** Low carrier adoption may indicate:
- Carriers working as intended (strategic assets, not baseline fleet)
- SpecialUnits budget appropriately constraining carrier spam
- 15-turn games too short to show full carrier payoff

**Recommendation:**
- Monitor carrier adoption in longer games (30+ turns)
- Current 80PP cost seems appropriate (4× fighter cost)
- No immediate changes needed

#### 7. Ground Unit Production
**Severity:** INFORMATIONAL
**Impact:** All strategies

**Observation:** Ground units (armies, marine divisions, planetary shields, ground batteries) showed **zero production** across all 292 games (3,504 samples).

**Analysis:** This is expected behavior for 15-turn games (Act2_RisingTensions phase) because:
- Ground invasions typically occur in later acts (Act3_TotalWar, Act4_Endgame)
- AI priorities focus on expansion and fleet buildup in early/mid game
- Planetary defense infrastructure becomes critical only when facing invasion threats
- Spacelift operations (army transport) are prerequisites for ground warfare

**Data Coverage:** The diagnostic CSV files track all ground unit types:
- `army_units` (cost: 15PP per unit)
- `marine_division_units` (cost: 30PP per unit)
- `planetary_shield_units` (cost: 500PP per unit)
- `ground_battery_units` (cost: 100PP per unit)

**Recommendation:**
- Run extended 30+ turn tests to analyze ground warfare patterns
- Evaluate ground unit cost effectiveness in invasion scenarios
- Assess spacelift (ETAC/transport) utilization during Act3/Act4
- No immediate action needed (ground units are late-game assets)

---

## 7. Strategic Recommendations

### Immediate Tuning Priorities (High Impact)

#### 1. Fix Balanced Strategy
**Target:** Achieve 8-12% win rate (random chance in 12-player = 8.33%)

**Proposed Changes:**
```nim
# Current: Balanced attempts 50/50 military/economy split
# Problem: Ends up weak at everything

# Proposed: Front-load research, then military buildup
strategyWeights[Balanced] = @[
  # Early game: Focus research to unlock fighters
  (Turn 1-8): [research: 40%, economy: 35%, military: 15%, special: 10%]

  # Mid game: Shift to military once fighters unlocked
  (Turn 9-15): [military: 35%, research: 25%, economy: 25%, special: 15%]

  # Late game: Maintain balance with fighter advantage
  (Turn 16+): [military: 30%, research: 25%, economy: 25%, special: 20%]
]

# Tech priorities: Reach CST3 by Turn 8-10
techPriorities[Balanced] = @[
  CST: High (until level 3)
  SCI: Medium
  WPN: Medium (after CST3)
  ECO: Low
]
```

#### 2. Adjust Aggressive Strategy
**Target:** Achieve 5-10% win rate through focused military effectiveness

**Proposed Changes:**
```nim
# Current: Aggressive overinvests in scouts and Heavy Cruisers
# Problem: Misses fighter tech, wastes PP on intel gathering

# Proposed: Streamline military focus with CST minimum
strategyWeights[Aggressive] = @[
  military: 40%  (unchanged)
  research: 25%  (up from 20%, need CST3)
  economy: 20%   (down from 25%, accept smaller economy)
  special: 15%   (unchanged)
]

# Tech priorities: CST3 is non-negotiable
techPriorities[Aggressive] = @[
  CST: High (until level 3, then Low)
  WPN: High (after CST3)
  SCI: Medium
  ECO: Low
]

# Unit priorities: Reduce scout spam, add fighter focus
unitPriorities[Aggressive] = @[
  fighters: High (after CST3 unlock)
  destroyers: High
  battlecruisers: Medium
  scouts: Low (max 1 scout, not 2+)
  heavy_cruisers: Low (opportunity cost trap)
]
```

#### 3. Scout Production Limits
**Goal:** Prevent excessive intelligence gathering investment

**Proposed Changes:**
```nim
# Add scout production caps for all strategies
maxScoutsPerStrategy = @[
  Economic: 1
  Turtle: 1
  Balanced: 1
  Aggressive: 1  # Down from current ~2
  Espionage: 3   # Exception for intel-focused strategy
]

# Alternative: Add diminishing returns to intel gathering
# (may already exist per reference.md, tune the coefficients)
intelDiminishingReturns = exponential_decay(scout_count)
```

### Medium-Term Balance Changes

#### 4. Tech Tree Rebalancing
**Goal:** Reduce fighter unlock barrier for military strategies

**Options (choose one):**

**Option A: Earlier Fighter Unlock**
```toml
# config/ships.toml
[fighter]
cost = 20
tech_requirements = { cst = 2 }  # Down from CST3
```

**Option B: Alternative Unlock Path**
```toml
# Add weapons-focused fighter variant
[assault_fighter]
cost = 25
tech_requirements = { wpn = 3, cst = 1 }
attack_strength = 5  # Higher AS than regular fighter (4)
defense_strength = 2  # Lower DS than regular fighter (3)
```

**Option C: Buff Escort Efficiency**
```toml
# Reduce escort costs to compensate for missing fighters
[destroyer]
cost = 35  # Down from 40

[light_cruiser]
cost = 50  # Down from 60

[heavy_cruiser]
cost = 70  # Down from 80
```

**Recommendation:** Start with **Option A** (CST2 fighter unlock). This is the smallest change with highest impact.

### Long-Term Strategic Goals

#### 5. Comprehensive AI Personality Tuning

**Phase 1 (Completed):** Baseline testing of 4 primary strategies
- Economic: 16.1% win rate ✓
- Turtle: 16.7% win rate ✓
- Balanced: 0.0% win rate ✗
- Aggressive: 0.6% win rate ✗

**Phase 2 (Next):** Tune underperforming strategies to 8-12% win rate range

**Phase 3 (Future):** Test remaining 8 personalities
- Diplomatic
- Espionage
- Expansionist
- TechRush
- Raider
- MilitaryIndustrial
- Opportunistic
- Isolationist

**Phase 4 (Final):** Full 12-strategy balance testing with 1,000+ games

#### 6. Combat Effectiveness Analysis

The current analysis is based on **unit counts and costs**, not actual combat performance. Next steps:

1. **Combat Log Analysis:** Parse combat results to understand:
   - Why Heavy Cruisers underperform despite decent efficiency
   - Fighter effectiveness in actual engagements
   - Capital ship kill ratios

2. **Fleet Composition Study:** Analyze winning fleet mixes:
   - Do fighters + capitals beat pure escort fleets?
   - Optimal carrier-to-fighter ratios
   - Starbase + fighter defensive effectiveness

3. **Economic Efficiency:** Measure PP-to-prestige conversion:
   - Which units generate most prestige per PP?
   - Are winners winning through combat or economic dominance?
   - Colony count vs military strength tradeoffs

---

## 8. Testing Recommendations

### Immediate Next Steps

1. **Implement Priority Fixes:**
   - Tune Balanced strategy (focus research early, military mid-game)
   - Adjust Aggressive CST priorities (reach CST3 by Turn 10)
   - Add scout production caps

2. **Run Validation Tests:**
   - 500 games, 12 players, 15 turns
   - Same 4 strategies (Economic, Turtle, Balanced, Aggressive)
   - Target: Balanced 8-12% win rate, Aggressive 5-10% win rate

3. **Tech Tree Experiment:**
   - Test Option A (fighter unlock at CST2)
   - 200 games, 12 players, 15 turns
   - Measure fighter adoption across all strategies

### Future Testing

4. **Extended Game Length:**
   - 100 games, 12 players, 30 turns (Act3_TotalWar)
   - Validate carrier effectiveness in longer games
   - Measure late-game tech scaling

5. **Full 12-Strategy Suite:**
   - 1,000 games, 12 players, 15 turns
   - Include all AI personalities
   - Target: All strategies 5-12% win rate (±3% variance acceptable)

6. **Combat Analysis:**
   - Enable detailed combat logging
   - 50 games with combat trace
   - Analyze unit effectiveness in actual battles

---

## 9. Conclusion

### Key Findings

1. **Fighter Budget Fix Successful:** Economic/Turtle strategies build 2.4-2.6 fighters on average after moving fighters from SpecialUnits to Military budget. The fix is working as designed.

2. **Tech Tree Gating Problem:** Military-focused strategies (Aggressive, Balanced) fail to reach CST3 by Turn 15, missing fighter unlock entirely. This creates an **insurmountable efficiency disadvantage**.

3. **Science Snowball:** Strategies that prioritize SCI/CST research gain compounding advantages through:
   - Cost-efficient fighters (2.86 PP/pwr)
   - Larger economic base from tech advantages
   - Higher research output from stronger economy
   - Earlier access to advanced ship classes

4. **Unit Investment Traps:**
   - Excessive scout production (-64% for winners)
   - Heavy Cruiser overinvestment (-46% for winners)
   - Both correlate strongly with losing

5. **Carrier Advantage:** Winners build 43% more carriers than losers, despite low overall adoption (1.9 avg). Strategic mobility and fighter projection are high-value capabilities.

### Strategic Balance Status

| Strategy | Status | Win Rate | Fix Priority |
|----------|--------|----------|--------------|
| Economic | ✓ Balanced | 16.1% | None |
| Turtle | ✓ Balanced | 16.7% | None |
| Balanced | ✗ Broken | 0.0% | **CRITICAL** |
| Aggressive | ✗ Broken | 0.6% | **CRITICAL** |

### Next Steps

**Immediate (This Week):**
1. Implement Balanced strategy tuning (research-first approach)
2. Adjust Aggressive CST priorities (CST3 by Turn 10)
3. Add scout production caps

**Short-Term (This Month):**
4. Test fighter unlock at CST2 (reduce tech barrier)
5. Run 500-game validation test
6. Analyze combat logs for unit effectiveness data

**Long-Term (Next Quarter):**
7. Tune remaining 8 AI personalities
8. Full 12-strategy balance test (1,000+ games)
9. Extended game testing (30-turn games)

---

## Appendix A: Raw Data Summary

### Games Analyzed
- Total games: 292
- Players per game: 12
- Total samples: 3,504
- Turns per game: 15
- Map size: 12 rings (~469 systems)

### Strategy Distribution
- Economic: 876 samples (25%)
- Balanced: 876 samples (25%)
- Turtle: 876 samples (25%)
- Aggressive: 876 samples (25%)

### Win Distribution
- Economic: 141 wins (16.1%)
- Turtle: 146 wins (16.7%)
- Balanced: 0 wins (0.0%)
- Aggressive: 5 wins (0.6%)

### Average Resources (Turn 15)
| Strategy | Treasury | Production | Colonies |
|----------|----------|------------|----------|
| Economic | 423 | - | 16.0 |
| Turtle | 425 | - | 16.1 |
| Balanced | 441 | - | 14.5 |
| Aggressive | 443 | - | 14.5 |

---

**Report Generated:** 2025-11-30
**Analysis Tools:**
- tools/ai_tuning/run_parallel_diagnostics.py
- tools/ai_tuning/analyze_12_strategies.py
- tools/ai_tuning/analyze_unit_effectiveness.py
