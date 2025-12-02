# Claude Code Session Context

**Load at session start:** `@docs/TODO.md` `@docs/STYLE_GUIDE.md`

---

## Critical Rules (Never Forget)

1. **All enums MUST be `{.pure.}`**
2. **No hardcoded game variables** - use TOML configs
3. **Follow DRY and existing DoD patterns**
4. **Follow NEP-1** - see STYLE_GUIDE.md
5. **Update TODO.md** after milestones
6. **Run tests before commits** - `nimble test`
7. **Max 7 markdown files in /docs root** - archive old docs to `/docs/archive/[date]/`
8. **Add focused doc comments** when touching engine code
9. **Engine respects fog-of-war** - use house.intelligence, not omniscient state
10. **Use proper logging** - `std/logging`, NOT echo statements

---

## File Organization (Keep Project Clean!)

### /docs Root (MAX 7 FILES - Current)
1. CLAUDE_CONTEXT.md - This file
2. TODO.md - Living roadmap
3. STYLE_GUIDE.md - Coding standards
4. README.md - Docs overview
5. KNOWN_ISSUES.md - Current issues
6. OPEN_ISSUES.md - Tracked issues
7. BALANCE_TESTING_METHODOLOGY.md - Testing approach

**❌ NO other .md files in /docs root!**

### Organized Subdirectories
- `/docs/architecture/` - System design, vision (**PRESERVE**)
- `/docs/specs/` - Game rules (**PRESERVE**)
- `/docs/guides/` - Implementation guides
- `/docs/milestones/` - Historical milestones
- `/docs/archive/` - Obsolete docs (organized by date)

### When Creating Documentation
1. ✅ Can it go in TODO.md? → Add there
2. ✅ Completion report? → Archive to `/docs/archive/[date]/`
3. ✅ Architecture? → `/docs/architecture/`
4. ✅ Guide? → `/docs/guides/`
5. ✅ Milestone? → `/docs/milestones/`

### Periodic Cleanup
```bash
ls docs/*.md | wc -l  # Should be 7
# If more: archive to docs/archive/YYYY-MM-obsolete/
```

---

## Testing Workflow (Nimble-First)

**🔴 CRITICAL: Use nimble tasks ONLY. Never run Python/bash/nim directly.**

### Token-Efficient Development Workflow

**USER runs commands, reports only errors/results to Claude:**

```bash
# Build & test (run yourself)
nimble build                   # Compile all components
nimble test                    # All integration tests
nimble testBalanceQuick        # Quick validation (20 games, ~10s)

# Only show Claude:
# - Compilation errors (last 20-50 lines)
# - Test failures (specific error messages)
# - Summary results ("X passed, Y failed")
```

**Why this saves tokens:**
- Build output: 1,000-3,000 tokens per compile
- Test output: 5,000-20,000 tokens per test run
- Git commands: 100-500 tokens each
- Error iterations: Multiple round trips avoided

**Claude focuses on:**
- Code changes and logic
- Documentation updates
- Design decisions
- File reading and analysis
- Complex grep/search operations
- **Analysis tools and diagnostics** (CSV analysis, polars scripts, metrics)
- **Interpreting test results** (balance analysis, unknown-unknowns detection)

**Benefits:**
- ✅ Saves 10,000+ tokens per session
- ✅ Forces thoughtful decision-making
- ✅ Faster development (no waiting for output parsing)
- ✅ You verify results directly

### Quick Commands (Run These Yourself)
```bash
# Standard tests
nimble test                    # All integration tests
nimble testBalanceQuick        # Quick validation (20 games, ~10s)

# 4-Act testing (auto-cleans old diagnostics before running)
nimble testBalanceAct1         # Act 1 (7 turns, 100 games)
nimble testBalanceAct2         # Act 2 (15 turns, 100 games)
nimble testBalanceAct3         # Act 3 (25 turns, 100 games)
nimble testBalanceAct4         # Act 4 (30 turns, 100 games)
nimble testBalanceAll4Acts     # All 4 acts (400 games)

# Manual cleanup (rarely needed - auto-cleaned by test tasks)
nimble cleanBalance            # Clean old diagnostics/binaries

# AI Optimization (separate from testing)
nimble buildAITuning           # Build genetic algorithm tools
nimble evolveAIQuick           # Quick 10-gen test (~5 min)
nimble evolveAI                # Full 50-gen evolution (~2-4 hours)
nimble coevolveAI              # Competitive co-evolution
nimble tuneAIDiagnostics       # 100 games + analysis

# Unknown-unknowns detection
nimble testUnknownUnknowns     # 200 games + analysis
nimble analyzeDiagnostics      # Analyze Phase 2 gaps

# Cleanup
nimble buildBalance            # Build balance binary
nimble cleanBalance            # Clean balance artifacts
nimble cleanAITuning           # Clean AI tuning artifacts
```

