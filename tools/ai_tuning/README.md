# AI Tuning Tools

Tools for optimizing and analyzing EC4X AI personalities.

## Genetic Algorithm Tools

### `genetic_ai.nim`
Core genetic algorithm operations for evolving AI personalities:
- Crossover: Breed two personalities
- Mutation: Random trait adjustments
- Tournament selection
- Fitness evaluation

### `evolve_ai.nim`
Evolution runner that runs GA across multiple generations:
```bash
nim c -r tools/ai_tuning/evolve_ai.nim --generations 50 --population 20
```

Evolves AI personalities to find optimal strategies.

### `coevolution.nim`
Competitive co-evolution system with 4 species:
- Economy specialists
- Military specialists
- Diplomacy specialists
- Technology specialists

Each species evolves to counter the others, creating arms race dynamics that expose balance issues.

```bash
nim c -r tools/ai_tuning/coevolution.nim
```

## Analysis Scripts

### `analyze_4act_progression.py`
Analyzes game progression through 4 acts (turns 7/15/25/30).

### `analyze_diagnostics.py`
Analyzes diagnostic CSV data for balance issues.

### `analyze_phase2_gaps.py`
Identifies gaps in Phase 2 AI implementation (fighters, scouts, espionage, etc.).

### `run_parallel_diagnostics.py`
Runs batch simulations in parallel for diagnostic data collection:
```bash
python3 tools/ai_tuning/run_parallel_diagnostics.py 100 30 16
# Args: games, turns, workers
```

## Usage

All tools import from `tests/balance/` for:
- `ai_controller.nim` - AI implementation
- `game_setup.nim` - Test game configuration
- `run_simulation.nim` - Simulation runner

## Output

- **Evolution results:** `evolution_results/`
- **Diagnostic CSVs:** `balance_results/diagnostics/`
- **Analysis reports:** Console output

## Purpose

These tools are for **development and optimization**, not automated testing.
They help discover:
- Optimal AI personality parameters
- Balance exploits
- Strategy dominance
- Performance bottlenecks
