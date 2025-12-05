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

# Analysis (Pure Nim - ec4x CLI)
nimble buildAnalysis           # Build ec4x analysis CLI
nimble analyzeSummary          # Quick terminal summary
nimble analyzeFull             # Full terminal analysis (with Unicode tables)
nimble analyzeCompact          # AI-friendly compact summary (~1500 tokens)
nimble analyzeDetailed         # Detailed markdown report (git-committable)
nimble analyzeAll              # Generate all report formats

# Data management
nimble dataInfo                # Show current analysis data status
nimble dataClean               # Clean old data (keep last 5 reports, 10 summaries)
nimble dataCleanAll            # Clean ALL analysis data with backup
nimble dataArchives            # List archived diagnostic backups

# AI Optimization (separate from testing)
nimble buildAITuning           # Build genetic algorithm tools
nimble evolveAIQuick           # Quick 10-gen test (~5 min)
nimble evolveAI                # Full 50-gen evolution (~2-4 hours)
nimble coevolveAI              # Competitive co-evolution
nimble tuneAIDiagnostics       # 100 games + analysis

# Unknown-unknowns detection
nimble testUnknownUnknowns     # 200 games + full analysis
nimble balanceDiagnostic       # 100 games + analysis
nimble balanceQuickCheck       # 20 games + analysis

# Cleanup
nimble buildSimulation         # Build simulation binary
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
2. **Analyze with ec4x CLI (Pure Nim)** - Unified analysis tool
3. Find anomalies → Formulate hypotheses
4. Add targeted logging → Re-test
5. Fix → Regression test with nimble

### CSV Analysis (Pure Nim - ec4x CLI)

**Use `ec4x` CLI for ALL diagnostic analysis** - Pure Nim, no Python required

```bash
# Quick terminal summary (human-readable)
bin/ec4x --summary

# Full analysis with Unicode tables
bin/ec4x --full

# Compact markdown (~1500 tokens for Claude)
bin/ec4x --compact

# Detailed markdown report (git-committable)
bin/ec4x --detailed

# All formats at once
bin/ec4x --all

# With options
bin/ec4x --summary -d custom/diagnostics/  # Custom directory
bin/ec4x --compact -o my_report.md         # Custom output file
bin/ec4x --full --no-save                  # Don't save to file
```

**Output organization** (gitignored in `balance_results/`):
```
balance_results/
├── diagnostics/           # Raw CSV data from simulations
│   └── game_*.csv
├── reports/               # Terminal and markdown reports
│   ├── terminal_*.txt    # Rich terminal output
│   ├── detailed_*.md     # Full analysis reports
│   └── latest.md         # Symlink to most recent detailed report
├── summaries/             # Compact AI-friendly summaries
│   └── compact_*.md      # ~1500 token summaries for Claude
└── archives/              # Backup of old diagnostics
    └── diagnostics_backup_*/
```

**Key features:**
- ✅ Pure Nim (Datamancer DataFrame library)
- ✅ Auto-cleanup before new runs (with backup)
- ✅ Organized timestamped outputs
- ✅ Token-efficient summaries for Claude
- ✅ Unicode table formatting for terminal
- ✅ Red flag detection (8 analyzer types)
- ✅ Strategy performance analysis
- ✅ Economy/military/espionage metrics

**Analysis metrics:**
- Strategy performance (prestige, win rate, treasury)
- Economy (treasury, PU growth, zero-spend rate)
- Military (ships, fighters, idle carriers)
- Espionage (spy/hack missions, adoption rate)
- Red flags (capacity violations, broken systems)

**For custom analysis:**
- Read `src/ai/analysis/analyzers/` modules
- Extend analyzer types or create new ones
- All code in Nim using Datamancer DataFrames

### Python/Polars Analysis (Alternative - Token-Efficient)

**⚠️ IMPORTANT FOR CLAUDE: Use Python scripts for CSV analysis, NOT raw CSV files!**

When the user requests CSV diagnostics analysis:

1. **NEVER load raw CSV files directly** - They are 5-20MB and waste 10,000+ tokens
2. **ALWAYS use `scripts/analysis/analyze_diagnostics.py`** - Generates small text summaries
3. **Token efficiency: 10-100x reduction** vs uploading raw CSVs