### Why Nimble?
- **Prevents stale binaries**: Uses `--forceBuild` (full recompilation every time)
- **Auto-cleans old data**: Removes `balance_results/diagnostics/*.csv` before each run
- **Git hash tracking**: Verifies binary matches source
- **Regression safe**: No incremental compilation bugs
- **Cross-platform**: Works everywhere

**Output:** `balance_results/diagnostics/game_*.csv` (fresh data each run)

**IMPORTANT:** Test tasks now automatically delete old diagnostic CSVs before running to prevent confusion from stale data. If you need to preserve diagnostics, copy them elsewhere first.

---

## Logging Rules

**Use `std/logging`, NOT echo:**

```nim
import std/logging

# Critical events
info "Turn ", state.turn, " resolved: ", result.events.len, " events"

# Debug traces
debug "Fleet ", fleetId, " moved from ", oldLoc, " to ", newLoc

# Errors with context
error "Invalid order from ", houseId, ": ", reason
```

**Why:** Echo disappears in release builds. The "Brain-Dead AI" bug (2025-11-25) was invisible for 4 hours because of echo statements.

---

## Unknown-Unknowns Testing

### Philosophy
> "You don't know what you don't know until you observe it."

Complex systems exhibit emergent behaviors. Catch them with **comprehensive observation**.

### Key Metrics (see tests/balance/diagnostics.nim)
```nim
# Track EVERYTHING that affects gameplay
- Orders submitted/rejected (catches AI failures)
- Build queue depth (catches construction stalls)
- Ships commissioned (catches production bugs)
- Fleet movement (catches stuck fleets)
- ETAC activity (catches expansion failures)
```

### Detection Workflow
1. Run 100+ games → CSV diagnostics
2. Analyze with Polars (Python) - **REQUIRED**
3. Find anomalies → Formulate hypotheses
4. Add targeted logging → Re-test
5. Fix → Regression test with nimble

### CSV Analysis Requirements
**Use polars for ALL CSV analysis** - Fast, type-safe DataFrame library
```python
import polars as pl

# Read diagnostic CSV
df = pl.read_csv('balance_results/diagnostics/game_2000.csv')

# Filter and analyze
result = (df
    .filter(pl.col('turn') >= 5)
    .select(['turn', 'house', 'tech_cst', 'total_fighters'])
    .sort(['house', 'turn'])
)

# Aggregate stats
summary = df.group_by('house').agg([
    pl.col('prestige').mean().alias('avg_prestige'),
    pl.col('tech_cst').max().alias('max_cst')
])
```

**Why polars over pandas:**
- 5-10x faster on large CSVs (130+ columns)
- Better type inference
- Lazy evaluation support
- Modern API with method chaining

### Claude Scripts Directory (`claude_scripts/`)
**Purpose:** Temporary analysis scripts generated by Claude Code (not tracked in git)

**Workflow:**
1. Claude creates analysis scripts in `claude_scripts/` directory
2. User runs scripts from project root: `python3 claude_scripts/script_name.py`
3. Scripts analyze CSV diagnostics and generate reports
4. No need to commit (directory gitignored)

**Example:**
```bash
# Claude creates: claude_scripts/analyze_tech_effects.py
# User runs from project root:
python3 claude_scripts/analyze_tech_effects.py balance_results/diagnostics/game_2000.csv
```

**Benefits:**
- Scripts separated from codebase
- No git pollution with temporary analysis tools
- Easy to delete/regenerate as needed
- Documented in `claude_scripts/README.md`

---

