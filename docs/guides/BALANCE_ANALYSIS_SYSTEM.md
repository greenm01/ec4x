# Balance Analysis System Guide

**Terminal-Based Data Analysis for RBA Tuning**

This guide shows you how to use the EC4X Balance Analysis System to tune and balance the RBA AI on your own and with Claude assistance.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [System Architecture](#system-architecture)
3. [Workflow](#workflow)
4. [Best Practices](#best-practices)
5. [Tips for Solo Tuning](#tips-for-solo-tuning)
6. [Tips for Claude-Assisted Tuning](#tips-for-claude-assisted-tuning)
7. [Command Reference](#command-reference)
8. [Troubleshooting](#troubleshooting)

---

## Quick Start

### 1. Generate Diagnostic Data

```bash
# Quick validation (20 games, ~10 seconds)
nimble testBalanceQuick

# Full diagnostics (50 games, ~2 minutes)
nimble testBalanceDiagnostics

# Unknown-unknowns detection (200 games, ~8 minutes)
nimble testUnknownUnknowns
```

**Output:** `balance_results/diagnostics/game_*.csv` (one per game)

### 2. Analyze Data

```bash
# Full workflow: CSV → Parquet → Analysis → Report
nimble analyzeBalance

# Or run individual steps:
nimble balanceSummary      # Quick overview
nimble balancePhase2       # Phase 2 gap analysis
nimble balanceOutliers     # Outlier detection
nimble balanceReport       # Generate markdown report
```

**Output:**
- `balance_results/diagnostics_combined.parquet` (fast loading)
- `balance_results/analysis_report.md` (git-committable)

### 3. Export for Excel

```bash
nimble balanceExport

# Opens: balance_results/summary_by_house.csv
# Use Excel/LibreOffice for pivot tables and charts
```

---

## System Architecture

### Data Pipeline

```
┌─────────────────────┐
│ Nim Test Simulation │  ← nimble testBalanceDiagnostics
│  (tests/balance/)   │
└──────────┬──────────┘
           │ generates
           ▼
┌─────────────────────┐
│  CSV Diagnostics    │  balance_results/diagnostics/game_*.csv
│  (156 fields/house) │  (~40KB per game)
└──────────┬──────────┘
           │ convert_to_parquet.py (parallel loading)
           ▼
┌─────────────────────┐
│ Parquet Format      │  balance_results/diagnostics_combined.parquet
│  (3-5x compression) │  (instant loading, Excel compatible)
└──────────┬──────────┘
           │ analysis.cli / analysis.reports
           ▼
┌─────────────────────┐
│ Terminal Output     │  Rich tables, panels, colored text
│ + Markdown Reports  │  analysis_report.md (git commit)
│ + CSV Exports       │  summary_by_house.csv (Excel)
└─────────────────────┘
```

### Key Components

1. **convert_to_parquet.py** - Fast parallel CSV → Parquet conversion
2. **analysis/balance_analyzer.py** - Core Polars analysis engine
3. **analysis/cli.py** - Terminal interface (Click + Rich)
4. **analysis/reports.py** - Markdown report generation
5. **Nimble tasks** - Integrated workflow automation

---

## Workflow

### Iterative Tuning Cycle

```
1. Run diagnostics     → nimble testBalanceDiagnostics
2. Analyze results     → nimble balancePhase2
3. Identify issues     → nimble balanceOutliers
4. Tune RBA config     → Edit config/rba.toml
5. Test changes        → nimble testBalanceQuick
6. Repeat until ✅
```

### Full Analysis Session

```bash
# 1. Generate fresh data
nimble testBalanceDiagnostics  # 50 games, ~2 min

# 2. Quick overview
nimble balanceSummary
# Output: Games, houses, turns, git hash

# 3. Phase 2 gap analysis
nimble balancePhase2
# Output: Fighter/carrier system, scouts, espionage, defense

# 4. Detect anomalies
nimble balanceOutliers
# Output: Z-score outliers for fighters, capacity violations, invalid orders

# 5. Export for deep dive
nimble balanceExport
# Opens Excel with pivot-ready data

# 6. Generate report
nimble balanceReport
# Output: balance_results/analysis_report.md (commit to git)
```

---

## Best Practices

### 1. Always Use Nimble Tasks

❌ **DON'T:**
```bash
python3 tools/ai_tuning/analyze_phase2_gaps.py  # May use stale data
```

✅ **DO:**
```bash
nimble balancePhase2  # Ensures correct workflow
```

**Why:** Nimble tasks ensure proper dependencies and data freshness.

### 2. Commit Analysis Reports to Git

```bash
nimble balanceReport
git add balance_results/analysis_report.md
git commit -m "balance: Analysis of RBA Phase 2 improvements"
```

**Why:** Track balance evolution over time. Helps Claude understand historical changes.

### 3. Use Parquet for Speed

```bash
# First time: Convert CSV → Parquet (~2 seconds)
nimble convertToParquet

# Then: Fast analysis (no CSV parsing)
nimble balanceSummary        # <0.1s
nimble balancePhase2         # <0.5s
```

**Why:** Parquet loads 100x faster than CSV. Takes advantage of your 32-core CPU.

### 4. Focus on Phase 2 Metrics

**Critical metrics to watch:**
- `capacity_violation_rate` - Should be 0% (fighter/carrier system)
- `espionage_usage_rate` - Should be 100% (all games use espionage)
- `idle_carrier_rate` - Should be <5% (carriers auto-load fighters)
- `invasions_with_eli` - Should be >80% (ELI mesh coordination)

**How to check:**
```bash
nimble balancePhase2  # Shows all Phase 2 metrics with targets
```

### 5. Detect Outliers Early

```bash
# Check key metrics for anomalies
nimble balanceOutliers

# Or specific metric:
python3 -m analysis.cli outliers total_fighters --threshold 2.5
```

**Why:** Outliers reveal edge cases and bugs before they become systemic issues.

### 6. Export to Excel for Pivot Analysis

```bash
nimble balanceExport
# Opens: balance_results/summary_by_house.csv
```

**In Excel/LibreOffice:**
1. Insert → Pivot Table
2. Rows: house
3. Values: total_fighters_mean, capacity_violations_sum, etc.
4. Look for imbalanced houses (one house dominates)

---

## Tips for Solo Tuning

### Finding the Right Balance

1. **Start with diagnostics**
   ```bash
   nimble testBalanceDiagnostics  # 50 games baseline
   nimble balancePhase2           # Check current status
   ```

2. **Identify the biggest issue**
   - Look at Phase 2 analysis: Which metrics are failing?
   - Example: "Espionage usage: 45%" → RBA not using espionage enough

3. **Edit config/rba.toml**
   ```toml
   # Increase espionage budget allocation
   [budget.act1]
   espionage = 0.10  # Was 0.05, now doubled
   ```

4. **Quick test the change**
   ```bash
   nimble testBalanceQuick  # 20 games, fast validation
   nimble balancePhase2     # Did espionage usage improve?
   ```

5. **If improved, run full test**
   ```bash
   nimble testBalanceDiagnostics  # 50 games
   nimble balanceReport           # Document improvement
   git add config/rba.toml balance_results/analysis_report.md
   git commit -m "balance: Increase espionage budget allocation"
   ```

### Common Tuning Patterns

**Problem: Low fighter production**
```toml
[budget.act2]
ships = 0.40  # Increase from 0.35
```

**Problem: High capacity violations**
```toml
[orders]
max_fighter_orders = 3  # Reduce from 5 (build fewer at once)
```

**Problem: Undefended colonies**
```toml
[strategic]
defense_threshold = 0.30  # Lower from 0.40 (defend more aggressively)
```

**Problem: Idle carriers**
```toml
[tactical]
carrier_response_radius = 5.0  # Increase from 3.0 (load from further away)
```

### Workflow for Systematic Tuning

```bash
# 1. Baseline measurement
nimble testBalanceDiagnostics
nimble balanceReport
cp balance_results/analysis_report.md docs/milestones/baseline_$(date +%Y%m%d).md

# 2. For each Phase 2 issue:
#    a. Edit config/rba.toml
#    b. Test: nimble testBalanceQuick
#    c. Validate: nimble balancePhase2
#    d. If good: git commit

# 3. Final validation
nimble testUnknownUnknowns  # 200 games, comprehensive
nimble balanceReport
git add balance_results/analysis_report.md
git commit -m "balance: Phase 2 tuning complete"
```

---

## Tips for Claude-Assisted Tuning

### Preparing Data for Claude

**Goal:** Minimize tokens, maximize insight

#### Option 1: Share Markdown Report (~1-2K tokens)

```bash
nimble balanceReport
# Share: balance_results/analysis_report.md with Claude
```

**Benefits:**
- ✅ ~1000x token reduction vs raw CSV (5KB vs 5MB)
- ✅ Human-readable summary
- ✅ Git-committable for version tracking
- ✅ Includes Phase 2 metrics + outliers

#### Option 2: Share Parquet File (~500 tokens to describe)

```bash
nimble convertToParquet
# Share: balance_results/diagnostics_combined.parquet with Claude
```

**Benefits:**
- ✅ Claude can use Polars to analyze (Phase 3+ capability)
- ✅ Full dataset for custom queries
- ✅ 3-5x smaller than CSV

#### Option 3: Share Terminal Output (copy/paste)

```bash
nimble balancePhase2 | tee phase2_results.txt
# Copy phase2_results.txt to Claude
```

**Benefits:**
- ✅ Fastest (no file upload)
- ✅ Shows exactly what you see
- ✅ Good for quick questions

### Effective Prompts for Claude

**Bad prompt (wastes tokens):**
> "Here are 50 CSV files with diagnostic data. What should I tune?"

**Good prompt (token-efficient):**
> "I ran `nimble balancePhase2` and got these results:
> ```
> [paste terminal output]
> ```
>
> Key issue: Espionage usage is 45% (target: 100%).
>
> Current config:
> ```toml
> [budget.act1]
> espionage = 0.05
> ```
>
> Should I increase this? What side effects might occur?"

**Best prompt (provides context + data):**
> "I'm tuning RBA espionage usage. Baseline:
> - Espionage usage: 45% of games (target: 100%)
> - Current budget: 5% in Act 1, 8% in Act 2
> - No outliers detected (checked with `nimble balanceOutliers`)
>
> Markdown report attached: analysis_report.md
>
> Question: Should I increase espionage budget linearly, or focus on early-game Act 1 only?"

### Iteration Loop with Claude

```
1. You: Run nimble balancePhase2, share results
2. Claude: Suggests config changes + explains reasoning
3. You: Edit config/rba.toml, run nimble testBalanceQuick
4. You: Share new results ("Espionage usage improved to 78%!")
5. Claude: Suggests refinement or next issue to tackle
6. Repeat until all Phase 2 metrics pass ✅
```

### Asking Claude for Custom Analysis

**Example 1: House imbalance**
```bash
nimble balanceByHouse > house_summary.txt
# Share with Claude: "House Red wins 60% of games. Is this a balance issue?"
```

**Example 2: Turn-by-turn progression**
```bash
nimble balanceByTurn > turn_progression.txt
# Share with Claude: "Fighter production drops after turn 15. Why?"
```

**Example 3: Outlier investigation**
```bash
python3 -m analysis.cli outliers zero_spend_turns --threshold 2.5 > outliers.txt
# Share with Claude: "3 houses have chronic treasury hoarding. Root cause?"
```

### Using Claude for Config Exploration

**Prompt template:**
> "I want to test different espionage budget allocations:
> - Baseline: [0.05, 0.08, 0.10, 0.12] (Act 1-4)
> - Option A: [0.10, 0.10, 0.08, 0.08] (front-loaded)
> - Option B: [0.05, 0.10, 0.15, 0.15] (back-loaded)
>
> Which should I test first? Generate the TOML config for Option A."

Claude will generate:
```toml
[budget.act1]
espionage = 0.10  # Front-loaded

[budget.act2]
espionage = 0.10

[budget.act3]
espionage = 0.08

[budget.act4]
espionage = 0.08
```

Then you:
```bash
# Save Claude's config to config/rba.toml
nimble testBalanceQuick  # Test it
nimble balancePhase2     # Check results
# Share results with Claude for comparison
```

---

## Command Reference

### Core Workflow Commands

```bash
# Testing & Data Generation
nimble testBalanceQuick          # 20 games, 7 turns (~10s)
nimble testBalanceDiagnostics    # 50 games, 30 turns (~2 min)
nimble testUnknownUnknowns       # 200 games, comprehensive (~8 min)

# Data Conversion
nimble convertToParquet          # CSV → Parquet (parallel loading)

# Analysis
nimble analyzeBalance            # Full workflow (convert + analyze + report)
nimble balanceSummary            # Quick dataset overview
nimble balancePhase2             # Phase 2 gap analysis
nimble balanceOutliers           # Outlier detection (key metrics)
nimble balanceByHouse            # Aggregate by house
nimble balanceByTurn             # Aggregate by turn

# Export
nimble balanceExport             # CSV for Excel/LibreOffice
nimble balanceReport             # Markdown report (git-committable)

# Cleanup
nimble cleanBalance              # Remove test artifacts
nimble cleanDiagnostics          # Remove CSV files only (keep Parquet)
```

### Advanced CLI Commands

```bash
# Custom outlier detection
python3 -m analysis.cli outliers <metric> --threshold 3.0 --by-house

# Custom aggregations
python3 -m analysis.cli by-house --metrics total_fighters total_carriers

# Custom exports
python3 -m analysis.cli export output.csv --type raw --metrics total_fighters
```

### Python API (Advanced)

```python
from analysis import BalanceAnalyzer

# Load data
analyzer = BalanceAnalyzer("balance_results/diagnostics_combined.parquet")

# Get metadata
metadata = analyzer.get_metadata()
print(f"Games: {metadata['num_games']}, Git: {metadata['git_hash']}")

# Summary statistics
summary = analyzer.summary_by_house()
print(summary)

# Outlier detection
outliers = analyzer.detect_outliers_zscore("total_fighters", threshold=2.5)
print(f"Found {len(outliers)} outliers")

# Phase 2 analysis
phase2 = analyzer.analyze_phase2_gaps()
print(phase2["overall_status"])

# Export to Excel
analyzer.export_for_excel("my_summary.csv", summary_type="by_house")
```

---

## Troubleshooting

### "ERROR: Polars not installed"

**Fix:** Exit and re-enter the nix shell
```bash
exit         # Exit current shell
nix develop  # Re-enter with updated dependencies
```

### "ERROR: Parquet file not found"

**Fix:** The analysis tasks now auto-convert CSV to Parquet on first run.
If this fails, manually run:
```bash
nimble convertToParquet  # Generates Parquet from CSV
nimble balanceSummary    # Now works
```

**Why it works:** The converter creates a compressed Parquet file (31.2x compression)
that loads 100x faster than CSV parsing.

### "No CSV files found in diagnostics directory"

**Fix:** Generate diagnostic data first
```bash
nimble testBalanceDiagnostics  # Generates CSV files
nimble convertToParquet         # Converts to Parquet
```

### Analysis shows outdated data

**Fix:** Always use nimble tasks (ensures clean rebuild)
```bash
nimble testBalanceDiagnostics  # Forces --forceBuild
nimble balancePhase2           # Analyzes fresh data
```

### Slow analysis performance

**Check:** Are you using Parquet or CSV?
```bash
# Slow (CSV parsing every time)
python3 tools/ai_tuning/analyze_phase2_gaps.py

# Fast (Parquet, parallel processing)
nimble balancePhase2
```

### Excel file won't open / encoding issues

**Fix:** Use UTF-8 encoding
```bash
nimble balanceExport  # Generates UTF-8 CSV
# In LibreOffice: Open → Character set: UTF-8
```

---

## Performance Tips

### Leveraging Your 32-Core CPU

The analysis system automatically uses all CPU cores via Polars:

```bash
# Parallel CSV loading (uses all 32 cores)
nimble convertToParquet  # Loads 50 files in parallel

# Parallel aggregation (uses all 32 cores)
nimble balanceByHouse    # Polars parallelizes automatically
```

**Expected performance:**
- Convert 200 CSVs → Parquet: **<2 seconds**
- Load Parquet for analysis: **<0.1 seconds**
- Phase 2 gap analysis: **<0.5 seconds**
- Generate markdown report: **<1 second**

### Workflow Optimization

```bash
# Slow workflow (re-parses CSV every time)
nimble testBalanceDiagnostics
python3 tools/ai_tuning/analyze_phase2_gaps.py  # Parse 50 CSVs
python3 tools/ai_tuning/generate_summary.py     # Parse 50 CSVs again

# Fast workflow (parse once, analyze many times)
nimble testBalanceDiagnostics  # Generate CSVs
nimble convertToParquet        # Parse once → Parquet
nimble balanceSummary          # <0.1s
nimble balancePhase2           # <0.5s
nimble balanceOutliers         # <0.5s
nimble balanceReport           # <1s
```

---

## Next Steps

1. **Try the quick start workflow** (top of this guide)
2. **Read `/docs/ai/RBA_OPTIMIZATION_GUIDE.md`** for RBA internals
3. **Check `/docs/testing/BALANCE_METHODOLOGY.md`** for testing philosophy
4. **Review `config/rba.toml`** to understand tunable parameters
5. **Start with `nimble testBalanceQuick`** for fast iteration

---

**Questions? Check:**
- `/docs/ai/README.md` - AI system overview
- `/docs/testing/README.md` - Testing methodology
- `CLAUDE_CONTEXT.md` - Session context for Claude
- `TODO.md` - Current project status

**Report issues:**
- GitHub: https://github.com/greenm01/ec4x/issues
