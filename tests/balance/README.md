# EC4X Balance Testing Framework

AI-powered game balance testing system that simulates full games and generates structured data for analysis.

## ⭐ ONE SOURCE OF TRUTH - Nimble Task Workflow ⭐

**ALWAYS use nimble tasks for balance testing to ensure build/test alignment:**

### Standard Balance Tests

```bash
# Quick validation during development (7 turns, 20 games, ~10 seconds)
nimble testBalanceQuick

# Build only (without running tests)
nimble buildBalance

# Clean all balance test artifacts
nimble cleanBalance
```

### 4-Act Structure Testing

```bash
# Individual act validation (100 games each)
nimble testBalanceAct1    # Act 1: Land Grab (7 turns)
nimble testBalanceAct2    # Act 2: Rising Tensions (15 turns)
nimble testBalanceAct3    # Act 3: Total War (25 turns)
nimble testBalanceAct4    # Act 4: Endgame (30 turns)

# Test all 4 acts in sequence (400 games total, ~15 minutes)
nimble testBalanceAll4Acts
```

### Unknown-Unknowns Detection (Phase 2 RBA / Phase 3 NNA)

```bash
# Unknown-unknowns detection suite (200 games with auto-analysis)
nimble testUnknownUnknowns

# Diagnostic tests with CSV output (50 games, 30 turns)
nimble testBalanceDiagnostics

# Analyze existing diagnostic CSV files
nimble analyzeDiagnostics

# Analyze 4-act progression patterns
nimble analyzeProgression
```

### Stress Testing

```bash
# AI behavior stress test (1000 games, identifies edge cases)
nimble testStressAI

# Engine stability stress test (100k games, crash detection)
nimble testStress

# Map size scaling tests (4, 8, 12 players)
nimble testMapSizes
```

### Why This Matters - Regression Testing Safeguards

The nimble task workflow ensures:
- ✅ **No Stale Binaries**: Uses `--forceBuild` flag - ALWAYS full recompilation
- ✅ **Git Hash Tracking**: Records git hash to `.build_git_hash` for traceability
- ✅ **Build Alignment**: Source code → Binary always in sync
- ✅ **Regression Safety**: Binary matches current code, not old cached version
- ✅ **Consistent Results**: Repeatable testing workflow
- ✅ **Cross-Platform**: Works on Linux, macOS, Windows
- ✅ **Fast Development Cycle**: Quick task for rapid iteration

**The Stale Binary Problem (SOLVED):**
Previously, running tests with old binaries caused hours of confusion:
- AI appeared to ignore code changes
- Test results didn't match expectations
- Log analysis showed outdated behavior

**Now:** Every nimble task uses `nim c --forceBuild` + git hash tracking.
You'll see: `Git hash: abc1234` in output - verify it matches `git rev-parse --short HEAD`

### Task Definitions (from ec4x.nimble)

```nim
task buildBalance, "Build balance test simulation binary":
  exec "nim c -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"

task testBalanceQuick, "Quick balance validation (7 turns, 20 games)":
  exec "nim c -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "python3 run_balance_test_parallel.py --workers 8 --games 20 --turns 7"

task testBalance, "Run balance tests (7 turn Act 1 validation)":
  exec "nim c -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "python3 run_balance_test_parallel.py --workers 16 --games 100 --turns 7"

task testBalanceAct2, "Run Act 2 balance tests (15 turns)":
  exec "nim c -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "python3 run_balance_test_parallel.py --workers 16 --games 100 --turns 15"

task testBalanceFull, "Run full game balance tests (30 turns)":
  exec "nim c -d:release --opt:speed -o:tests/balance/run_simulation tests/balance/run_simulation.nim"
  exec "python3 run_balance_test_parallel.py --workers 16 --games 100 --turns 30"

task cleanBalance, "Clean balance test artifacts":
  exec "rm -f tests/balance/run_simulation"
  exec "rm -rf balance_results/*"
```

### Alternative Testing Approaches

EC4X uses **two complementary testing methodologies**:

#### 1. Fixed Strategy Testing (Current - Phase 2)
**Purpose:** Validate game balance with fixed AI strategies (Act-by-Act analysis)

**Primary tool:** Nimble tasks (see above)

**Manual single-game testing:**
```bash
# Build first, then run simulation directly with custom parameters
nimble buildBalance
./tests/balance/run_simulation 30 88888 4 4  # 30 turns, seed 88888, 4 rings, 4 players
```