## Configuration System

**All balance values from TOML (14 files):**
- Engine: `config/prestige.toml`, `config/espionage.toml`, `config/economy.toml`, etc.
- RBA AI: `config/rba.toml` (NEW - AI strategies, budgets, thresholds)
- Type-safe loaders via `toml_serialization`
- TOML uses `snake_case`, Nim fields match exactly

```nim
# ❌ BAD - hardcoded
result.prestige = 2
let attackThreshold = 0.6

# ✅ GOOD - from config
result.prestige = globalPrestigeConfig.economic.tech_advancement
let attackThreshold = globalRBAConfig.strategic.attack_threshold
```

**RBA Configuration** (`config/rba.toml` → `src/ai/rba/config.nim`):
- Strategy personalities (12 strategies × 6 traits)
- Budget allocations by game act (4 acts × 6 objectives)
- Tactical parameters (response radius, ETA limits)
- Strategic thresholds (attack, retreat)
- Economic costs (terraforming)
- Orders parameters (research caps, scout counts)
- Logistics thresholds (mothballing)
- Fleet composition ratios
- Threat assessment levels

**Reloading for testing:**
```nim
reloadRBAConfig()                              # Reload default config
reloadRBAConfigFromPath("evolved_gen42.toml")  # Load custom config
```

---

## Architecture Quick Reference

```
src/
├── engine/              # 13 major systems (combat, economy, etc.)
│   └── fog_of_war.nim   # FoW filtering (mandatory for AI)
├── ai/
│   ├── rba/             # Rule-Based Advisor (production AI)
│   │   ├── player.nim       # Public API
│   │   ├── controller.nim   # Strategy profiles
│   │   ├── intelligence.nim # Intel gathering
│   │   ├── diplomacy.nim    # Diplomatic assessment
│   │   ├── tactical.nim     # Fleet operations
│   │   ├── strategic.nim    # Combat assessment
│   │   └── budget.nim       # Budget allocation
│   ├── training/        # Neural network training exports
│   │   └── export.nim       # 600-dim state encoding
│   └── common/          # Shared AI types (AIStrategy, etc.)

tests/balance/           # Balance testing (uses production RBA)
│   ├── run_simulation.nim # Test harness (uses src/ai/rba/)
│   └── diagnostics.nim    # Metric logging (130 columns)

tools/ai_tuning/         # AI optimization
│   ├── run_parallel_diagnostics.py  # Parallel game runner
│   └── *.py                         # Analysis scripts

docs/
├── ai/                  # AI system documentation
├── testing/             # Testing methodology
├── architecture/        # System design (**PRESERVE**)
├── specs/               # Game rules (**PRESERVE**)
└── archive/             # Obsolete docs
```

**Key principle:** Fleet → Squadrons (combat) + SpaceLift ships (individual units, NOT squadrons)

**AI Documentation:** See [docs/ai/README.md](ai/README.md)
**Testing Documentation:** See [docs/testing/README.md](testing/README.md)

---

## Fog-of-War System

**Mandatory for AI (RBA and NNA)**

```nim
type FilteredGameState* = object
  viewingHouse*: HouseId
  ownColonies*: seq[Colony]              # Full details
  visibleSystems*: Table[SystemId, VisibleSystem]  # Limited view
  visibleFleets*: seq[VisibleFleet]      # If detected
```

**Visibility:** Owned > Occupied > Scouted > Adjacent > None

**Usage:** `let view = createFogOfWarView(gameState, houseId)`

---

## Pre-Commit Checklist

- [ ] Enums are `{.pure.}`
- [ ] No hardcoded values
- [ ] `nimble test` passes
- [ ] `nimble testBalanceQuick` (if AI/balance code)
- [ ] TODO.md updated (if milestone)
- [ ] Used nimble tasks (not direct commands)
- [ ] /docs root has ≤7 files
- [ ] Engine respects fog-of-war

---

## Current Status

**See TODO.md for full details**

✅ **Complete:** Engine (13 systems), 101+ tests, FoW integrated, Cipher Ledger timeline
🔄 **In Progress:** Phase 2 RBA enhancements (diagnostic-driven improvement)

**Test Coverage:** 101+ integration tests passing
