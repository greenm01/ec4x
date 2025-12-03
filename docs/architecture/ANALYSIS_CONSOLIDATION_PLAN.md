# EC4X Analysis & Testing Consolidation Plan

## Current State Analysis

### Problem Summary
The AI analysis and testing infrastructure has become fragmented across multiple directories:
- Python scripts scattered in `scripts/`, `balance_tuning/`, `analysis/`, `src/ai/tuning/`, and `src/ai/analysis/`
- Nim test files moved from `tests/balance/` to `src/ai/analysis/`
- Old tools in `tools/ai_tuning/` moved to `src/ai/tuning/`
- Many nimble tasks broken due to path changes
- Unclear separation between analysis, testing, tuning, and diagnostic tools

### Directory Inventory

#### src/ai/analysis/ (NEW - formerly tests/balance/)
**Purpose:** Test harness for balance analytics and simulation
**Contents:**
- `diagnostics.nim` - Core diagnostic metrics system (56KB, 2000+ lines)
- `run_simulation.nim` - Main simulation runner
- `balance_framework.nim` - Balance test framework
- `game_setup.nim` - Test game initialization
- `test_*.nim` - Various test scenarios (economy, strategy, turn reports, minimal)
- `analyze_results.nim` - Nim-based analysis
- `parallel_sim.nim` - Parallel simulation runner
- Python scripts:
  - `analyze_fleet_composition.py`
  - `run_comprehensive_tests.py`
  - `test_all_acts_all_sizes.py`

#### src/ai/tuning/ (NEW - formerly tools/ai_tuning/)
**Purpose:** Parameter optimization and genetic algorithms
**Contents:**
- Genetic evolution (Nim): `genetic_ai.nim`, `evolve_ai.nim`, `coevolution.nim`
- Python analysis scripts (19 files):
  - `analyze_*.py` (12 different analyzers)
  - `run_parallel_diagnostics.py`
  - `convert_to_parquet.py`
  - `generate_summary.py`
  - `manage_archives.py`
  - `debug_*.py` utilities

#### scripts/ (ROOT)
**Purpose:** Project-wide utility scripts
**Contents:**
- `check_formatting.py` - Documentation quality
- `halve_tech_costs.py` - Config manipulation
- `run_balance_test_parallel.py` - Parallel test runner
- `run_map_size_test.py` - Map testing
- `run_stress_test.py` - Stress testing

#### balance_tuning/ (ROOT)
**Purpose:** Statistical parameter sweeping
**Contents:**
- `analyze_balance.py` - Balance metrics analyzer
- `sweep_parameters.py` - Parameter sweep tool
- `sweep_results/` - Sweep output directory

#### analysis/ (ROOT)
**Purpose:** Polars-based data analysis CLI
**Contents:**
- `balance_analyzer.py` (24KB) - Core analysis engine
- `cli.py` (11KB) - Command-line interface
- `reports.py` (7KB) - Report generation
- `__init__.py` - Package initialization

### Broken Nimble Tasks

The following tasks reference old paths and are broken:

```nim
# Reference tools/ai_tuning/* (moved to src/ai/tuning/)
- listArchives (line 323)
- archiveStats (line 327)
- pruneArchives (line 331)
- testBalanceDiagnostics (line 340)
- testUnknownUnknowns (line 349-353)
- analyzeDiagnostics (line 360)
- analyzeProgression (line 364)
- summarizeDiagnostics (line 368-372)
- convertToParquet (line 376)
- analyzePerformance (line 383)
- balanceDiagnostic (line 390-392)
- balanceQuickCheck (line 399-401)
- analyzeBalance (line 406-419)
- tuneAIDiagnostics (line 528-532)
- buildAITuning (line 500-505)
- evolveAI (line 509-511)
- evolveAIQuick (line 515-517)
- coevolveAI (line 521-523)

# Reference tests/balance/* (moved to src/ai/analysis/)
- buildBalance (line 230-233)
- testBalanceQuick (line 240-241)
- testBalanceAct1-4 (lines 249-277)
- testBalanceAll4Acts (line 285-296)
- cleanBalance (line 300-305)
```

## Core Use Cases

### 1. Run Full Game Simulations
**Current:** `src/ai/analysis/run_simulation.nim` + various test files
**Use:** Generate game data for balance analysis

### 2. Collect Diagnostic Metrics
**Current:** `src/ai/analysis/diagnostics.nim` (outputs CSV)
**Use:** Per-turn, per-house metrics for pattern detection

### 3. Analyze Diagnostic Data
**Current:**
- Polars CLI (`analysis/cli.py`)
- Tuning scripts (`src/ai/tuning/analyze_*.py`)
**Use:** Query, aggregate, visualize diagnostic CSVs/Parquet

### 4. Optimize AI Parameters
**Current:** `src/ai/tuning/{genetic_ai,evolve_ai,coevolution}.nim`
**Use:** Genetic algorithms for AI personality tuning

