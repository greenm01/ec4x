# EC4X Testing Documentation

## Overview

EC4X uses comprehensive testing across multiple levels: unit tests, integration tests, balance testing, and AI optimization.

**Testing Philosophy:** "You don't know what you don't know until you observe it" - comprehensive metrics catch emergent behaviors.

---

## Documentation Structure

- **[BALANCE_METHODOLOGY.md](BALANCE_METHODOLOGY.md)** - Balance testing approach (regression)
- **[DIAGNOSTICS.md](DIAGNOSTICS.md)** - Unknown-unknowns detection (coming soon)

**AI Tuning:** See `../../tools/ai_tuning/USAGE.md` (optimization, not testing)

---

## Testing Levels

### 1. Unit Tests (Planned)
**Purpose:** Test individual functions in isolation

**Location:** `tests/unit/`

**Status:** Not yet implemented (engine-first development)

---

### 2. Integration Tests
**Purpose:** Verify engine systems work together correctly

**Location:** `tests/`

**Run:** `nimble test`

**Coverage:** 101+ tests covering:
- Core game state
- Combat resolution
- Economy (production, income, maintenance)
- Research advancement
- Diplomacy engine
- Espionage mechanics
- Victory conditions
- Fog-of-war filtering

---

### 3. Balance Testing (Regression)
**Purpose:** Validate AI strategies work correctly with fixed personalities

**Location:** `tests/balance/`

**What it tests:**
- 12 predefined AI strategies function correctly
- 4-act game progression (7/15/25/30 turns)
- Engine stability across different configurations
- No crashes, hangs, or broken mechanics

**Quick Commands:**
```bash
nimble testBalanceQuick        # 20 games, 7 turns (~10s)
nimble testBalanceAct1         # 100 games, Act 1
nimble testBalanceAct2         # 100 games, Act 2
nimble testBalanceAct3         # 100 games, Act 3
nimble testBalanceAct4         # 100 games, Act 4
nimble testBalanceAll4Acts     # 400 games, all 4 acts
```

**Output:**
- `balance_results/diagnostics/game_*.csv` - Per-turn metrics
- `balance_results/simulation_reports/` - JSON snapshots
- Git hash verification (prevents stale binaries)

**See:** [BALANCE_METHODOLOGY.md](BALANCE_METHODOLOGY.md)

---

### 4. AI Tuning (Optimization)
**Purpose:** Find optimal AI personalities and expose balance exploits

**Location:** `tools/ai_tuning/`

**What it finds:**
- Dominant strategies (balance issues)
- Weak strategies (underpowered mechanics)
- Parameter sweet spots via evolution
- Emergent exploits

**Quick Commands:**
```bash
nimble buildAITuning          # Build GA tools
nimble evolveAIQuick          # 10 gen test (~5 min)
nimble evolveAI               # 50 gen full run (~2-4 hours)
nimble coevolveAI             # Competitive co-evolution
nimble tuneAIDiagnostics      # 100 games + analysis
```

**Not Testing:** This is a *development tool* for optimization, not regression testing.

**See:** `../../tools/ai_tuning/USAGE.md`

---

## Testing Workflow

### Standard Development Cycle

```bash
# 1. Make changes to engine/AI
vim src/engine/combat/cer.nim

# 2. Run unit tests (when available)
# nimble testUnit

# 3. Run integration tests
nimble test                   # Must pass before commit

# 4. Run balance quick check (if AI/balance code changed)
nimble testBalanceQuick       # Catches obvious breaks

# 5. Commit (pre-commit hook runs tests again)
git commit -m "..."
```

### Balance Testing Cycle

**When to run:**
- After major game mechanic changes
- After AI modifications
- Before releases
- Weekly validation

**Workflow:**
```bash
# 1. Quick validation (catches 90% of issues)
nimble testBalanceQuick       # 20 games, ~10s

# 2. If suspicious, run full act tests
nimble testBalanceAct1        # 100 games, Act 1
nimble testBalanceAct2        # 100 games, Act 2

# 3. If still suspicious, unknown-unknowns detection
nimble testUnknownUnknowns    # 200 games + analysis
nimble analyzeDiagnostics     # Phase 2 gaps

# 4. If anomalies found, investigate with diagnostics
python3 tools/ai_tuning/analyze_phase2_gaps.py
python3 tools/ai_tuning/analyze_4act_progression.py
```

### AI Optimization Cycle

**When to run:**
- During balance passes
- After major mechanic additions
- When suspecting exploits
- Before major releases

**Workflow:**
```bash
# 1. Quick GA test (verify setup)
nimble evolveAIQuick          # 10 gen, ~5 min

# 2. Full evolution (find optimal strategies)
nimble evolveAI               # 50 gen, ~2-4 hours

# 3. Competitive co-evolution (expose exploits)
nimble coevolveAI             # 4 species, 20 gen

# 4. Analyze results
cat balance_results/evolution/final_results.json
# Look for: dominant strategies, fitness plateaus, exploits
```

---

