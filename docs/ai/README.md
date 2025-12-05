# AI System Documentation

**Last Updated:** 2025-12-05
**Current Status:** Intelligence Integration Phase C Complete, GOAP + RBA Hybrid Operational

## Overview

EC4X features a hybrid AI architecture combining:
- **GOAP (Goal-Oriented Action Planning)** - Strategic multi-turn planning (3-10 turns ahead)
- **RBA (Rule-Based Advisors)** - Tactical single-turn execution with intelligence-driven adaptation
- **Intelligence System** - Centralized intelligence processing from 5 engine report types

This hybrid system provides Byzantine Imperial AI with strategic foresight, adaptive replanning, combat learning, and intelligence-driven decision making across 6 domains (Fleet, Build, Research, Diplomatic, Espionage, Economic).

---

## 🆕 Recent Changes (December 2025)

### Intelligence Integration Phase C Complete ✅
**Date:** 2025-12-05
**Status:** Production-ready, ~70% intelligence utilization

**Implementation:**
- Starbase intelligence analyzer (~155 LOC) - Tech gap detection and economic assessment
- Combat intelligence analyzer (~205 LOC) - Tactical lessons from combat encounters
- Tech gap priority system - Critical/High priority research needs
- Logothete integration - Intelligence-driven research allocation
- Domestikos combat learning - Ship type selection based on proven effectiveness

**Key Features:**
- **Tech Gap Analysis:** Identifies critical tech disadvantages (3+ levels behind enemies)
- **Combat Learning:** AI learns which ship types work against specific enemies
- **Adaptive Research:** Logothete boosts tech gaps (10% budget for Critical, 5% for High)
- **Combat-Informed Build:** Domestikos selects proven ship types vs known threats

**Intelligence Utilization Progress:**
- Phase A (Baseline): ~5% utilization
- Phase B (Colony + System): ~40% utilization
- Phase C (Starbase + Combat): ~70% utilization ✅
- Phase D (Surveillance + Full Integration): Target >80%

**Processed Report Types:**
1. ✅ ColonyIntelReport → Vulnerability & high-value targets (Phase B)
2. ✅ SystemIntelReport → Enemy fleet tracking (Phase B)
3. ✅ StarbaseIntelReport → Tech gaps & economy (Phase C)
4. ✅ CombatEncounterReport → Tactical lessons (Phase C)
5. ⏳ StarbaseSurveillanceReport → Surveillance gaps (Phase D)

**See:** `analysis/intelligence-phase-c-complete.md` for implementation details

---

### GOAP + RBA Hybrid System Complete ✅
**Date:** 2025-12-04
**Status:** Production-ready, awaiting performance testing

**Implementation:**
- ~5,700 LOC across 32 files
- 6 domains with 25 goal types and 25 action types
- A* planner with admissible heuristics
- RBA integration with budget estimation
- Replanning triggers for adaptive behavior
- Parameter sweep framework (243 parameter sets)
- 35 unit tests (100% passing)

**Key Features:**
- Strategic planning horizon (3-10 turns)
- Budget-aware multi-domain coordination
- Adaptive replanning on state changes
- Configuration-driven behavior per strategy
- Backward compatible (GOAP can be disabled)

**See:** `GOAP_COMPLETE.md` for comprehensive documentation

---

### RBA Bug Fixes Complete ✅
**Date:** 2025-12-04
**Status:** All bugs fixed, performance regression identified

**Fixed Issues:**
1. ✅ Espionage budget calculation (EBP/CIP now working)
2. ✅ War AI combat orders (Bombard/Invade/Blitz selection)
3. ✅ Scout intelligence missions (HackStarbase/SpyPlanet/SpySystem)
4. ✅ Infinite loop in scout targeting (HashSet optimization)

**Known Issue:** Performance regression (40+ seconds per 8-turn game)
- NOT caused by RBA fixes
- Likely from capacity systems (carrier hangar, construction docks)
- Needs profiling to identify bottleneck

**See:** `RBA_WORK_COMPLETE_NEXT_STEPS.md` for details