**Custom multi-game configurations:**
```bash
# Call Python directly for non-standard parameters
python3 run_balance_test_parallel.py --workers 32 --games 500 --turns 25
```

#### 2. Genetic Coevolution Testing
**Purpose:** Evolve AI personalities through competitive coevolution

**Shell scripts for genetic algorithm testing:**
- `./tests/balance/run_parallel_test.sh` - Run coevolution experiments
- `./tests/balance/archive_results.sh` - Archive coevolution results

**Example coevolution test:**
```bash
# 4 parallel runs, 10 generations, 8 population, 5 games/gen
./tests/balance/run_parallel_test.sh 4 10 8 5
```

See `docs/BALANCE_TESTING_METHODOLOGY.md` for full details on both approaches.

## Overview

This framework enables data-driven balance testing by:
1. Simulating complete games with various AI strategies
2. Capturing detailed metrics at every turn
3. Exporting structured JSON for AI analysis
4. Receiving specific config recommendations
5. Iterating until balance is achieved

## Architecture

```
balance_framework.nim      # Core framework (JSON schema, capture, export)
test_strategy_balance.nim  # Strategy comparison tests
AI_ANALYSIS_PROMPT.md      # Template for AI analysis
balance_results/           # Generated JSON files (gitignored)
```

## Quick Start

### 1. Run Balance Tests

```bash
# Compile and run strategy balance tests
nim c -r tests/balance/test_strategy_balance.nim

# Creates JSON files in balance_results/
```

### 2. Analyze Results with AI

```bash
# Copy AI_ANALYSIS_PROMPT.md content
# Attach balance_results/test_name.json
# Ask AI to analyze the data
```

### 3. Implement Recommendations

```bash
# AI will suggest specific config changes like:
# config/espionage.toml: tech_theft.srp_percentage = 20 → 30

# Edit config files
vim config/espionage.toml

# Sync specs from config
python3 scripts/sync_specs.py
```

### 4. Verify Improvements

```bash
# Re-run tests
nim c -r tests/balance/test_strategy_balance.nim

# Compare new results to previous
# Iterate until balanced
```

## JSON Output Structure

Each balance test generates a comprehensive JSON file with:

### Metadata
- Test ID, timestamp, engine version
- Test configuration (houses, turns, strategies)
- Execution time

### Turn Snapshots
- Complete game state for each turn
- Per-house metrics:
  - Prestige, treasury, economy (GCO/NCV)
  - Fleet strength, colony count
  - Tech levels, morale
  - Cumulative statistics
- Event logs:
  - Combat: battles, losses, victories
  - Economic: colonization, construction, tax changes
  - Diplomatic: pacts, violations, status changes
  - Espionage: actions, successes, detections

### Game Outcome
- Victor, victory type, victory turn
- Final rankings with detailed stats
- Peak performance metrics

### Aggregate Metrics
- Game length distribution
- Win rate by strategy
- Economic growth curves
- Combat frequency
- Espionage effectiveness
- Balance indicators:
  - Prestige volatility
  - Leader changes
  - Comeback rate
  - Domination frequency
  - Competitiveness score

## Test Scenarios

### Military vs Economic
Tests if aggressive military and patient economic strategies are balanced.

**Participants**: 2x Aggressive, 2x Economic
**Duration**: 100 turns
**Focus**: Early military vs late economic power

### All Strategies
Comprehensive test of all 7 AI strategies in direct competition.

**Participants**: All strategies (7 houses)
**Duration**: 150 turns
**Focus**: Strategic diversity and counter-play

### Early Aggression
Tests if rush strategies are too strong or too weak.

**Participants**: Aggressive, Turtle, Balanced
**Duration**: 50 turns
**Focus**: Timing windows and defensive viability

## AI Strategies

The framework supports 7 distinct AI personalities:

| Strategy | Aggression | Economic Focus | Expansion | Description |
|----------|-----------|----------------|-----------|-------------|
| Aggressive | 0.9 | 0.3 | 0.7 | Heavy military, early attacks |
| Economic | 0.2 | 0.9 | 0.5 | Growth and tech focused |
| Espionage | 0.5 | 0.5 | 0.4 | Intelligence and sabotage |
| Diplomatic | 0.3 | 0.6 | 0.5 | Pacts and manipulation |
| Balanced | 0.5 | 0.5 | 0.5 | Mixed approach |
| Turtle | 0.1 | 0.7 | 0.2 | Defensive consolidation |
| Expansionist | 0.6 | 0.4 | 0.95 | Rapid colonization |

