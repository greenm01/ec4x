# AI Tuning Tools - Usage Guide

## Overview

Tools for optimizing EC4X AI personalities using genetic algorithms and competitive co-evolution.

**Location:** `tools/ai_tuning/`

**Purpose:** Find optimal AI strategies and expose game balance exploits

---

## Quick Start

### 1. Build the tools
```bash
nimble buildAITuning
```

This compiles:
- `tools/ai_tuning/bin/genetic_ai` - Core GA library
- `tools/ai_tuning/bin/evolve_ai` - Evolution runner
- `tools/ai_tuning/bin/coevolution` - Co-evolution framework

### 2. Run a quick evolution test
```bash
nimble evolveAIQuick
```

Runs 10 generations with 10 individuals (takes ~5-10 minutes).

### 3. Check results
```bash
ls -lh balance_results/evolution/
cat balance_results/evolution/final_results.json
```

---

## Available Tasks

### Core Tasks

**`nimble buildAITuning`**
- Builds all AI tuning binaries
- Output: `tools/ai_tuning/bin/{genetic_ai,evolve_ai,coevolution}`

**`nimble evolveAI`**
- Full evolution run: 50 generations, 20 population
- Takes ~2-4 hours on 16-core CPU
- Discovers optimal AI personality parameters
- Output: `balance_results/evolution/`

**`nimble evolveAIQuick`**
- Quick test: 10 generations, 10 population
- Takes ~5-10 minutes
- Good for testing GA setup

**`nimble coevolveAI`**
- Competitive co-evolution with 4 species
- 20 generations, species compete against each other
- Exposes balance exploits faster than standard evolution
- Output: `balance_results/coevolution/`

**`nimble tuneAIDiagnostics`**
- Runs 100 games with full diagnostic CSV output
- Analyzes Phase 2 gaps (scouts, fighters, espionage)
- Analyzes 4-act progression
- Combines testing + analysis in one command

**`nimble cleanAITuning`**
- Removes all binaries and results
- Clean slate for new runs

---

## Manual Usage

### Evolution with custom parameters
```bash
tools/ai_tuning/bin/evolve_ai --generations 100 --population 30 --games 8
```

**Parameters:**
- `--generations N` - How many generations to evolve (default: 50)
- `--population N` - Population size (default: 20)
- `--games N` - Games per AI per generation (default: 4)

### Co-evolution
```bash
tools/ai_tuning/bin/coevolution
```

No parameters - uses hardcoded defaults from coevolution.nim.

### Analysis only
```bash
python3 tools/ai_tuning/analyze_phase2_gaps.py
python3 tools/ai_tuning/analyze_4act_progression.py
```

Requires existing CSV files in `balance_results/diagnostics/`.

---

## Understanding Results

### Evolution Output

**`balance_results/evolution/final_results.json`**
```json
{
  "config": {...},
  "generations": [
    {
      "stats": {
        "generation": 0,
        "bestFitness": 0.453,
        "avgFitness": 0.234,
        "dominantStrategy": "Aggressive"
      },
      "bestIndividual": {
        "id": 42,
        "fitness": 0.453,
        "genes": {
          "aggression": 0.85,
          "riskTolerance": 0.72,
          "economicFocus": 0.23,
          "expansionDrive": 0.67,
          "diplomacyValue": 0.12,
          "techPriority": 0.34
        }
      }
    }
  ]
}
```

**Key metrics:**
- `bestFitness` - Highest fitness in generation (0.0-1.0+)
- `avgFitness` - Population average
- `dominantStrategy` - Which archetype won most

**Red flags:**
- Fitness plateaus early (premature convergence)
- One strategy dominates all generations (balance issue)
- Fitness > 0.9 consistently (possible exploit found)

### Co-evolution Output

**`balance_results/coevolution/generation_XX.json`**

Shows which species won each game and how species evolved to counter each other.

**Expected:** Cyclical dynamics (rock-paper-scissors)
**Red flag:** One species consistently dominates (balance exploit)

---

## Integration with Balance Testing

AI tuning complements but doesn't replace balance testing:

| Tool | Purpose | When to Run |
|------|---------|-------------|
| `nimble testBalance*` | Regression testing | After engine changes |
| `nimble evolveAI` | Find optimal strategies | During balance passes |
| `nimble coevolveAI` | Find exploits | After major mechanic changes |

**Workflow:**
1. Make mechanic change
2. Run `nimble testBalanceQuick` - verify no crashes
3. Run `nimble evolveAIQuick` - check for obvious exploits
4. If suspicious, run full `nimble coevolveAI`

---

## Technical Details

### Genetic Algorithm

- **Selection:** Tournament selection (size=3)
- **Crossover:** Blend crossover (70% rate)
- **Mutation:** Gaussian noise (15% rate, σ=0.1)
- **Elitism:** Top 2 preserved unchanged

### Fitness Function

```nim
fitness = (
  winRate * 0.40 +           # 40% - winning games
  (avgPrestige/1000) * 0.40 + # 40% - prestige (victory condition)
  (avgColonies/10) * 0.10 +   # 10% - expansion
  (avgMilitary/100) * 0.10    # 10% - military strength
)
```

### Co-evolution Species

1. **Economy** - Growth focus, low aggression
2. **Military** - High aggression, combat focus
3. **Diplomacy** - Pact formation, peaceful
4. **Technology** - Research priority, long-term

Each species evolves independently but competes in mixed games.

---

## Troubleshooting

**Problem:** Evolution stuck at low fitness (~0.2)
- **Fix:** Increase population size or mutation rate
- Check if game is actually winnable in 100 turns

**Problem:** All strategies converge to same personality
- **Fix:** Increase mutation rate or reduce elitism
- May indicate only one viable strategy (balance issue!)

**Problem:** Compilation errors
- **Fix:** `nimble clean && nimble buildAITuning`
- Check that `tests/balance/ai_controller.nim` compiles

**Problem:** Python script errors
- **Fix:** Ensure balance_results/diagnostics/ has CSV files
- Run `nimble testBalanceDiagnostics` first to generate data

---

## Performance Tips

**Parallel execution:**
- Evolution runs games sequentially (single-threaded)
- Use `run_parallel_diagnostics.py` for parallel game batches
- Co-evolution runs 4-player games (bottleneck: game engine)

**Optimization:**
- Release builds only: `-d:release --opt:speed`
- Use `--games 2` for quick experiments
- Full runs need `--games 4+` for stable fitness

**Hardware:**
- 16-core CPU: ~2 hours for 50 gen evolution
- 8-core CPU: ~4 hours
- 4-core CPU: ~8+ hours (not recommended)

---

## See Also

- [README.md](README.md) - Tool overview
- [../../docs/BALANCE_TESTING_METHODOLOGY.md](../../docs/BALANCE_TESTING_METHODOLOGY.md) - Academic foundation
- [../../docs/AI_DECISION_FRAMEWORK.md](../../docs/AI_DECISION_FRAMEWORK.md) - AI architecture
