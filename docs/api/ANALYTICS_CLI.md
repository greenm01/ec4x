# EC4X Analytics CLI Reference

The Analytics CLI is a Python-based terminal interface for analyzing balance test results from RBA simulations. It provides statistical analysis, outlier detection, and data export capabilities.

## Table of Contents
1. [Quick Start](#quick-start)
2. [Installation](#installation)
3. [Commands](#commands)
4. [Common Workflows](#common-workflows)
5. [Export Formats](#export-formats)
6. [Integration with RBA](#integration-with-rba)

## Quick Start

```bash
# Run balance tests to generate data
nimble testBalance

# View summary of results
python3 analysis/cli.py summary

# Analyze by house
python3 analysis/cli.py by-house

# Run phase 2 gap analysis
python3 analysis/cli.py phase2

# Export for spreadsheet analysis
python3 analysis/cli.py export summary.csv
```

## Installation

The Analytics CLI requires Python dependencies provided by the Nix shell:

```bash
# Enter the development environment
nix develop

# Verify installation
python3 -m analysis.cli --help
```

**Required packages** (provided by Nix):
- `click` - CLI framework
- `rich` - Terminal formatting
- `polars` - Fast dataframe operations
- `pyarrow` - Parquet file handling

## Commands

### `summary` - Dataset Overview

Shows quick statistics about the balance test dataset.

```bash
python3 analysis/cli.py summary
```

**Output**:
- Parquet file path and git hash
- Number of games and houses
- Total turns and turns per game

**Example**:
```
┌─ Balance Analysis Summary ──────────────────┐
│ Dataset Info:                                │
│   • Parquet: balance_results/...parquet      │
│   • Git hash: abc123def                      │
│   • Timestamp: 2025-01-15 14:30:00           │
│                                              │
│ Statistics:                                  │
│   • Games: 100                               │
│   • Houses: 6                                │
│   • Total turns: 3,240                       │
│   • Turns/game: 32.4                         │
└──────────────────────────────────────────────┘
```

### `by-house` - House Aggregation

Aggregates metrics by house across all games.

```bash
# Show all metrics for all houses
python3 analysis/cli.py by-house

# Show specific metrics
python3 analysis/cli.py by-house -m total_fighters -m tech_wep -m prestige

# Limit number of rows
python3 analysis/cli.py by-house --limit 5
```

**Options**:
- `--metrics, -m` - Select specific metrics (repeatable)
- `--limit, -n` - Number of rows to display (default: 10)

**Common metrics**:
- `total_fighters` - Total fighter squadrons
- `total_capital` - Capital ship count
- `treasury` - Available credits
- `tech_wep`, `tech_cst` - Tech levels
- `prestige` - Prestige score
- `total_pop` - Total population
- `income` - Income per turn

### `by-turn` - Turn Aggregation

Aggregates metrics by turn number across all games.

```bash
# Show all metrics by turn
python3 analysis/cli.py by-turn

# Show specific metrics
python3 analysis/cli.py by-turn -m total_fighters -m total_capital

# Show first 30 turns
python3 analysis/cli.py by-turn --limit 30
```

**Options**:
- `--metrics, -m` - Select specific metrics (repeatable)
- `--limit, -n` - Number of rows to display (default: 20)

**Use case**: Track game progression and identify imbalanced phases.

### `outliers` - Anomaly Detection

Detects statistical outliers using z-score analysis.

```bash
# Find outliers in fighter count (global)
python3 analysis/cli.py outliers total_fighters

# Use stricter threshold
python3 analysis/cli.py outliers total_fighters --threshold 2.5

# Compute per-house z-scores
python3 analysis/cli.py outliers treasury --by-house

# Show more outliers
python3 analysis/cli.py outliers prestige --limit 50
```

**Arguments**:
- `METRIC` - Metric to analyze (required)

**Options**:
- `--threshold, -t` - Z-score threshold (default: 3.0)
- `--by-house` - Compute z-scores per house instead of globally
- `--limit, -n` - Number of outliers to display (default: 20)

**Interpretation**:
- **Z-score > 3**: Likely anomaly (3σ from mean)
- **Z-score > 5**: Definite anomaly
- Use `--by-house` to detect house-specific anomalies

### `phase2` - Gap Analysis

Runs comprehensive Phase 2 validation checks.

```bash
python3 analysis/cli.py phase2
```

**Checks performed**:
- Economy balance (income vs maintenance)
- Combat effectiveness (fleet survival rates)
- Tech progression (research speed)
- Prestige scoring (balance between houses)
- Population growth (colonization viability)

**Output**:
```
✓ PHASE2.ECONOMY.INCOME
  income_mean: 1250.5
  income_std: 342.1
  status: pass

✗ PHASE2.COMBAT.LOSSES
  capital_loss_rate: 0.45
  expected_range: 0.20-0.35
  status: fail

🚨 Anomalies Detected:
  🚨 critical_error: Excessive capital ship losses in turn 15-20
  ⚠ warning: Tech level variance exceeds threshold
```

**Status indicators**:
- `✓` (green) - Pass
- `✗` (yellow) - Fail
- `🚨` (red) - Critical fail
- `⚠` (dim) - Not implemented

### `export` - CSV Export

Exports data to CSV for spreadsheet analysis.

```bash
# Export house summary
python3 analysis/cli.py export house_summary.csv

# Export turn summary
python3 analysis/cli.py export turn_summary.csv --type by_turn

# Export raw data with specific metrics
python3 analysis/cli.py export raw.csv --type raw -m total_fighters -m treasury
```

**Arguments**:
- `OUTPUT` - Output CSV file path (required)

**Options**:
- `--type, -t` - Export type: `by_house`, `by_turn`, `raw` (default: `by_house`)
- `--metrics, -m` - Metrics to include (default: all)

**Use case**: Import into Excel/LibreOffice for custom analysis and charting.

### `export-for-claude` - Token-Efficient Export

Exports data optimized for Claude Code analysis with token estimation.

```bash
# Export as markdown table
python3 analysis/cli.py export-for-claude combat.md --format markdown

# Export specific turns (10-20)
python3 analysis/cli.py export-for-claude turns_10_20.md --turns 10,20

# Filter by houses
python3 analysis/cli.py export-for-claude alpha.md --houses alpha --houses beta

# Export specific metrics
python3 analysis/cli.py export-for-claude econ.md -m treasury -m income -m maintenance

# Quick summary format (< 1K tokens)
python3 analysis/cli.py export-for-claude quick.txt --format summary

# Full JSON export
python3 analysis/cli.py export-for-claude full.json --format json
```

**Arguments**:
- `OUTPUT` - Output file path (required)

**Options**:
- `--format, -f` - Output format: `markdown`, `json`, `summary` (default: `markdown`)
- `--houses` - Filter by house names (repeatable)
- `--turns` - Turn range in format `start,end` (e.g., `10,20`)
- `--metrics, -m` - Metrics to include (default: important ones)

**Token estimates**:
- **Green** (< 5K tokens): Safe for analysis
- **Yellow** (5K-12K tokens): Moderate size
- **Red** (> 12K tokens): Consider filtering

**Example output**:
```
✓ Exported to combat.md
  File size: 12.4 KB
  Estimated tokens: ~3,240
```

## Common Workflows

### Workflow 1: Quick Health Check

```bash
# 1. Run quick balance test (20 games)
nimble testBalanceQuick

# 2. View summary
python3 analysis/cli.py summary

# 3. Run phase 2 validation
python3 analysis/cli.py phase2
```

**When to use**: Before committing changes, verify basic balance.

### Workflow 2: Full Balance Analysis

```bash
# 1. Run full balance test (100 games)
nimble testBalance

# 2. Check summary
python3 analysis/cli.py summary

# 3. Analyze by house
python3 analysis/cli.py by-house -m total_fighters -m treasury -m prestige

# 4. Detect outliers
python3 analysis/cli.py outliers total_fighters
python3 analysis/cli.py outliers treasury --by-house

# 5. Export for detailed review
python3 analysis/cli.py export-for-claude full_analysis.md --format markdown

# 6. Run phase 2 checks
python3 analysis/cli.py phase2
```

**When to use**: Major balance changes, pre-release validation.

### Workflow 3: Combat System Analysis

```bash
# 1. Run balance tests
nimble testBalance

# 2. Check fighter counts
python3 analysis/cli.py by-turn -m total_fighters -m total_capital --limit 50

# 3. Detect combat anomalies
python3 analysis/cli.py outliers total_fighters
python3 analysis/cli.py outliers capital_ships

# 4. Export combat data for Claude
python3 analysis/cli.py export-for-claude combat.md \
  --turns 10,25 \
  -m total_fighters -m total_capital -m fleet_power
```

**When to use**: Investigating combat balance issues.

### Workflow 4: Economy System Analysis

```bash
# 1. Check economy metrics by house
python3 analysis/cli.py by-house \
  -m treasury -m income -m maintenance -m total_pop

# 2. Track economy over time
python3 analysis/cli.py by-turn \
  -m treasury -m income -m maintenance --limit 40

# 3. Find economy outliers
python3 analysis/cli.py outliers treasury
python3 analysis/cli.py outliers income --by-house

# 4. Export for analysis
python3 analysis/cli.py export-for-claude economy.md \
  -m treasury -m income -m maintenance -m tax_rate
```

**When to use**: Economy system changes, income/maintenance tuning.

## Export Formats

### Markdown Format

Compact tables optimized for Claude Code analysis.

```markdown
# Balance Analysis Results

## Summary by House

| house   | total_fighters | treasury | prestige |
|---------|----------------|----------|----------|
| alpha   | 12.4           | 1250.3   | 340.2    |
| beta    | 11.8           | 1180.5   | 315.8    |
```

**Token efficiency**: ~0.3 tokens per cell

### JSON Format

Structured data for programmatic analysis.

```json
{
  "metadata": {
    "games": 100,
    "houses": 6,
    "timestamp": "2025-01-15T14:30:00"
  },
  "by_house": {
    "alpha": {
      "total_fighters": 12.4,
      "treasury": 1250.3
    }
  }
}
```

**Token efficiency**: ~1.2 tokens per value

### Summary Format

Ultra-compact text format (< 1K tokens).

```
Balance Test Summary (100 games, 6 houses)

Key Metrics (mean):
- Fighters: 12.1 ± 2.3
- Treasury: 1215.4 ± 340.2
- Prestige: 328.6 ± 45.1

Top Houses: alpha (350.2), beta (342.1), gamma (315.8)
```

**Token efficiency**: ~0.1 tokens per metric

## Integration with RBA

The Analytics CLI is designed to work seamlessly with RBA testing:

### Step 1: Configure RBA Test

Edit `tests/balance/run_simulation.nim`:
```nim
const NUM_GAMES = 100       # Full test
const ENABLE_DIAGNOSTICS = true  # Collect analytics data
```

### Step 2: Run Simulation

```bash
nimble testBalance
```

**Output location**: `balance_results/diagnostics_combined.parquet`

### Step 3: Analyze Results

```bash
# Quick check
python3 analysis/cli.py summary
python3 analysis/cli.py phase2

# Detailed analysis
python3 analysis/cli.py by-house
python3 analysis/cli.py outliers total_fighters
```

### Step 4: Export for Review

```bash
# For Claude analysis
python3 analysis/cli.py export-for-claude results.md

# For spreadsheet analysis
python3 analysis/cli.py export results.csv --type by_house
```

### Custom Parquet Files

Use `--parquet` to analyze custom result files:

```bash
python3 analysis/cli.py --parquet=custom_results.parquet summary
```

## Advanced Usage

### Filtering Large Datasets

When datasets are large (> 10K tokens), use filters:

```bash
# Focus on mid-game
python3 analysis/cli.py export-for-claude midgame.md --turns 15,25

# Specific houses only
python3 analysis/cli.py export-for-claude alpha_beta.md \
  --houses alpha --houses beta

# Minimal metrics
python3 analysis/cli.py export-for-claude minimal.md \
  -m total_fighters -m treasury -m prestige
```

### Combining Filters

```bash
# Ultra-focused analysis
python3 analysis/cli.py export-for-claude combat_alpha_t10-20.md \
  --houses alpha \
  --turns 10,20 \
  -m total_fighters -m total_capital -m fleet_power \
  --format markdown
```

**Token estimate**: ~500-1000 tokens

### Z-Score Tuning

Adjust threshold based on data quality:

```bash
# Strict (fewer false positives)
python3 analysis/cli.py outliers treasury --threshold 4.0

# Lenient (catch more anomalies)
python3 analysis/cli.py outliers treasury --threshold 2.0

# Per-house (catch house-specific issues)
python3 analysis/cli.py outliers treasury --threshold 2.5 --by-house
```

## Troubleshooting

### Error: "Required packages not installed"

**Solution**: Enter Nix shell
```bash
nix develop
```

### Error: "Failed to load parquet file"

**Causes**:
1. Balance tests not run yet
2. Diagnostics disabled in simulation

**Solution**:
```bash
# Verify diagnostics enabled in tests/balance/run_simulation.nim
const ENABLE_DIAGNOSTICS = true

# Run tests
nimble testBalance

# Verify file exists
ls -lh balance_results/diagnostics_combined.parquet
```

### Warning: "File is large for Claude"

**Solution**: Use filters to reduce size
```bash
# Instead of full export
python3 analysis/cli.py export-for-claude full.md

# Use filters
python3 analysis/cli.py export-for-claude focused.md \
  --turns 10,30 \
  --houses alpha --houses beta \
  -m total_fighters -m treasury -m prestige
```

## Further Reading

- [RBA_QUICKSTART.md](./RBA_QUICKSTART.md) - Running balance simulations
- [RBA_CONFIG_REFERENCE.md](./RBA_CONFIG_REFERENCE.md) - Configuring RBA behavior
- [ENGINE_QUICKSTART.md](./ENGINE_QUICKSTART.md) - Engine development patterns
- [Balance Analyzer Source](../../analysis/balance_analyzer.py) - Implementation details