---

### Commissioning & Automation Refactor ✅
**Date:** 2025-12-04
**Status:** Implementation complete

**Changes:**
- Moved commissioning from Maintenance Phase to Command Phase
- Consolidated all automation in `automation.nim` module
- Implemented auto-loading fighters to carriers (per-colony toggle)
- Removed 468+ lines of dead code
- Maintained strict DRY and DoD principles

**See:** `COMMISSIONING_AUTOMATION_REFACTOR_COMPLETE.md` for details

---

## Quick Start

### Testing the AI

```bash
# Build the project
nimble build

# Quick validation (20 games, ~10s)
nimble testBalanceQuick

# Full balance testing (400 games across 4 acts)
nimble testBalanceAll4Acts

# Quick game simulation (8 turns, 4 houses)
time ./bin/run_simulation 8 12345 4 4
```

**Expected Performance:**
- 8-turn game: Should complete in <1 second (currently experiencing regression)
- 40-turn game: ~5-10 seconds

---

## Analysis System

EC4X uses a **Pure Nim analysis system** (no Python required) via the `ec4x` CLI tool.

### Quick Analysis Commands

```bash
# Build analysis CLI
nimble buildAnalysis

# Quick terminal summary (human-readable)
nimble analyzeSummary

# Full analysis with Unicode tables
nimble analyzeFull

# Compact markdown (~1500 tokens for Claude)
nimble analyzeCompact

# Detailed markdown report (git-committable)
nimble analyzeDetailed

# Generate all report formats
nimble analyzeAll
```

### Data Management

```bash
# Show current data status
nimble dataInfo

# Clean old data (keep last 5 reports, 10 summaries)
nimble dataClean

# Clean ALL data with backup
nimble dataCleanAll

# List archived diagnostics
nimble dataArchives
```

### Output Organization

```
balance_results/
├── diagnostics/           # Raw CSV data from simulations
│   └── game_*.csv
├── reports/               # Terminal and markdown reports
│   ├── terminal_*.txt    # Rich terminal output
│   ├── detailed_*.md     # Full analysis reports
│   └── latest.md         # Symlink to most recent report
├── summaries/             # Compact AI-friendly summaries
│   └── compact_*.md      # ~1500 token summaries
└── archives/              # Backup of old diagnostics
    └── diagnostics_backup_*/
```

**Key Features:**
- ✅ Pure Nim (Datamancer DataFrame library)
- ✅ Auto-cleanup with backup before new runs
- ✅ Token-efficient summaries for Claude Code
- ✅ Unicode table formatting for terminal
- ✅ Red flag detection (8 analyzer types)
- ✅ Strategy performance analysis

---

## Architecture

### File Structure

```
src/ai/
├── rba/                     # Rule-Based Advisor (production AI)
│   ├── player.nim           # Public API
│   ├── controller.nim       # Strategy profiles
│   ├── intelligence.nim     # Intel gathering
│   ├── diplomacy.nim        # Diplomatic assessment
│   ├── tactical.nim         # Fleet operations
│   ├── strategic.nim        # Combat assessment
│   ├── budget.nim           # Budget allocation
│   └── goap/                # GOAP integration (~5,700 LOC)
│       ├── core/            # Foundation (types, conditions, heuristics)
│       ├── state/           # State management (snapshot, assessment, effects)
│       ├── planner/         # A* algorithm (node, search)
│       ├── domains/         # 6 domains (fleet, build, research, etc.)
│       └── integration/     # RBA integration (conversion, tracking, replanning)
├── analysis/                # Pure Nim analysis system
│   ├── run_simulation.nim   # Simulation harness
│   ├── diagnostics.nim      # Metric logging (200+ metrics)
│   ├── data/                # CSV loading, statistics, management
│   ├── analyzers/           # Performance and red flag analysis
│   └── formatters/          # Terminal, compact, markdown output
├── tuning/                  # AI optimization
│   └── genetic/             # Genetic algorithms
├── sweep/                   # Parameter sweep framework
│   └── params/              # GOAP parameter definitions
├── training/                # Neural network training exports
│   └── export.nim           # 600-dim state encoding
└── common/                  # Shared AI types

cli/
├── ec4x.nim                 # Unified CLI tool (analysis, etc.)
└── commands/
    ├── analyze.nim          # Analysis commands
    └── data.nim             # Data management
```