### 5. Balance Engine Parameters
**Current:** `balance_tuning/sweep_parameters.py`
**Use:** Grid search for optimal config values

### 6. Generate Reports
**Current:** `analysis/reports.py`, various `generate_*.py`
**Use:** Markdown/JSON reports for analysis

## Recommended Consolidation Strategy

### Phase 1: Unified CLI Tool Architecture

Create a single command-line application: **`ec4x-analyze`**

```
ec4x-analyze
├── simulate      # Run game simulations (from src/ai/analysis/*.nim)
│   ├── single    # Single game with diagnostics
│   ├── batch     # Parallel batch simulations
│   ├── acts      # 4-act progression tests
│   └── stress    # Stress testing
│
├── analyze       # Analyze diagnostic data (from analysis/*.py + src/ai/tuning/analyze_*.py)
│   ├── summary   # Quick terminal summary
│   ├── by-house  # Aggregate by house
│   ├── by-turn   # Aggregate by turn
│   ├── outliers  # Detect anomalies
│   ├── phase2    # Phase 2 gap analysis
│   ├── combat    # Combat analysis
│   ├── economy   # Economic analysis
│   ├── territory # Territory control
│   └── custom    # Custom queries
│
├── optimize      # Parameter optimization (from src/ai/tuning/*.nim + balance_tuning/)
│   ├── sweep     # Grid search parameters
│   ├── evolve    # Genetic AI evolution
│   └── coevolve  # Competitive co-evolution
│
├── report        # Generate reports (from analysis/reports.py)
│   ├── markdown  # Git-committable reports
│   ├── json      # Machine-readable summaries
│   └── export    # CSV for Excel/LibreOffice
│
└── data          # Data management (from src/ai/tuning/manage_archives.py, convert_to_parquet.py)
    ├── convert   # CSV → Parquet conversion
    ├── archive   # Manage restic archives
    └── clean     # Clean old data
```

### Phase 2: Directory Structure

```
src/ai/
├── analysis/              # Simulation & test framework (Nim + Python)
│   ├── core/             # Core Nim modules
│   │   ├── diagnostics.nim
│   │   ├── simulation.nim
│   │   ├── framework.nim
│   │   └── game_setup.nim
│   ├── tests/            # Test scenarios
│   │   ├── test_economy_balance.nim
│   │   ├── test_strategy_balance.nim
│   │   └── test_turn_reports.nim
│   ├── python/           # Python analysis modules
│   │   ├── __init__.py
│   │   ├── diagnostics.py     # Diagnostic data loader
│   │   ├── aggregation.py     # Aggregation functions
│   │   ├── visualization.py   # Plotting utilities
│   │   └── queries.py         # Common queries
│   └── README.md
│
├── tuning/               # Parameter optimization (Nim + Python)
│   ├── genetic/          # Genetic algorithms (Nim)
│   │   ├── genetic_ai.nim
│   │   ├── evolve_ai.nim
│   │   └── coevolution.nim
│   ├── sweep/            # Parameter sweeping (Python)
│   │   ├── sweep_engine.py
│   │   └── balance_metrics.py
│   └── README.md
│
└── cli/                  # Unified CLI tool
    ├── ec4x_analyze.py   # Main CLI entry point
    ├── commands/         # Command implementations
    │   ├── __init__.py
    │   ├── simulate.py
    │   ├── analyze.py
    │   ├── optimize.py
    │   ├── report.py
    │   └── data.py
    └── README.md

tools/                    # REMOVED - consolidated into src/ai/
scripts/                  # Keep for project-wide utilities
├── sync_specs.py         # TOML → docs sync
├── check_formatting.py   # Doc quality
└── setup_hooks.sh        # Git hooks

balance_tuning/           # REMOVE - move to src/ai/tuning/sweep/
analysis/                 # REMOVE - move to src/ai/analysis/python/

balance_results/          # Keep as-is (gitignored data directory)
└── diagnostics/
```

### Phase 3: Python Package Structure

Create proper Python package: `ec4x_analysis`

```python
# src/ai/cli/setup.py
from setuptools import setup, find_packages

setup(
    name="ec4x-analysis",
    version="0.1.0",
    packages=find_packages(),
    install_requires=[
        "polars>=0.19.0",
        "pyarrow>=13.0.0",
        "click>=8.1.0",  # For CLI
    ],
    entry_points={
        "console_scripts": [
            "ec4x-analyze=ec4x_analysis.cli.main:main",
        ],
    },
)
```

### Phase 4: Nimble Task Updates

