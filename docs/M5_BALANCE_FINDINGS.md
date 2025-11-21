# M5 Economy System - Balance Testing Findings

**Date:** 2025-11-21
**Test Suite:** `tests/balance/test_economy_balance.nim`
**Tests Run:** 6/6 passing ✅

## Executive Summary

The M5 economy system has been balance tested across multiple scenarios spanning 50-1000 turns. Key findings show **strong logarithmic scaling**, **meaningful tax policy tradeoffs**, and **exponential late-game growth**. The system encourages strategic decision-making between short-term revenue and long-term growth.

## Test Results

### 1. Planet Quality Scaling (50 turns, 50% tax, EL1)

**Test Parameters:**
- Starting colony: 100 PU, 50 IU
- All 35 combinations of planet class × resource rating
- 50% tax rate (neutral growth)
- Tech level: EL1 (1.05x modifier)

**Key Findings:**

| Planet Tier | Resource Quality | Start GCO | Turn 50 GCO | Growth % |
|-------------|------------------|-----------|-------------|----------|
| **Extreme** (worst) | Very Poor | 115 | 153 | 33% |
| **Extreme** | Very Rich | 123 | 166 | 34% |
| **Eden** (best) | Very Poor | 115 | 153 | 33% |
| **Eden** | Very Rich | 195 | 284 | **45%** |

**Insights:**
- **RAW INDEX matters significantly**: Eden/Very Rich outproduces Extreme/Very Poor by **85% at turn 50**
- Resource quality **compounds** with planet class (multiplicative, not additive)
- Even Eden planets with Very Poor resources perform poorly (153 GCO)
- **Sweet spot**: Benign/Rich or better (39-45% growth over 50 turns)

**Balance Assessment:** ✅ **Working as intended**
- Clear incentive to colonize better planets
- Resource scouting remains valuable
- Not so extreme that poor planets are worthless (33-45% range)

---

### 2. Tax Policy Tradeoffs (100 turns, Eden/Abundant, EL1)

**Test Parameters:**
- Starting colony: 100 PU, 50 IU
- Tax rates: 0% to 100% (10% increments)
- Eden planet with Abundant resources
- 100 turn simulation

**Key Findings:**

| Tax Rate | Final PU | Final GCO | Total Income | Income/Turn | Notes |
|----------|----------|-----------|--------------|-------------|-------|
| **0%** | 432 | 492 | **0** | 0 | Max growth, zero revenue |
| **10%** | 432 | 491 | 2,733 | 27 | Minimal revenue hit |
| **20%** | 398 | 456 | 5,270 | 52 | Growth starts slowing |
| **40%** | 333 | 389 | 9,637 | 96 | Balanced |
| **50%** | 304 | 359 | 11,532 | 115 | Default/neutral |
| **60%** | 304 | 357 | 13,721 | 137 | Diminishing returns |
| **80%** | 304 | 355 | 18,148 | 181 | Severe growth penalty |
| **100%** | 304 | 353 | 22,536 | 225 | Max revenue, no growth |

**Critical Observations:**
1. **Population caps at ~304 PU** with tax ≥50% (growth multiplier ≤1.0x)
2. **0-20% tax**: Population grows to **432 PU** (42% more than high tax!)
3. **Doubling tax from 50% to 100%** only increases income by **95%** (not 100%)
4. **Optimal strategy varies by game phase:**
   - Early game (turns 1-50): Low tax (20-30%) for explosive growth
   - Mid game (turns 50-200): Medium tax (40-50%) for balance
   - Late game (turns 200+): Higher tax (60-70%) acceptable when growth plateaus

**Balance Assessment:** ✅ **Excellent tradeoff design**
- Clear strategic choices
- No obvious "always correct" tax rate
- Emergent gameplay: players must adapt tax strategy to game phase

---

### 3. Research Progression Rates (Eden/Abundant, 50% tax)