### GOAP + RBA Hybrid Architecture

**Phase 1-3: Strategic Planning (GOAP)**
- Goal extraction from game state
- Multi-turn action planning with A*
- Budget estimation for strategic needs

**Phase 4: RBA Integration**
- GOAP plans inform RBA budget allocation
- Treasurer has visibility into strategic needs
- Backward compatible (GOAP can be disabled)

**Phase 5: Feedback & Replanning**
- RBA feedback triggers GOAP replanning
- Budget shortfalls detected automatically
- Opportunistic goal pursuit

**Configuration:**
All GOAP behavior controlled via `GOAPConfig` in `config/rba.toml`:
- Planning depth (3-10 turns)
- Confidence threshold (0.4-0.9)
- Max concurrent plans (3-10)
- Defense/offense priorities (0.0-1.0)

---

## Testing Workflow

### Token-Efficient Development

**USER runs commands, reports only errors/results to Claude:**
- Build output: 1,000-3,000 tokens per compile
- Test output: 5,000-20,000 tokens per test run
- Saves 10,000+ tokens per session

**Claude focuses on:**
- Code changes and logic
- Documentation updates
- Design decisions
- File reading and analysis
- Interpreting test results

### Quick Commands

```bash
# Standard tests
nimble test                    # All integration tests
nimble testBalanceQuick        # Quick validation (20 games, ~10s)

# 4-Act testing (auto-cleans old diagnostics)
nimble testBalanceAct1         # Act 1 (7 turns, 100 games)
nimble testBalanceAct2         # Act 2 (15 turns, 100 games)
nimble testBalanceAct3         # Act 3 (25 turns, 100 games)
nimble testBalanceAct4         # Act 4 (30 turns, 100 games)
nimble testBalanceAll4Acts     # All 4 acts (400 games)

# AI Optimization
nimble buildAITuning           # Build genetic algorithm tools
nimble evolveAIQuick           # Quick 10-gen test (~5 min)
nimble evolveAI                # Full 50-gen evolution (~2-4 hours)
nimble coevolveAI              # Competitive co-evolution
```

---

## Configuration System

All balance values from TOML (14 files):
- Engine: `config/prestige.toml`, `config/espionage.toml`, `config/economy.toml`, etc.
- RBA AI: `config/rba.toml` (AI strategies, budgets, thresholds)
- GOAP: Embedded in RBA config (planning depth, confidence, priorities)

**Example (from config/rba.toml):**
```toml
[goap.default]
enabled = true
planning_depth = 5
confidence_threshold = 0.6
max_concurrent_plans = 5
defense_priority = 0.7
offense_priority = 0.5

[goap.aggressive]
enabled = true
planning_depth = 3
confidence_threshold = 0.5
max_concurrent_plans = 7
defense_priority = 0.4
offense_priority = 0.9
```

---

## Known Issues

### Performance Regression ⚠️
**Symptom:** 8-turn game takes 40+ seconds instead of <1 second
**Root Cause:** Unknown, predates RBA/GOAP work
**Suspected Culprits:**
- Carrier hangar capacity system
- Construction dock capacity system
- Potential O(n²) patterns in capacity checks

**Next Steps:**
1. Profile simulation to identify bottleneck
2. Review capacity algorithms for nested loops
3. Add caching if capacity checks are repeated
4. Optimize hot paths

**See:** `RBA_WORK_COMPLETE_NEXT_STEPS.md` for investigation steps

---

## Documentation

### Current Documentation
1. **GOAP_COMPLETE.md** - Complete GOAP + RBA hybrid system documentation
2. **RBA_WORK_COMPLETE_NEXT_STEPS.md** - RBA fixes and performance investigation
3. **COMMISSIONING_AUTOMATION_REFACTOR_COMPLETE.md** - Construction system refactor
4. **ARCHITECTURE.md** - Overall AI system architecture
5. **QUICK_START.md** - Getting started guide

