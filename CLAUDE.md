# EC4X Development Context for Claude

**Load at session start:** `@CLAUDE.md` `@docs/TODO.md` `@docs/STYLE_GUIDE.md`

*Note: File lives at project root as `CLAUDE.md` - the `@` is Claude's reference syntax, not part of filename*

---

## Critical Rules

1. **All enums MUST be `{.pure.}`** (NEP-1 requirement)
2. **No hardcoded values** - use TOML configs
3. **Follow DRY** (Don't Repeat Yourself) - check existing patterns before duplicating
4. **Follow DoD** (Data-Oriented Design) - see patterns below
5. **Use `std/logging`** - NOT echo (disappears in release builds)
6. **Engine respects fog-of-war** - use `house.intelligence`, not omniscient state
7. **Max 7 .md files in /docs root** - archive old docs to `/docs/archive/[date]/`
8. **80 character line limit** - break long lines naturally (NEP-1)
9. **2-space indentation** - consistent formatting (NEP-1)
10. **Spaces around operators** - `let total = value + modifier * 2`

The src tree API is located in docs/api/api.json for efficient context.

---

## Design Patterns (DRY & DoD)

### DRY (Don't Repeat Yourself)

**Before writing new code:**
1. Search for similar functionality in existing modules
2. Extract common patterns into shared utilities
3. Reuse existing types and interfaces

**Common patterns to reuse:**
- Table iteration: `for id, entity in table.pairs`
- Filtering with fog-of-war: `createFogOfWarView(game, houseId)`
- Config loading: Use existing `global*Config` patterns
- Diagnostic collection: Follow `diagnostics.nim` patterns

### DoD (Data-Oriented Design)

**Core principle:** Separate data from behavior, use tables for entity management.

**EC4X follows strict DoD patterns:**

```nim
# ✅ GOOD - DoD pattern
type GameState = object
  houses: Table[HouseId, House]
  fleets: Table[FleetId, Fleet]
  colonies: Table[SystemId, Colony]

proc processFleets(game: var GameState) =
  for fleetId, fleet in game.fleets.mpairs:
    # Process fleet
```

```nim
# ❌ BAD - OOP pattern (don't do this)
type Fleet = object
  id: FleetId
  ships: seq[Ship]
  
method move(self: var Fleet) =
  # Don't use methods/inheritance
```

**DoD Guidelines:**
- Use `Table[Id, Entity]` for all game entities
- Keep data structures flat and cache-friendly
- Separate data (types) from logic (procs)
- Pass `GameState` by reference, mutate in place
- Avoid deep nesting and pointer chasing
- Use value types where possible (not ref objects)

**Benefits in EC4X:**
- Efficient iteration over entities
- Easy serialization/deserialization
- Clear data ownership
- Better cache locality
- Easier to reason about state changes

---

## Current Focus: RBA AI Bug Fixes

**Priority:** Get RBA fully functional before GOAP integration.

**Planned Architecture:** Hybrid GOAP/RBA system
- GOAP: Strategic planning (long-term goals, resource allocation)
- RBA: Tactical execution (fleet operations, combat decisions)

**Current Work:** RBA has bugs preventing proper functionality. Using diagnostic-driven approach to identify and fix issues.

### Quick Development Loop

```bash
# 1. Build simulation (includes git hash)
nimble buildSimulation 2>&1 | tail -10

# 2. Test single game with specific seed
./bin/run_simulation --seed 12345
# Or with short flag: ./bin/run_simulation -s 12345
# Output: balance_results/diagnostics/game_12345.csv

# 3. Test with custom parameters
./bin/run_simulation -s 12345 --fixed-turns --turns 35 --players 4

# 3. Batch test (20 games, 7 turns, ~10 seconds)
python3.11 scripts/run_balance_test_parallel.py --workers 8 --games 20 --turns 35
# Seeds are auto-generated based on game number

# 4. Analyze with Python + polars
python3.11 scripts/analysis/your_script.py  # Use python3.11 for polars
```

### Why This Workflow?

- **Python for analysis:** Dynamic, iterate on queries without recompiling
- **Polars over pandas:** 10-50x faster on large CSVs (multi-GB files)
- **Throwaway scripts:** Write quick queries, get answers, move on
- **Git hash tracking:** `nimble buildSimulation` writes to `bin/.build_git_hash`
- **Reproducible seeds:** Each game gets unique seed, stored in CSV for debugging

### Available Flags for run_simulation

```bash
./bin/run_simulation [OPTIONS]

# Key flags:
--seed, -s NUMBER         Random seed (default: 42, stored in CSV as game_id)
--turns, -t NUMBER        Max turns safety limit (default: 200)
--players, -p NUMBER      Number of AI players (default: 4)
--map-rings, -m NUMBER    Hex rings for map size (default: 3)
--fixed-turns             Run exactly N turns (disable victory check)
--run-until-victory       Run until victory (default behavior)
--output, -o FILE         Output JSON file path
--log-level, -l LEVEL     DEBUG, INFO, WARN, ERROR (default: INFO)

# Examples:
./bin/run_simulation -s 12345 -t 100           # Specific seed, max 100 turns
./bin/run_simulation -s 99999 -p 6 -m 4       # 6 players, larger map
./bin/run_simulation --fixed-turns -t 30      # Force exactly 30 turns
```

---

## Key Build Commands

```bash
# Primary builds
nimble buildSimulation      # Sim binary + git hash (USE THIS)
nimble buildAll             # All binaries (ec4x + run_simulation)
nimble buildDebug           # Debug symbols enabled

# Testing
nimble testBalanceQuick     # 20 games, 7 turns (~10s)
nimble testBalanceAct1      # 100 games, 7 turns (Act 1)
nimble testBalanceAct2      # 100 games, 15 turns (Act 2)
nimble testBalanceAct3      # 100 games, 25 turns (Act 3)
nimble testBalanceAct4      # 100 games, 30 turns (Act 4)

# AI evolution (genetic algorithms for personality weights)
nimble buildAITuning        # Build genetic algorithm tools
nimble evolveAIQuick        # 10 gen test (~5 min)
nimble evolveAI             # 50 gen (~2-4 hours)

# Cleanup
nimble tidy                # Remove build artifacts
```

---

## Analysis Workflow (Python + Polars)

### CSV Output Location

```
balance_results/diagnostics/
├── game_12345.csv          # Single game (seed in filename)
├── game_12346.csv          # Another game
└── game_*.csv              # Pattern for batch runs
```

Each CSV contains:
- `game_id` column with the seed value
- Per-turn economic/military stats (190+ columns)
- Victory conditions and final scores
- Combat outcomes

**Files are HUGE** (multi-GB for 100+ games) - polars handles them efficiently.

### Available Diagnostic Columns

**Reference:** `scripts/analysis/diagnostic_columns.json` contains the complete list of 200 diagnostic columns.

**Auto-generated:** Run `python3.11 scripts/update_diagnostic_columns.py` after modifying columns in `csv_writer.nim`

**Quick lookup:** `cat scripts/analysis/diagnostic_columns.json | jq '.diagnostic_columns'`

**Common columns for analysis:**
- Treasury: `treasury`, `production`, `maintenance_cost`, `treasury_deficit`
- Ships: `total_ships`, `ships_gained`, `ships_lost`, ship type columns (e.g., `destroyer_ships`)
- Colonies: `total_colonies`, `colonies_gained`, `colonies_lost`
- Tech: `tech_cst`, `tech_wep`, `tech_el`, `tech_sl`, etc.
- Combat: `space_wins`, `space_losses`, `combat_cer_avg`
- Prestige: `prestige`, `prestige_change`, `prestige_victory_progress`

**Ship Classifications:** The JSON includes ship role classifications (Escort, Capital, Auxiliary, Fighter, SpecialWeapon) matching the tables in `docs/specs/10-reference.md`.

### Creating Analysis Scripts

```python
import polars as pl

# IMPORTANT: Use python3.11 (not python3) for polars in nix-shell
# After rebuilding flake: exit and re-enter nix develop

# Load specific game by seed
df = pl.read_csv("balance_results/diagnostics/game_12345.csv")

# Or load all games (lazy evaluation)
df = pl.scan_csv("balance_results/diagnostics/game_*.csv")

# Filter and analyze
results = (
    df.filter(pl.col("turn") >= 7)
    .group_by("ai_strategy")
    .agg([
        (pl.col("victory_type") == "Domination").mean().alias("win_rate"),
        pl.count().alias("games")
    ])
    .collect()
)

print(results)
```

### Why Polars?

- **10-50x faster** than pandas on large CSVs
- **Lazy evaluation** - only processes needed data
- **Better memory** - ~50% less usage than pandas
- **Fast iteration** - no compilation, instant feedback

### Analysis Pattern

1. User runs simulation batch → generates CSVs
2. Claude writes Python script for specific analysis
3. User runs script → shares small text output (~1-5KB)
4. Claude interprets results, suggests next analysis
5. Iterate quickly without recompiling

**DON'T:** Ask user to upload raw CSVs (5-20MB, wastes 10k+ tokens)
**DO:** Write Python script that outputs summary text

---

## Project Structure (AI Work)

```
src/
├── ai/
│   ├── rba/             # Rule-Based Advisor (production AI - currently being fixed)
│   │   ├── player.nim          # Public API
│   │   ├── controller.nim      # Strategy profiles
│   │   ├── intelligence.nim    # Intel gathering
│   │   ├── strategic.nim       # Combat assessment
│   │   ├── tactical.nim        # Fleet operations
│   │   └── budget.nim          # Budget allocation
│   ├── analysis/               # Simulation & diagnostics
│   │   ├── run_simulation.nim  # Main simulation harness
│   │   └── diagnostics.nim     # 200+ metrics logged to CSV
│   ├── sweep/                  # GOAP infrastructure (experimental, not integrated)
│   ├── tuning/genetic/         # Genetic algo for AI personality weights
│   ├── training/               # Neural network training exports
│   └── common/                 # Shared AI types

config/
├── *.toml                      # Game balance (14 files)
└── rba.toml                    # RBA AI weights & thresholds

balance_results/diagnostics/    # CSV output from simulations

scripts/
├── run_balance_test_parallel.py  # Batch runner (Python)
└── analysis/                     # Your polars-based analysis scripts
```

---

## Configuration System

**All tunable values come from TOML files** - no hardcoded magic numbers.

```nim
# ❌ BAD - hardcoded
result.prestige = 2
let attackThreshold = 0.6

# ✅ GOOD - from config
result.prestige = globalPrestigeConfig.economic.tech_advancement
let attackThreshold = globalRBAConfig.strategic.attack_threshold
```

**Key configs:**
- `config/rba.toml` - RBA AI weights, budgets, thresholds
- `config/prestige.toml` - Prestige rewards
- `config/economy.toml` - Economic parameters
- `config/espionage.toml` - Intel ops costs

**Reloading for testing:**
```nim
reloadRBAConfig()  # Reload default
reloadRBAConfigFromPath("evolved_gen42.toml")  # Load evolved weights
```

---

## Fog-of-War System

**AI MUST use filtered views** - no omniscient state access.

```nim
# Get filtered view for AI
let view = createFogOfWarView(gameState, houseId)

# Access only what the house knows
for colony in view.ownColonies:        # Full details
  ...
for system in view.visibleSystems:    # Limited intel
  ...
for fleet in view.visibleFleets:      # If detected
  ...
```

**Visibility levels:** Owned > Occupied > Scouted > Adjacent > None

---

## Logging (Critical!)

**Use `std/logging`, NOT echo statements.**

```nim
import std/logging

# Events worth logging
info "Turn ", state.turn, " resolved: ", result.events.len, " events"
debug "Fleet ", fleetId, " moved from ", oldLoc, " to ", newLoc
error "Invalid order from ", houseId, ": ", reason
```

**Why:** Echo disappears in release builds. The "Brain-Dead AI" bug (Nov 2025) was invisible for 4 hours because of echo statements. Don't repeat this mistake.

---

## Unknown-Unknowns Testing

### Philosophy

Complex systems exhibit emergent behaviors. Catch them with **comprehensive CSV diagnostics**.

### Workflow

1. Run 100+ games → CSV diagnostics output
2. Write Python script to analyze specific metrics
3. Find anomalies → Formulate hypothesis
4. Add targeted logging → Re-test
5. Fix bug → Regression test

### Key Metrics (in diagnostics.nim)

```nim
# Track everything that affects gameplay
- Orders submitted/rejected    # Catches AI failures
- Build queue depth            # Catches construction stalls
- Ships commissioned           # Catches production bugs
- Fleet movement               # Catches stuck fleets
- ETAC activity               # Catches expansion failures
```

**Analysis is iterative** - write throwaway Python scripts to explore the data.

---

## Token-Efficient Development

**USER runs commands, reports only errors/results to Claude.**

### What Claude Should NOT Do

- ❌ Run build commands (1,000-3,000 tokens per compile)
- ❌ Run test commands (5,000-20,000 tokens per test run)
- ❌ Parse git output (100-500 tokens each)
- ❌ Load raw CSV files (10,000+ tokens for multi-MB files)

### What Claude SHOULD Do

- ✅ Write code changes and logic
- ✅ Write Python analysis scripts
- ✅ Interpret test result summaries
- ✅ Design solutions based on data
- ✅ Update documentation
- ✅ Complex file analysis and search

### Saves 10,000+ tokens per session

User shares:
- Compilation errors (last 20-50 lines only)
- Test failures (specific error messages)
- Summary results ("20 passed, 2 failed")
- Python script output (~1-5KB, not raw CSVs)

---

## File Organization

### /docs Root (MAX 7 FILES)

Current:
1. `TODO.md` - Living roadmap
2. `STYLE_GUIDE.md` - Coding standards
3. `README.md` - Docs overview
4. `KNOWN_ISSUES.md` - Current issues
5. `OPEN_ISSUES.md` - Tracked issues
6. `BALANCE_TESTING_METHODOLOGY.md` - Testing approach
7. (1 slot available)

**Note:** `CLAUDE.md` lives in project root, not /docs

**❌ NO other .md files in /docs root!**

### Organized Subdirectories

- `/docs/architecture/` - System design (**PRESERVE**)
- `/docs/specs/` - Game rules (**PRESERVE**)
- `/docs/ai/` - AI development and architecture
- `/docs/guides/` - Implementation guides
- `/docs/milestones/` - Historical milestones
- `/docs/archive/[date]/` - Obsolete docs

### When Creating Docs

1. Can it go in TODO.md? → Add there
2. Completion report? → Archive to `/docs/archive/[date]/`
3. Architecture? → `/docs/architecture/`
4. AI-related? → `/docs/ai/`
5. Guide? → `/docs/guides/`

---

## Common Gotchas

- **Stale binaries:** Use `nimble buildSimulation` (has `--forceBuild`), not direct `nim c`
- **RBA weights:** Edit `config/rba.toml`, NOT hardcoded in source
- **CSV size:** Multi-hundred game runs = GB+ of data, use polars
- **Git hash:** Always in `bin/.build_git_hash` after `nimble buildSimulation`
- **Clean old CSVs:** `rm -rf balance_results/diagnostics/*` before new runs
- **Analysis:** Write Python scripts, don't compile analysis into ec4x
- **Seeds matter:** Use `--seed` for reproducible testing, stored in CSV as `game_id`
- **CSV filenames:** Pattern is `game_{seed}.csv`, not timestamped files

---

## Code Standards Reference

### Test Structure Pattern

```nim
import std/unittest
import ../../src/engine/module_name/[types, engine]

suite "Module Name Tests":
  test "should do expected behavior":
    # Arrange
    let input = setupInput()

    # Act
    let result = functionUnderTest(input)

    # Assert
    check result == expectedValue
```

### Git Commit Format

**Format:**
```
Brief description (50 chars max)

- Detailed bullet point if needed
- Another detail
- Reference to issue if applicable
```

**Example:**
```
Add victory condition system

- Implements prestige, elimination, turn limit victories
- Adds leaderboard generation
- 9 integration tests passing
```

---

## Pre-Commit Checklist

- [ ] Enums are `{.pure.}`
- [ ] No hardcoded values (check TOML configs)
- [ ] Followed DRY - reused existing patterns
- [ ] Followed DoD - used Tables, avoided OOP patterns
- [ ] Used `std/logging`, not echo
- [ ] Line length ≤80 characters
- [ ] 2-space indentation, spaces around operators
- [ ] Relevant integration tests pass (if touching engine systems)
- [ ] `nimble testBalanceQuick` if touching AI/balance code (~10s)
- [ ] TODO.md updated if milestone reached
- [ ] /docs root has ≤7 .md files
- [ ] Engine code respects fog-of-war

**Note:** Git hooks automatically enforce `nimble buildAll` before push

---

## Current Status

**See TODO.md for full roadmap**

✅ **Complete:** 
- 13 engine systems operational
- 101+ integration tests passing
- Fog-of-war integrated
- Cipher Ledger timeline system
- GOAP infrastructure (not yet integrated)

🔄 **In Progress:** 
- **RBA bug fixes** - Getting RBA fully functional (current priority)
- Diagnostic-driven AI improvement
- Genetic algorithm weight tuning

📋 **Future:**
- Hybrid GOAP/RBA system - GOAP for strategy, RBA for tactics
- GOAP integration with RBA (after RBA is stable)

---

**Last Updated:** 2025-12-06  
**Location:** Project root (`CLAUDE.md`)  
**Usage:** Reference with `@CLAUDE.md` at session start