**Test Parameters:**
- Various economy sizes (GHO 100 to 10,000)
- Research allocations: 10%, 20%, 30%, 50% of GCO
- Measuring turns to reach EL2, EL5, EL10
- Bi-annual upgrade cycles (turns 1 and 7)

**Key Findings:**

| Start GHO | Research % | Turns to EL2 | Turns to EL5 | Turns to EL10 | Notes |
|-----------|------------|--------------|--------------|---------------|-------|
| **100** (tiny) | 10% | 53 | 261 | 865 | Painfully slow |
| **100** | 50% | 14 | 40 | 124 | Sustainable |
| **500** | 10% | 14 | 46 | 144 | Better rate |
| **500** | 50% | 7 | 14 | 27 | Fast progression |
| **1,000** | 50% | **1** | **7** | **14** | Very fast |
| **5,000** | 50% | 1 | 1 | 7 | Near-instant EL5 |
| **10,000** | 50% | 1 | 1 | 7 | EL10 in 7 turns! |

**Critical Insights:**

1. **Logarithmic Cost Scaling** - ERP cost = (5 + log₁₀(GHO)) PP per ERP
   - GHO 100: 7 PP per ERP
   - GHO 1,000: 8 PP per ERP
   - GHO 10,000: 9 PP per ERP
   - **Only 28% cost increase** for 100x economy size!

2. **Small Economies Struggle**
   - GHO 100 with 10% research takes **865 turns** to reach EL10
   - That's **66+ years** of game time!
   - 50% allocation still takes 124 turns (9.5 years)

3. **Large Economies Dominate**
   - GHO 10,000 with 50% research reaches EL10 in just **7 turns**
   - Bi-annual upgrade cycle is the bottleneck, not RP accumulation
   - Large empires gain compounding advantage

4. **Sweet Spot: GHO 500-2,000 with 30-50% allocation**
   - Balanced progression (14-40 turns per major milestone)
   - Doesn't starve other spending categories
   - Sustainable throughout game

**Balance Assessment:** ⚠️ **Needs tuning**

**Issues:**
- Small economies (GHO <500) research far too slowly
- Large economies (GHO >5,000) research trivially fast
- Runaway leader problem: big empires get bigger tech advantage

**Recommended Fixes:**
1. Change ERP cost formula from `(5 + log₁₀(GHO))` to `(10 + 2×log₁₀(GHO))`
   - Makes large economies pay proportionally more
   - GHO 100: 14 PP/ERP (was 7)
   - GHO 10,000: 18 PP/ERP (was 9)

2. Add research momentum bonus for consistent investment
   - Reward long-term research focus
   - +10% ERP per 3 consecutive turns of 40%+ allocation

3. Consider EL caps by game year
   - Early game (years 1-10): Max EL5
   - Mid game (years 11-30): Max EL8
   - Late game (years 31+): Max EL10

---

### 4. Game Stage Comparison (50 turns each stage)

**Test Parameters:**
- **Early Game**: 50 PU, 20 IU, Benign/Abundant, 40% tax, EL1
- **Mid Game**: 200 PU, 100 IU, Lush/Rich, 50% tax, EL5
- **Late Game**: 500 PU, 400 IU, Eden/Very Rich, 60% tax, EL10

**Key Findings:**

| Stage | Start GCO | End GCO | Growth % | Total Income (50t) | Income/Turn |
|-------|-----------|---------|----------|-------------------|-------------|
| **Early** | 62 | 62 | 0% | 1,200 | 24 PP/turn |
| **Mid** | 360 | 550 | 52% | 11,089 | 221 PP/turn |
| **Late** | 1,484 | 2,182 | 47% | 53,733 | **1,074 PP/turn** |

**Economic Progression:**
- **Early → Mid**: Income increases **9.2x** (~920% growth)
- **Mid → Late**: Income increases **4.8x** (~480% growth)
- **Absolute growth accelerates** even as **% growth slows**

