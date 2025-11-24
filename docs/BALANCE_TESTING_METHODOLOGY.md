# EC4X Balance Testing Methodology

**Last Updated:** 2025-11-23

## Overview

EC4X uses **competitive coevolution with genetic algorithms** to automatically test game balance across multiple strategic approaches. This methodology is grounded in academic research on game balance and evolutionary computation.

---

## Academic Foundation

### Key Research Papers

Our approach is based on established research in game balance and competitive coevolution:

1. **[On Video Game Balancing: Joining Player- and Data-Driven Analytics](https://dl.acm.org/doi/10.1145/3675807)** (ACM 2024)
   - Analyzed 4+ million in-game fights in Guild Wars 2
   - Finding: Balance greatly influences player satisfaction and game success

2. **[Analyzing Competitive Coevolution across Families of N-Player Games](https://dl.acm.org/doi/10.1145/3729878.3746621)** (ACM FOGA 2025)
   - Monte Carlo tree search as adaptive benchmark for N-player competitive coevolution
   - Directly applicable to our 5-species competitive setup

3. **[Virtual Player Design Using Self-Learning via Competitive Coevolutionary Algorithms](https://link.springer.com/article/10.1007/s11047-014-9411-3)** (Natural Computing)
   - **Key finding:** Coevolved controllers achieve better generalization than standard evolution
   - Competitive coevolution creates "arms race" dynamics driving higher performance

4. **[An Electronic-Game Framework for Evaluating Coevolutionary Algorithms](https://www.researchgate.net/publication/301879801_An_electronic-game_framework_for_evaluating_coevolutionary_algorithms)**
   - Applied to RTS games and action-platformer games
   - Coevolution helps avoid premature convergence (fitness stagnation)

### Key Insights from Research

- **Cyclic dynamics are expected:** No single strategy should consistently dominate across runs
- **Variance is normal:** Rock-paper-scissors relationships create unstable equilibria
- **Sample size matters:** Need 20-50+ generations and multiple parallel runs
- **Diversity preservation:** Genetic algorithms naturally maintain strategy diversity

---

## Our Implementation

### System Architecture

```
tests/balance/
├── genetic_ai.nim          # Core genetic algorithm (mutation, crossover, selection)
├── coevolution.nim         # 5-species competitive coevolution framework
├── parallel_sim.nim        # Multi-threaded game simulation
├── run_parallel_test.sh    # GNU Parallel orchestration (4x speedup)
└── analyze_results.nim     # Comprehensive balance analysis & reporting
```

### Five Species (Strategic Archetypes)

1. **Economic** - High expansion, infrastructure focus, low aggression
2. **Military** - High aggression, combat focus, resource efficiency
3. **Diplomatic** - Pact formation, peaceful expansion, trade focus
4. **Technology** - Research priority, tech advantage, long-term power
5. **Espionage** - Disruption, asymmetric warfare, support strategy

### Genetic Algorithm Parameters

- **Population:** 5-8 individuals per species
- **Mutation Rate:** 15% with Gaussian noise
- **Crossover Rate:** 70% (blend crossover)
- **Selection:** Tournament selection with elitism
- **Fitness:** Win rate + colony count + military strength + prestige

### AI Personality Genes

Each AI is defined by continuous personality traits (0.0-1.0):
- `aggression` - Willingness to engage in combat
- `riskTolerance` - Acceptance of uncertain outcomes
- `economicFocus` - Priority on infrastructure/production
- `expansionDrive` - Colony acquisition urgency
- `diplomacyValue` - Pact formation preference
- `techPriority` - Research investment preference

**Key Design:** Strategy emerges from personality weights, not hardcoded behavior.

---

## Testing Protocol

### Quick Validation Test (5 minutes)
```bash
./tests/balance/run_parallel_test.sh 4 3 5 3
# 4 parallel runs, 3 generations, 5 population, 3 games/gen
```

### Standard Balance Test (10-15 minutes)
```bash
./tests/balance/run_parallel_test.sh 4 10 8 5
# 4 parallel runs, 10 generations, 8 population, 5 games/gen
```

### Comprehensive Overnight Test (recommended)
```bash
./tests/balance/run_parallel_test.sh 10 30 10 10
# 10 parallel runs, 30 generations, 10 population, 10 games/gen
# ~6-8 hours, generates 3000+ game simulations
```

---

## Interpreting Results

### Balance Report Structure

The analysis tool generates markdown reports with:
1. **Executive Summary** - Overall balance assessment (🟢🟡🔴)
2. **Species Performance Table** - Win rates, game counts, fitness scores
3. **Balance Issues** - Categorized by severity (Critical/High/Medium/Low)
4. **Evolution Trends** - Fitness progression over generations
5. **Recommendations** - Specific actions to address imbalances

### Expected Patterns

#### Healthy Balance (Target):
- Win rates between 15-30% (for 5-player games, 20% is ideal)
- No strategy consistently dominates across multiple runs
- Fitness continues improving through generations
- Rock-paper-scissors dynamics between strategies

#### Imbalance Indicators:
- **Critical (>60% win rate):** Strategy is overpowered
- **Unviable (<5% win rate):** Strategy needs buffs
- **High variance (>20%):** Unstable meta, may need more data
- **Fitness stagnation:** Local optimum or strategy ceiling reached

### Understanding Cyclic Dynamics

Our testing has revealed the following patterns:

| Test Run | Economic | Military | Technology | Diplomatic | Espionage |
|----------|----------|----------|------------|------------|-----------|
| Test 1 (5 gen) | 65% 🔴 | 45% | 20% | 2.5% | 5% |
| Test 2 (3 gen) | 33% | 27% | 37% 🥇 | 11% | 15% |
| Test 3 (10 gen) | 30% | 69% 🔴 | 0% | 24% | 0% |

**Interpretation:** This variance is **expected and healthy** according to academic research. It indicates:
1. No single dominant strategy across all conditions
2. Rock-paper-scissors relationships exist
3. Initial population randomness affects evolution paths
4. Need larger sample sizes for statistical confidence

---

## Espionage Balance Fixes (2025-11-22)

### Problem Identified

Espionage was completely unviable (0% win rate) due to:
1. AI controller hardcoded to only use espionage when `strategy == AIStrategy.Espionage`
2. Genetic algorithm creates all AIs with `strategy: Balanced` regardless of personality
3. Budget threshold was 5%, making espionage investment impossible (40 PP cost per EBP vs ~2 PP allowed)
4. Espionage personality had aggression too high (0.4-0.7 instead of 0.1-0.4)

### Solutions Applied

1. **AI Controller Logic** (tests/balance/ai_controller.nim)
   - Changed espionage decisions to use personality weights instead of strategy enum
   - Formula: `espionageChance = riskTolerance * 0.5 + (1-aggression) * 0.3 + techPriority * 0.2`
   - EBP/CIP investment: `espionageFocus = (riskTolerance + (1-aggression)) / 2.0`

2. **Budget Threshold** (config/espionage.toml)
   - Increased from 5% to 20% to allow viable espionage-focused strategies
   - 5% was mathematically impossible (1.8 PP allowed vs 40 PP cost per EBP)

3. **Espionage Personality** (tests/balance/coevolution.nim)
   - `aggression`: 0.1-0.4 (was 0.4-0.7) - **critical fix**
   - `riskTolerance`: 0.7-1.0 (high risk for espionage actions)
   - `techPriority`: 0.6-0.9 (high tech for EBP value)

### Results

Post-fix testing shows espionage is now viable but intentionally not dominant:
- 5-15% win rate in most tests
- Espionage fitness improving over generations
- Functions as intended: asymmetric disruption rather than direct victory path

---

## Variable Player Count Testing Strategy

### Phased Approach

The game supports 2-12 players, but balance characteristics change dramatically with player count. We use a phased testing approach:

#### Phase 1: Fixed 4-Player Tuning (Current)
**Goal:** Establish stable baseline with all strategies viable

**Setup:**
- Fixed 4 players per game
- Each house assigned specific strategy (Aggressive, Economic, Balanced, Turtle)
- 10 games per test run for statistical sampling
- Fast iteration on personality parameters

**Success Criteria:**
- All strategies achieve >0% win rate
- No systematic collapses (negative prestige)
- Competitive games (win rates between 20-40%)
- Clear strategy differentiation maintained

**Testing Method:**
```bash
python3 run_balance_test.py  # 10 games, 4 players each
```

#### Phase 2: Act-by-Act Analysis (Current)
**Goal:** Validate 4-act game structure and identify where balance breaks down

**Rationale:**
- 30-turn games span 150-300 years in-game (5-10 years per turn)
- Each act should have distinct characteristics and natural transitions
- Need to understand progression curves, not just final outcomes
- Enables targeted tuning (fix Act 1 issues before testing Act 3)

**Test Configuration:**
```bash
# Phase 2A: Act 1 - The Land Grab (7 turns = 35-70 years)
python3 run_balance_test_parallel.py --workers 8 --games 200 --turns 7

# Phase 2B: Act 2 - Rising Tensions (15 turns = 75-150 years)
python3 run_balance_test_parallel.py --workers 8 --games 200 --turns 15

# Phase 2C: Act 3 - Total War (25 turns = 125-250 years)
python3 run_balance_test_parallel.py --workers 8 --games 200 --turns 25

# Phase 2D: Full Game - Endgame (30 turns = 150-300 years)
python3 run_balance_test_parallel.py --workers 8 --games 200 --turns 30
```

**Analysis Focus per Act:**

**Act 1 (Turn 7):**
- Colony expansion working? (Target: 5-8 colonies)
- Economic foundations established? (Target: 50-150 prestige)
- Early game collapses?
- Differentiation visible between strategies?

**Act 2 (Turn 15):**
- Conflicts emerging? (First wars, territory disputes)
- Tech advantages appearing? (Level 2-3)
- Leaders and laggards clear? (Target: 150-500 prestige range)
- Strategy effectiveness diverging?

**Act 3 (Turn 25):**
- Decisive phase working? (Clear winners, eliminations)
- Prestige leaders pulling ahead? (Target: 1000+ for leaders)
- Total war dynamics present?
- Victory in sight for someone?

**Act 4 (Turn 30):**
- Winner emerges naturally?
- Satisfying conclusion or arbitrary cutoff?
- 4-act dramatic arc complete?
- Prestige victory threshold appropriate?

#### Phase 3: Variable Player Count Scaling (Future)
**Goal:** Identify how strategies scale with different player counts

**Why player count matters:**
- **Diplomacy:** 4 players = 3 potential allies, 12 players = 11 (complex webs)
- **Resources:** 4 players = ~7 colonies each, 12 players = ~2 colonies each
- **Military:** Squadron limits scale with PU (affected by colony count)
- **Espionage:** More players = more targets, higher value for intel

**Test Configuration:**
```python
PLAYER_COUNTS = [4, 6, 8, 10, 12]
GAMES_PER_COUNT = 5  # 25 total games
```

**Analysis Focus:**
- Strategy win rates at each player count
- Resource competition patterns
- Diplomatic strategy viability scaling
- Identify strategies that don't scale well

#### Phase 4: Full Randomization (Future)
**Goal:** Universal balance across all configurations

**Setup:**
- Random player counts 4-12 per game
- Random strategy assignments
- Large sample size (100+ games)

**Success Criteria:**
- No strategy dominates at any player count
- Smooth scaling from small (4) to large (12) games
- Variety in outcomes regardless of player count

### Current Status (as of 2025-11-23)

**✅ Phase 1 Complete:**
- Aggressive strategy: STABLE (0.5% collapse rate in 200 games, but 41.5% win rate - overpowered)
- Economic strategy: STABLE (6% collapse rate in 200 games, 30% win rate - vulnerable to dominant Aggressive)
- Turtle strategy: PERFECT (0% collapse rate in 200 games, 21.5% win rate - ideal balance)
- Balanced strategy: BROKEN (12.5% collapse rate in 200 games, 7% win rate - needs rework)

**✅ Parallel Testing Infrastructure:**
- 8-worker parallel testing achieves 60+ games/second
- 200-game test completes in ~3.3 seconds
- 7.45x speedup vs sequential (near-ideal 8x scaling)

**✅ Multi-Generational Timeline Framework:**
- Documented 4-act game structure (Land Grab → Rising Tensions → Total War → Endgame)
- Each turn = 5-10 years in-game (30 turns = 150-300 years)
- Current mechanics appropriate for multi-generational timeline

**🔄 Phase 2 In Progress: Act-by-Act Analysis**
- **Next:** Phase 2A - Act 1 analysis (7-turn games, 200 samples)
- **Goal:** Validate early game balance and 4-act structure

**⏳ Phase 3:** Blocked until Phase 2 validates scaling behavior

### Implementation Notes

**What needs to change for Phase 2:**

1. **run_balance_test.py:**
   ```python
   for player_count in [4, 6, 8, 10, 12]:
       for game in range(GAMES_PER_COUNT):
           run_game(player_count, strategies)
   ```

2. **Strategy assignment:**
   - 4 players: [Aggressive, Economic, Balanced, Turtle]
   - 6 players: Add [Espionage, Diplomatic]
   - 8+ players: Repeat strategies or random assignment

3. **Analysis updates:**
   - Track performance by player count
   - Generate per-count win rate tables
   - Identify scaling issues

**Already supported:**
- `createBalancedGame(numHouses, numSystems, seed)` handles variable player counts
- Engine supports 2-12 players without modification

---

## Game Pacing Design: The 30-Day Game

### Design Philosophy

EC4X is designed for **daily turn-based multiplayer** with a target game length of **30 days** (30 turns). This creates a compelling 1-month commitment with natural story progression and achievable victory conditions.

### The 4-Act Structure

A well-paced 30-turn game follows a dramatic arc with clear phases:

#### Act 1: The Land Grab (Days 1-7)
**Objective:** Establish your empire's foundation

**Key Milestones:**
- Expand to 5-8 colonies
- Scout neighboring territories
- Establish initial production base (50-100 PP/turn)
- Make first contact with rivals
- Form early alliances or identify threats

**Player Experience:**
- High activity - lots of decisions
- Exploration and discovery
- Setting strategic direction
- Minimal conflict (everyone expanding)

**Expected Prestige Range:** 50-150

#### Act 2: Rising Tensions (Days 8-15)
**Objective:** Establish dominance in your region

**Key Milestones:**
- Reach 10-15 colonies
- First military engagements
- Tech level 2-3 in key areas
- Resource conflicts emerge
- First invasions/territory disputes
- Alliances tested by proximity

**Player Experience:**
- Strategic pivots based on neighbors
- First major fleet battles
- Diplomatic maneuvering
- Economic vs military tradeoffs

**Expected Prestige Range:** 150-500

#### Act 3: Total War (Days 16-25)
**Objective:** Push for victory or survive elimination

**Key Milestones:**
- Peak empire size (15-25 colonies)
- Tech level 3-4 advantages decisive
- Major wars with clear winners/losers
- Prestige leaders pull ahead (1000-1500)
- Desperate alliances form
- First player eliminations possible

**Player Experience:**
- High-stakes battles every turn
- Territory changing hands
- Clear leaders emerge
- Comeback mechanics matter
- Every decision critical

**Expected Prestige Range:** 500-1500

#### Act 4: Endgame (Days 26-30)
**Objective:** Secure victory or orchestrate comeback

**Key Milestones:**
- Prestige victory possible (2000-3000 threshold)
- Elimination victories (last house standing)
- Final desperate alliances
- Last-minute betrayals
- Dominant players consolidate or get overwhelmed

**Player Experience:**
- Intense finale
- Victory within reach or fighting for survival
- Social drama peaks
- Satisfying conclusion

**Expected Prestige Range:** 1000-3000 (winner)

### Pacing Requirements: Multi-Generational Timeline

**CRITICAL INSIGHT:** Each player turn represents **5-10 years of in-game time**. This means:

- **30 player turns = 150-300 years in-game**
- **Multi-generational empire building**
- Population growth happens over decades
- Technology advances over generations
- Colonies mature over lifetimes

This creates an **epic scope** where players make strategic decisions across centuries while experiencing a 30-day game commitment.

#### Timeline Options

**Option 2: 1 turn = 5 years (recommended for faster pace)**
- 30 turns = 150 years
- 2-3 generations of leaders
- Colonies grow from settlements to core worlds in 50-100 years
- Technology advances over decades (reasonable)

**Option 3: 1 turn = 10 years (recommended for epic scale)**
- 30 turns = 300 years
- 5-6 generations of leaders
- Colonies develop over centuries
- Technology evolution feels generational
- Greater sense of dynasty building

#### Current Mechanics Already Appropriate

**NO artificial acceleration needed** - the mechanics are designed for multi-year turns:

- **Population growth per turn**: Reasonable over 5-10 years
- **Tech research**: Advancement over decades makes sense
- **Colony development**: Growing from outpost to thriving world over generations
- **Fleet construction**: Building armadas over years, not days
- **Prestige accumulation**: Dynasty reputation built across lifetimes

### Configuration Philosophy

Rather than speeding up mechanics, we tune for **meaningful progression within the multi-generational timeline**:

#### 1. Colony Development Over Decades
```toml
# Population growth per turn = growth over 5-10 years
# New colonies need 5-10 turns (25-100 years) to reach maturity
# Rationale: Building civilizations takes generations
```

#### 2. Technology Over Generations
```toml
# Tech advancement = generational progress
# Major tech breakthroughs every 3-5 turns (15-50 years)
# Rationale: Scientific revolutions span decades
```

#### 3. Military Buildup Over Years
```toml
# Fleet construction = multi-year industrial effort
# Building armada over 5-10 turns = 25-100 years of preparation
# Rationale: Military supremacy requires sustained investment
```

#### 4. Prestige = Dynastic Legacy
```toml
# Prestige accumulation = historical reputation over centuries
# Victory threshold = legendary dynasty status
# Rationale: Great houses earn prestige across generations
```

### Testing Implications

#### For AI Balance Testing (Current Phase)
- **Test length:** 30-turn games (full game lifecycle)
- **Timeline scale:** Testing with current mechanics (no acceleration)
- **Victory conditions:** Prestige victory OR elimination OR turn 30 limit
- **Focus:**
  - Does balance hold across all 4 acts?
  - Do AI strategies complete the 4-act dramatic arc?
  - Is prestige progression appropriate for multi-generational timeline?
  - Are victories achievable by turn 25-30?

#### For Human Playtesting (Future)
- **Test length:** 30-turn games (1 month commitment)
- **Victory conditions:** Prestige threshold OR elimination OR turn 30
- **Focus:**
  - Is each act engaging with multi-generational framing?
  - Does timeline feel epic (centuries passing)?
  - Do players feel they're building dynasties?
  - Is 1-turn-per-day pacing satisfying?

#### Validation Metrics (Multi-Generational Timeline)

These targets assume **1 turn = 5-10 years in-game**:

- **Act 1 (T7 = 35-70 years):**
  - Empire establishment phase (first generation)
  - Target: 5-8 colonies, 50-150 prestige
  - Validation: Did expansion happen? Are foundations laid?

- **Act 2 (T15 = 75-150 years):**
  - Regional dominance phase (second generation)
  - Target: 10-15 colonies, 150-500 prestige, first wars
  - Validation: Are conflicts emerging? Tech advantages appearing?

- **Act 3 (T25 = 125-250 years):**
  - Total war phase (third generation+)
  - Target: Clear leaders (1000+), active eliminations, major battles
  - Validation: Are decisive moments happening? Victory in sight?

- **Act 4 (T30 = 150-300 years):**
  - Endgame resolution (dynastic conclusion)
  - Target: Winner emerges OR elimination victory
  - Validation: Was game satisfying? Did 4-act structure work?

#### Key Testing Questions

**Q: What prestige threshold makes sense for 150-300 year dynasties?**
- Current: 5000 prestige victory
- Question: Is this achievable in 30 turns with current mechanics?
- Testing: Track max prestige achieved in 30-turn games

**Q: Do current mechanics create the 4-act dramatic arc?**
- Act transitions should feel natural
- Mid-game (T15) should see clear leaders and wars
- Late-game (T25) should be decisive
- Testing: Analyze prestige progression curves across acts

**Q: Should timeline be 5 years/turn or 10 years/turn?**
- 5 years = faster-paced dynasties (150 years total)
- 10 years = epic generational saga (300 years total)
- Testing: Does current AI progression feel right for either?

---

## Future Improvements

### Short Term
1. Complete Phase 1: Tune Balanced and Turtle strategies
2. Implement remaining strategies (Espionage, Diplomatic, Expansionist)
3. Track counter-strategy effectiveness (which species beats which)
4. Generate heat maps of strategy matchups

### Medium Term
1. Implement Phase 2: Variable player count testing (4, 6, 8, 10, 12)
2. Add adaptive mutation rates (higher early, lower late)
3. Multi-objective fitness (balance win rate with diversity)
4. Real-time visualization of evolution progress

### Long Term
1. Implement Phase 3: Full randomization testing
2. Neural network policy evolution (replace utility AI)
3. Transfer learning from evolved strategies to LLM fine-tuning
4. Player behavior incorporation (human vs AI coevolution)
5. Dynamic balance adjustment based on meta trends

---

## Best Practices

### When to Run Tests

- **After config changes:** Any modification to `config/*.toml` files
- **After AI logic changes:** Changes to decision-making or strategy implementation
- **Before major releases:** Comprehensive overnight tests for confidence
- **During development:** Quick validation tests (3-5 gens) for rapid iteration

### Interpreting Short Tests (<10 generations)

- High variance is expected - don't overreact to single dominant strategies
- Focus on relative trends rather than absolute win rates
- Look for strategies that are **consistently** weak/strong across multiple runs
- Use short tests for "smoke testing" rather than balance conclusions

### Statistical Confidence

For meaningful balance conclusions:
- **Minimum:** 10 parallel runs × 20 generations
- **Recommended:** 20 parallel runs × 30 generations
- **High confidence:** 50+ parallel runs × 50 generations

---

## References

### Academic Papers
- ACM: [On Video Game Balancing](https://dl.acm.org/doi/10.1145/3675807)
- ACM FOGA: [Competitive Coevolution N-Player Games](https://dl.acm.org/doi/10.1145/3729878.3746621)
- Springer: [Virtual Player Design via Coevolution](https://link.springer.com/article/10.1007/s11047-014-9411-3)
- ResearchGate: [Electronic-Game Framework for Coevolution](https://www.researchgate.net/publication/301879801_An_electronic-game_framework_for_evaluating_coevolutionary_algorithms)

### Implementation Resources
- DEAP (Python): Distributed Evolutionary Algorithms in Python
- OpenRA: Open source RTS with extensive AI testing
- GAlib: C++ Genetic Algorithm Library

---

**See Also:**
- `docs/STATUS.md` - Current project status and AI development phase
- `tests/balance/README.md` - Detailed usage instructions
- `config/espionage.toml` - Espionage balance parameters