## Balance Criteria

### Strategic Viability
✅ **Good**: All strategies win 20-40% of games
❌ **Bad**: One strategy wins >60% or <10%

### Game Dynamics
✅ **Good**: Leadership changes 3-7 times
❌ **Bad**: Turn 20 leader wins 90%+ of games

### Comeback Potential
✅ **Good**: Houses recover from -500 prestige
❌ **Bad**: Last at turn 30 = eliminated by turn 50

### Victory Diversity
✅ **Good**: Prestige, military, and economic paths all viable
❌ **Bad**: Only one victory type achieved

### Competitive Games
✅ **Good**: Close finishes, multiple contenders
❌ **Bad**: Runaway leaders, early stalemates

## Example AI Analysis

```json
{
  "summary": "Military rush dominates early game, economic strategies non-viable",
  "concerns": [
    {
      "severity": "high",
      "category": "strategy",
      "issue": "Aggressive AI wins 65% of games",
      "evidence": "Average victory turn 45, Economic AI eliminated by turn 60 in 80% of losses",
      "impact": "Game becomes pure military race, strategic diversity lost"
    }
  ],
  "recommendations": [
    {
      "priority": "high",
      "config_file": "config/military.toml",
      "parameter": "ships.fighter.build_cost",
      "current_value": 10,
      "suggested_value": 15,
      "rationale": "Slow early military timing, give economic players defensive window",
      "expected_impact": "Rush delayed ~10 turns, economic strategies viable"
    }
  ]
}
```

## Adding New Tests

### 1. Define Test Configuration

```nim
let config = BalanceTestConfig(
  testName: "your_test_name",
  description: "What this test evaluates",
  numberOfHouses: 4,
  numberOfTurns: 100,
  mapSize: 50,
  startingConditions: "equal",
  aiStrategies: @["Strategy1", "Strategy2"],
  tags: @["category", "focus-area"]
)
```

### 2. Create Initial State

```nim
let initialState = createStandardTestGame(4, @[
  AIStrategy.YourStrategy1,
  AIStrategy.YourStrategy2,
  AIStrategy.YourStrategy3,
  AIStrategy.YourStrategy4
])
```

### 3. Run Test

```nim
let result = runBalanceTest(config, initialState)
exportBalanceTest(result, "balance_results/your_test.json")
```

## Current Status

**Framework**: ✅ Complete
**AI Strategies**: ⏳ In Progress (order generation TODO)
**Test Scenarios**: ⏳ In Progress (game initialization TODO)
**AI Analysis**: ✅ Prompt template ready

## Next Steps

1. **Complete AI order generation** - Implement full logic for all strategies
2. **Implement game initialization** - Create balanced starting conditions
3. **Run first test suite** - Generate initial balance data
4. **AI analysis iteration** - Feed JSON to Claude/GPT, implement recommendations
5. **Balance verification** - Re-test until criteria met

## Files

- `balance_framework.nim` - Core framework (490 lines)
- `test_strategy_balance.nim` - Strategy tests (360 lines)
- `AI_ANALYSIS_PROMPT.md` - AI analysis template (330 lines)
- `README.md` - This file

## Dependencies

- EC4X engine modules (gamestate, resolve, orders)
- Nim standard library (json, tables, times)
- Python 3.x for spec sync (optional)

## Configuration

All game balance parameters are in `config/*.toml` files:
- `config/military.toml` - Unit costs, salvage
- `config/economy.toml` - Production, taxes, research
- `config/espionage.toml` - Action costs, detection
- `config/prestige.toml` - Prestige sources, morale
- `config/combat.toml` - Combat mechanics
- Plus 8 more config files with 2000+ parameters

## Notes

- JSON files can be large (10-100 MB for long games)
- Balance results are gitignored (use for analysis only)
- AI recommendations are specific to config parameters
- Iterative process: test → analyze → adjust → repeat
- Target: 80-120 turn competitive games with 20-40% win rates for all strategies

---

**Ready to start balance testing!**

Once AI order generation is complete, we can run the first suite and begin data-driven balance iteration.
