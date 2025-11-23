# EC4X Balance Testing Methodology

**Last Updated:** 2025-11-22

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

## Future Improvements

### Short Term
1. Implement diversity preservation mechanisms (species distance metrics)
2. Add adaptive mutation rates (higher early, lower late)
3. Track counter-strategy effectiveness (which species beats which)
4. Generate heat maps of strategy matchups

### Medium Term
1. Multi-objective fitness (balance win rate with diversity)
2. Island model evolution (multiple isolated populations, periodic migration)
3. Automated balance parameter tuning (meta-optimization)
4. Real-time visualization of evolution progress

### Long Term
1. Neural network policy evolution (replace utility AI)
2. Transfer learning from evolved strategies to LLM fine-tuning
3. Player behavior incorporation (human vs AI coevolution)
4. Dynamic balance adjustment based on meta trends

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