### Outdated Documentation (To Be Archived)
Several older documentation files are now superseded by recent work:
- TOKEN_EFFICIENT_WORKFLOW.md (workflow mostly unchanged)
- RBA_OPTIMIZATION_GUIDE.md (RBA bugs now fixed)
- AI_ANALYSIS_WORKFLOW.md (workflow documented in CONTEXT.md)
- DATA_MANAGEMENT.md (data commands documented in CONTEXT.md)
- Multiple GOAP phase documents (consolidated in GOAP_COMPLETE.md)

**Note:** Per CONTEXT.md rules, /docs/ai should maintain only essential current documentation. Historical docs should be archived to `/docs/archive/[date]/`.

---

## Next Steps

### Immediate Priority
1. **Performance Investigation**
   - Profile simulation to identify bottleneck
   - Fix capacity system slowdown
   - Verify AI behavior with proper performance

### After Performance Fix
1. **Run Balance Test Suite**
   ```bash
   nimble testBalanceAll4Acts
   ```
2. **Generate RBA Baseline Metrics**
   - Compare vs GOAP targets
   - Analyze strategy performance
   - Evaluate GOAP effectiveness

### GOAP Testing & Optimization
1. Write GOAP integration tests
2. Run 10-turn test game with GOAP logging
3. Perform stratified parameter sweep (50 sets)
4. Analyze results and document optimal configurations
5. A/B test: GOAP vs pure RBA

---

## Performance Expectations (7950X3D)

**Simulation (when fixed):**
- 8 turns: <1 second
- 40 turns: ~5-10 seconds
- 50 games: ~2 minutes
- 100 games: ~4 minutes
- 400 games (4-act): ~15-20 minutes

**Analysis (Pure Nim):**
- Summary generation: ~2 seconds
- Parquet conversion: ~3 seconds
- Custom query: <1 second
- Full report with Unicode tables: ~5 seconds

**GOAP Overhead (per house, per turn):**
- Goal extraction: <10ms
- Plan generation: <100ms
- Budget estimation: <1ms
- Replanning (when triggered): <200ms
- **Total Phase 1.5:** ~120ms

---

## Best Practices

### ✅ DO
- Use `ec4x` CLI for all diagnostic analysis
- Start with compact summaries for Claude (~1500 tokens)
- Run balance tests with nimble tasks (not direct commands)
- Use proper logging (`std/logging`, not echo)
- Follow DRY and DoD principles
- Update TODO.md after major milestones

### ❌ DON'T
- Upload raw CSV files to Claude (5M tokens)
- Run direct Python/bash commands (use nimble tasks)
- Use echo statements in production code
- Hardcode game values (use TOML configs)
- Create files without checking 7-file limit in /docs root

---

## References

- **Main Context:** `docs/CONTEXT.md` - Critical rules and workflow
- **TODO:** `docs/TODO.md` - Project-wide roadmap
- **Style Guide:** `docs/STYLE_GUIDE.md` - Coding standards
- **Balance Testing:** `docs/BALANCE_TESTING_METHODOLOGY.md` - Testing approach
- **AI Status:** `docs/ai/STATUS.md` - Neural network training roadmap (outdated, pre-GOAP)

---

## Support

**Getting Started:**
1. Read `CONTEXT.md` for critical rules and workflow
2. Read `GOAP_COMPLETE.md` for AI system architecture
3. Run `nimble testBalanceQuick` to verify setup
4. Use `nimble analyzeCompact` to generate AI-friendly reports

**For Help:**
- Tool documentation: See `ec4x --help` and nimble task definitions
- Claude Code: Share compact summaries for analysis
- Architecture questions: See GOAP_COMPLETE.md and ARCHITECTURE.md

---

**Remember:** The hybrid GOAP + RBA system is production-ready and awaiting performance fixes. Focus on profiling and optimizing the capacity systems, then proceed with comprehensive testing and parameter optimization!