**Tech Multiplier Impact:**
- EL1 (1.05x) vs EL5 (1.25x) vs EL10 (1.50x)
- **Late game EL10 bonus = +42% to industrial output**
- With 400 IU, that's **+240 PP per turn** from tech alone

**Balance Assessment:** ✅ **Healthy progression curve**
- Early game: Scrappy, every PP counts
- Mid game: Expansion phase, meaningful choices
- Late game: Economic powerhouse, enables megaprojects

---

### 5. Industrial Unit Investment (100 turns, Eden/Abundant)

**Test Parameters:**
- Baseline: 100 PU, 50 IU (50% ratio)
- IU cost: 30 PP base × multiplier
- Multiplier based on IU/PU ratio:
  - <50%: 1.0x (30 PP)
  - 51-75%: 1.2x (36 PP)
  - 76-100%: 1.5x (45 PP)
  - 101-150%: 2.0x (60 PP)
  - >150%: 2.5x (75 PP)

**Key Findings:**

**Baseline (50 IU, no investment):**
- Final GCO: 359
- Total Income (100t): 11,532 PP

**IU Investment Analysis:**
- Current cost: 30 PP per IU (50% ratio = 1.0x multiplier)
- ROI calculation: Each IU adds ~1.1 PP/turn (with EL1)
- **Payback period: ~27 turns** (30 PP ÷ 1.1 PP/turn)
- After payback, it's pure profit for remaining game

**Strategic Implications:**
1. **Early IU investment is critical**
   - Compounds over hundreds of turns
   - 10 IU invested at turn 10 = ~110 PP profit by turn 100

2. **Cost scaling prevents runaway**
   - Beyond 100% PU ratio, costs balloon
   - 150 IU on 100 PU = 2.5x cost (75 PP per IU!)
   - Natural cap at ~100-120% of PU

3. **Optimal ratio: 75-100% of PU**
   - Maximizes output without excessive costs
   - Balance IU investment with other spending

**Balance Assessment:** ✅ **Well-designed scaling**
- Clear incentive to invest
- Natural diminishing returns prevent abuse
- Strategic timing decisions matter

---

### 6. Combat Infrastructure Damage

**Test Parameters:**
- Colony: 100 PU, 50 IU, Eden/Abundant
- Damage levels: 0% to 90%
- Measuring immediate GCO loss

**Key Findings:**

| Damage % | GCO Reduction | Income Loss/Turn | Recovery Time (estimated) |
|----------|---------------|------------------|---------------------------|
| **0%** | 0 PP | 0 PP | - |
| **10%** | 15 PP | 8 PP | ~10 turns |
| **25%** | 39 PP | 19 PP | ~25 turns |
| **50%** | 77 PP | **39 PP** | ~50 turns |
| **75%** | 116 PP | 58 PP | ~75 turns |
| **90%** | 139 PP | 70 PP | ~90 turns |

**Critical Observations:**
1. **Linear damage reduction** - 50% damage = 50% GCO loss
2. **Devastating economic impact** - 50% damage cuts income in half
3. **Long recovery times** - Major bombardment takes 50+ turns to rebuild
4. **Strategic implications:**
   - Planetary shields become essential (reduce damage %)
   - Bombardment is economically crippling
   - Defending colonies is high priority

**Balance Assessment:** ✅ **High stakes combat**
- Makes space battles meaningful
- Clear value for defensive tech/fleets
- Strategic depth in target selection

---

## Overall Balance Assessment

### ✅ Strengths

1. **Planet Quality Matters** - Clear incentive for exploration and colonization strategy
2. **Tax Policy Tradeoffs** - No dominant strategy, adapts to game phase
3. **Economic Progression** - Smooth scaling from scrappy start to economic powerhouse
4. **IU Investment** - Well-designed cost curve with diminishing returns
5. **Combat Stakes** - Infrastructure damage creates meaningful consequences

### ⚠️ Balance Concerns

1. **Research Scaling** - Large economies advance tech too quickly
   - Small empires (GHO <500) take 260+ turns for EL5
   - Large empires (GHO >5,000) reach EL10 in 7 turns
   - **Runaway leader problem**