## Testing Philosophy

### Unknown-Unknowns Detection

> "You don't know what you don't know until you observe it."

Complex systems exhibit emergent behaviors. Comprehensive metrics catch them.

**Approach:**
1. Track EVERYTHING that affects gameplay
2. Run 100+ games → CSV diagnostics
3. Analyze with Polars (Python) → Find anomalies
4. Formulate hypotheses → Add targeted logging
5. Fix → Regression test with nimble

**Key Metrics** (see `tests/balance/diagnostics.nim`):
```nim
- Orders submitted/rejected (catches AI failures)
- Build queue depth (catches construction stalls)
- Ships commissioned (catches production bugs)
- Fleet movement (catches stuck fleets)
- ETAC activity (catches expansion failures)
- Combat engagements (catches combat bugs)
- Espionage missions (catches intel failures)
```

**Example Bug Caught:**
- **"Brain-Dead AI" (2025-11-25)**: AIs built fighters but never used them
- **Detection**: `fighters_built > 0 && combat_engagements == 0` for 15+ turns
- **Root cause**: Scout build conditions checked aggression >= 0.4, fighter logic missing
- **Fix**: Added fighter build logic to ai_controller.nim:1145

---

## Test Output

### Balance Testing Output

**Directory:** `balance_results/`

```
balance_results/
├── diagnostics/
│   ├── game_001.csv          # Per-turn metrics
│   ├── game_002.csv
│   └── ...
└── simulation_reports/
    ├── game_001_final.json   # Final state
    ├── game_001_turn_01.json # Turn snapshots
    └── ...
```

**CSV Format** (42+ columns):
```csv
turn,house,treasury,production,prestige,colony_count,fleet_count,...
1,house-atreides,500,120,5,3,2,...
2,house-atreides,480,125,6,3,3,...
```

**JSON Format:**
```json
{
  "turn": 30,
  "houses": { ... },
  "colonies": { ... },
  "fleets": { ... },
  "winner": "house-atreides",
  "victoryType": "prestige",
  "finalPrestige": 342
}
```

### AI Tuning Output

**Directory:** `balance_results/evolution/` or `balance_results/coevolution/`

**Evolution Results:**
```json
{
  "config": { "populationSize": 20, "numGenerations": 50, ... },
  "generations": [
    {
      "generation": 0,
      "bestFitness": 0.453,
      "avgFitness": 0.234,
      "dominantStrategy": "Aggressive",
      "bestIndividual": {
        "id": 42,
        "genes": { "aggression": 0.85, ... }
      }
    }
  ]
}
```

---

## Performance & Scale

### Integration Tests
- **Runtime:** ~2-5 seconds total
- **Frequency:** Every commit (pre-commit hook)
- **Coverage:** 101+ tests

### Balance Testing Quick
- **Runtime:** ~10 seconds (20 games, 7 turns)
- **Frequency:** After balance changes
- **Games:** 20 games, 4 players each

### Balance Testing Full
- **Runtime:** ~5-10 minutes per act (100 games)
- **Frequency:** Weekly, before releases
- **Games:** 400 games total (4 acts × 100 games)

### AI Optimization
- **Runtime:** ~2-4 hours (50 generations)
- **Frequency:** During balance passes
- **Games:** 1,000+ games total (50 gen × 20 pop × 1 game/individual)

### Hardware Recommendations
- **Minimum:** 4-core CPU, 8GB RAM
- **Recommended:** 16-core CPU, 16GB RAM (for parallel testing)
- **Optimal:** 32-core CPU, 32GB RAM (for large-scale evolution)

---

## Continuous Integration (Future)

### Planned CI Pipeline

```yaml
on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - run: nimble test

  balance-quick:
    runs-on: ubuntu-latest
    steps:
      - run: nimble testBalanceQuick

  balance-full:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - run: nimble testBalanceAll4Acts
```

**Status:** Not yet implemented (manual testing for now)

---

## Troubleshooting

### Common Issues

**Problem:** Tests fail with "command not found: python3"
- **Fix:** Install Python 3.8+ or use `python` instead of `python3`

**Problem:** Balance tests produce stale binaries
- **Fix:** `nimble cleanBalance && nimble buildBalance`
- **Note:** Nimble tasks use `--forceBuild` to prevent this

**Problem:** CSV analysis fails with import errors
- **Fix:** `pip install polars pandas` (Python dependencies)

**Problem:** Evolution takes forever
- **Fix:** Use `nimble evolveAIQuick` for testing, or reduce population/generations

**Problem:** Git hash mismatch warning
- **Fix:** Recompile with `nimble buildBalance` (ensures binary matches source)

---

## See Also

- [BALANCE_METHODOLOGY.md](BALANCE_METHODOLOGY.md) - Balance testing details
- `../ai/README.md` - AI system documentation
- `../../tools/ai_tuning/USAGE.md` - AI optimization tools
- `../../tests/balance/README.md` - Balance testing implementation
- `../../ec4x.nimble` - All available nimble tasks