```nim
# Simulation Tasks (src/ai/analysis/)
task analyzeRun, "Run single game with diagnostics":
  exec "nim c -r src/ai/analysis/core/simulation.nim --diagnostics"

task analyzeQuick, "Quick validation (20 games, 7 turns)":
  exec "python3 -m ec4x_analysis simulate batch --games 20 --turns 7"

task analyzeActs, "4-act progression tests":
  exec "python3 -m ec4x_analysis simulate acts"

# Analysis Tasks (unified CLI)
task analyzeSummary, "Quick diagnostic summary":
  exec "python3 -m ec4x_analysis analyze summary"

task analyzePhase2, "Phase 2 gap analysis":
  exec "python3 -m ec4x_analysis analyze phase2"

task analyzeReport, "Generate markdown report":
  exec "python3 -m ec4x_analysis report markdown"

# Optimization Tasks (src/ai/tuning/)
task tuneEvolve, "Evolve AI personalities (50 gen, 20 pop)":
  exec "nim c -r src/ai/tuning/genetic/evolve_ai.nim"

task tuneSweep, "Parameter sweep optimization":
  exec "python3 -m ec4x_analysis optimize sweep"

# Data Management
task dataConvert, "Convert CSV to Parquet":
  exec "python3 -m ec4x_analysis data convert"

task dataClean, "Clean diagnostic data":
  exec "python3 -m ec4x_analysis data clean"
```

## Migration Plan

### Step 1: Create new structure (non-breaking)
1. Create `src/ai/cli/` directory
2. Create `src/ai/analysis/python/` subdirectory
3. Create `src/ai/tuning/sweep/` subdirectory
4. Leave existing files in place (don't break anything yet)

### Step 2: Build unified CLI
1. Implement `ec4x_analysis` Python package
2. Implement command structure
3. Wire up existing Python scripts as commands
4. Test each command against existing functionality

### Step 3: Consolidate Python scripts
1. Move `analysis/*.py` → `src/ai/analysis/python/`
2. Move `balance_tuning/*.py` → `src/ai/tuning/sweep/`
3. Refactor `src/ai/tuning/analyze_*.py` into modular functions
4. Update imports across all files

### Step 4: Update nimble tasks
1. Replace all `tools/ai_tuning/` references with `src/ai/tuning/`
2. Replace all `tests/balance/` references with `src/ai/analysis/`
3. Replace direct Python script calls with `python3 -m ec4x_analysis`
4. Test each nimble task

### Step 5: Clean up
1. Remove `balance_tuning/` directory
2. Remove `analysis/` directory
3. Remove `tools/ai_tuning/` (if it exists)
4. Update all documentation
5. Commit cleanup

## Benefits

### Before (Current State)
- 5 different locations for Python scripts
- 19 broken nimble tasks
- Unclear purpose for each directory
- Duplicate functionality (multiple analyzers)
- No unified interface
- Hard to discover features

### After (Proposed State)
- Single CLI tool: `ec4x-analyze`
- All nimble tasks working
- Clear separation: simulation (Nim) + analysis (Python) + tuning (both)
- Unified command interface
- Easy to extend with new commands
- Self-documenting (`ec4x-analyze --help`)

## Questions to Resolve

1. **Should diagnostics.nim stay in analysis/ or move to engine/?**
   - Current: `src/ai/analysis/diagnostics.nim`
   - Alternative: `src/engine/diagnostics.nim` (engine subsystem)
   - Recommendation: Keep in analysis/ (it's testing infrastructure)

2. **Should we keep balance_results/ at root or move to src/ai/?**
   - Current: `balance_results/` (root)
   - Alternative: `src/ai/analysis/results/`
   - Recommendation: Keep at root (gitignored, not source code)

3. **What to do with scripts/ directory?**
   - Keep for project-wide utilities (sync_specs.py, setup_hooks.sh)
   - Move game-specific scripts to CLI tool
   - Current scripts to move: `run_balance_test_parallel.py`, `run_map_size_test.py`

4. **Single Python package or keep Nim separate?**
   - Option A: `ec4x-analyze` (Python) + separate Nim binaries
   - Option B: All-in-one CLI that calls Nim when needed
   - Recommendation: Option B (unified experience)

5. **Version control for analysis scripts during development?**
   - Create feature branch for consolidation
   - Merge when all nimble tasks pass
   - Keep old structure in git history

## Next Steps

1. Review and approve this plan
2. Answer outstanding questions
3. Create feature branch: `consolidate-analysis-tools`
4. Implement Step 1 (create structure)
5. Implement Step 2 (build CLI)
6. Test thoroughly
7. Continue with Steps 3-5

## Success Criteria

- [ ] All nimble tasks execute successfully
- [ ] `ec4x-analyze --help` shows all commands
- [ ] All existing analysis workflows still work
- [ ] Zero duplicate Python scripts
- [ ] Documentation updated
- [ ] README in each directory explains purpose
- [ ] Can run full analysis workflow end-to-end:
  ```bash
  # Simulate
  ec4x-analyze simulate batch --games 100 --turns 30

  # Analyze
  ec4x-analyze analyze summary
  ec4x-analyze analyze phase2

  # Report
  ec4x-analyze report markdown --output analysis_report.md
  ```

---

**Status:** Draft - awaiting review and discussion
**Author:** Claude Code
**Date:** 2025-12-02