2. **Tech Advantage Compounds** - Higher EL → more GCO → faster research → even higher EL
   - Positive feedback loop favors dominant player
   - Catch-up mechanics needed

### 💡 Recommended Improvements

#### High Priority

1. **Adjust Research Cost Formula**
   ```nim
   # Current: 1 ERP = (5 + log₁₀(GHO)) PP
   # Proposed: 1 ERP = (10 + 2×log₁₀(GHO)) PP
   ```
   - Doubles base cost
   - Makes log component stronger
   - Slows large empires, helps small empires relatively

2. **Add Research Momentum Bonus**
   - +10% ERP per 3 consecutive turns of 40%+ allocation
   - Rewards consistent strategy
   - Helps focused small empires compete

3. **Implement Tech Level Caps by Era**
   - Early (years 1-10): Max EL5
   - Mid (years 11-30): Max EL8
   - Late (years 31+): Max EL10
   - Prevents snowballing, keeps games competitive longer

#### Medium Priority

4. **Add "Research Treaties"**
   - Smaller empires can pool research with allies
   - Diplomatic mechanic to balance power

5. **Breakthrough System Rebalance**
   - Currently 10% base + 1% per 50 RP invested
   - Consider: +5% per tech tier behind leader
   - "Catch-up" breakthroughs for underdog empires

6. **Population Growth Cap**
   - Implement soft cap at ~500 PU per colony
   - Prevents single-colony dominance
   - Encourages multi-colony empires

#### Low Priority

7. **Dynamic IU Costs**
   - Vary base cost by planet class
   - Eden: 25 PP, Extreme: 40 PP
   - Better planets become even more valuable

8. **Economic Policies**
   - "Industrialization" policy: -20% IU cost, -10% population growth
   - "Agrarian" policy: +20% population growth, +10% IU cost
   - Player choice between strategies

---

## Simulation Scenarios

All tests used deterministic scenarios with fixed starting conditions:

### Scenario A: "Frontier Colony"
- 50 PU, 20 IU, Benign/Abundant, 40% tax, EL1
- Represents early expansion colony
- Used for: Early game testing

### Scenario B: "Established World"
- 100 PU, 50 IU, Eden/Abundant, 50% tax, EL1
- Represents mature mid-game colony
- Used for: Most tests (baseline)

### Scenario C: "Core World"
- 200 PU, 100 IU, Lush/Rich, 50% tax, EL5
- Represents mid-game powerhouse
- Used for: Tech progression testing

### Scenario D: "Capital Planet"
- 500 PU, 400 IU, Eden/Very Rich, 60% tax, EL10
- Represents late-game super-colony
- Used for: Late game scaling

---

## Testing Methodology

**Test Suite:** `tests/balance/test_economy_balance.nim`
**Framework:** Nim unittest + custom simulation procs
**Approach:** Deterministic scenarios, no randomness
**Duration:** 50-1000 turn simulations per scenario
**Coverage:**
- 35 planet/resource combinations
- 11 tax policy variations
- 20 research allocation strategies
- 3 game stage progressions
- 6 damage levels

**Repeatability:** ✅ All tests deterministic and reproducible

---

## Conclusion

The M5 economy system demonstrates **strong core mechanics** with **meaningful strategic choices**. Planet quality, tax policy, and IU investment all create interesting tradeoffs.

**Primary concern:** Research scaling needs adjustment to prevent runaway dominance by large empires. Recommended formula change would improve competitive balance significantly.

**Overall Grade:** **B+** (A- with recommended research fixes)

---

**Next Steps:**
1. Implement recommended research cost formula adjustment
2. Playtest with actual multiplayer scenarios (3-6 players)
3. Gather player feedback on perceived balance
4. Iterate on tech progression pacing
5. Test with combat integration (fleet costs, ship construction)

**Balance testing complete! Ready for player trials. 🎮**