**Quick analysis workflow:**
```bash
# Setup (one-time)
pip install -r scripts/analysis/requirements.txt  # Or: uv pip install

# Run analyses (Claude instructs user to run these)
python scripts/analysis/analyze_diagnostics.py summary           # Quick overview
python scripts/analysis/analyze_diagnostics.py strategy          # Strategy comparison
python scripts/analysis/analyze_diagnostics.py red-flags         # Detect issues
python scripts/analysis/analyze_diagnostics.py compare A B       # Head-to-head
python scripts/analysis/analyze_diagnostics.py economy           # Economic metrics
python scripts/analysis/analyze_diagnostics.py military          # Military metrics
python scripts/analysis/analyze_diagnostics.py research          # Tech progression
python scripts/analysis/analyze_diagnostics.py diplomacy         # Diplomatic status

# Custom queries (advanced)
python scripts/analysis/analyze_diagnostics.py custom "filter(pl.col('prestige') > 500)"
```

**Analysis commands available:**
- `summary` - Quick overview (game count, strategies, final metrics)
- `strategy` - Performance comparison (growth rates, trends)
- `economy` - Treasury, production, efficiency, red flags
- `military` - Fleet composition, combat, capacity violations
- `research` - Tech levels, investment, waste
- `diplomacy` - Relationships, pacts, wars
- `red-flags` - Automated issue detection (dominance, stagnation, waste, failures)
- `compare <S1> <S2>` - Head-to-head strategy comparison
- `custom "<query>"` - Execute custom Polars DataFrame operations

**Command options:**
- `--min-turn N` - Filter to turns >= N
- `--max-turn N` - Filter to turns <= N

**Claude's workflow when user asks for analysis:**

1. **Instruct user to run script**:
   ```
   Please run: python scripts/analysis/analyze_diagnostics.py summary
   Then share the output with me (it will be small, ~1-2KB).
   ```

2. **Analyze the output** (not raw CSV):
   - User shares script output (~1-2KB vs 5-20MB raw CSV)
   - Claude interprets results, suggests next steps
   - Claude may suggest additional analyses

3. **Iterate with targeted analyses**:
   ```
   Based on those results, let's look at economy:
   python scripts/analysis/analyze_diagnostics.py economy
   ```

4. **Suggest custom scripts if needed**:
   - For specialized analysis, Claude can write new scripts in `scripts/analysis/`
   - Follow the template in `analyze_diagnostics.py`
   - Use Polars for performance (10-50x faster than Pandas)

**Creating new analysis scripts:**
```python
import polars as pl

# Load all diagnostics
df = pl.scan_csv("balance_results/diagnostics/*.csv").collect()

# Your custom analysis using Polars DataFrame API
result = df.filter(pl.col("turn") > 10).group_by("strategy").agg(...)

print(result)  # Small text output for Claude
```

**Performance benefits:**
- Loading: ~10x faster than Pandas
- Filtering: ~5-20x faster
- Aggregations: ~10-50x faster
- Memory: ~50% less usage

**For 400 games (4000+ CSV files):**
- Load time: <5 seconds
- Analysis time: <1 second per command
- Output size: ~1-5KB (vs 5-20MB raw CSV)

**Documentation:** See `scripts/analysis/README.md` for full command reference

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
│   ├── analysis/        # Pure Nim analysis system
│   │   ├── run_simulation.nim    # Simulation harness
│   │   ├── diagnostics.nim       # Metric logging (200+ metrics)
│   │   ├── types.nim             # Common types
│   │   ├── data/                 # Data loading
│   │   │   ├── loader.nim       # CSV loading with Datamancer
│   │   │   ├── statistics.nim   # Statistical functions
│   │   │   └── manager.nim      # Output organization
│   │   ├── analyzers/            # Analysis modules
│   │   │   ├── analyzer.nim     # Unified analyzer
│   │   │   ├── performance.nim  # Strategy analysis
│   │   │   └── red_flags.nim    # Issue detection
│   │   └── formatters/           # Output generators
│   │       ├── terminal.nim     # Unicode tables
│   │       ├── compact.nim      # Token-efficient
│   │       └── markdown.nim     # Detailed reports
│   ├── tuning/          # AI optimization
│   │   └── genetic/     # Genetic algorithms
│   ├── training/        # Neural network training exports
│   │   └── export.nim   # 600-dim state encoding
│   └── common/          # Shared AI types (AIStrategy, etc.)
├── cli/
│   ├── ec4x.nim         # Unified CLI tool (analysis, etc.)
│   └── commands/        # Command implementations
│       ├── analyze.nim  # Analysis commands
│       └── data.nim     # Data management

scripts/                 # Parallel orchestration (temporary)
│   ├── run_balance_test_parallel.py  # Multi-process runner
│   └── run_map_size_test.py          # Map size testing

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
