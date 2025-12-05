# EC4X Analysis Scripts

Python scripts for efficient analysis of game diagnostics using Polars.

## Setup

```bash
# Install dependencies
pip install -r scripts/analysis/requirements.txt

# Or use uv (faster)
uv pip install -r scripts/analysis/requirements.txt
```

## Quick Start

```bash
# Quick summary of all diagnostics
python scripts/analysis/analyze_diagnostics.py summary

# Strategy performance comparison
python scripts/analysis/analyze_diagnostics.py strategy

# Detect balance issues
python scripts/analysis/analyze_diagnostics.py red-flags

# Compare two strategies
python scripts/analysis/analyze_diagnostics.py compare Aggressive Economic

# Economic analysis
python scripts/analysis/analyze_diagnostics.py economy

# Military analysis
python scripts/analysis/analyze_diagnostics.py military
```

## Commands

### `summary`
Quick overview of all games including:
- Game count, turn count, strategies tested
- Final turn prestige, treasury, production by strategy
- Basic statistics (mean, min, max, std)

**Example:**
```bash
python scripts/analysis/analyze_diagnostics.py summary
```

### `strategy`
Detailed strategy performance analysis:
- Final turn comparison across all metrics
- Growth rates from start to finish
- Prestige and production trends

**Example:**
```bash
python scripts/analysis/analyze_diagnostics.py strategy --min-turn 10
```

### `economy`
Economic metrics analysis:
- Treasury, production, gross output by strategy
- Resource efficiency (PP per IU, prestige per PP)
- Economic red flags (deficits, zero-spend turns)

**Example:**
```bash
python scripts/analysis/analyze_diagnostics.py economy
```

### `military`
Military metrics analysis:
- Fleet composition by strategy
- Combat performance (wins, losses, win rate)
- Capacity violations and disbandments

**Example:**
```bash
python scripts/analysis/analyze_diagnostics.py military
```

### `research`
Research progression analysis:
- Final tech levels by strategy
- Total research investment (ERP, SRP, TRP)
- Research efficiency and waste

**Example:**
```bash
python scripts/analysis/analyze_diagnostics.py research
```

### `diplomacy`
Diplomatic relationship analysis:
- Diplomatic position (allies, enemies, neutrals)
- Diplomatic activity (pacts, wars, violations)

**Example:**
```bash
python scripts/analysis/analyze_diagnostics.py diplomacy
```

### `red-flags`
Automated detection of balance issues:
- Strategy dominance (>30% prestige advantage)
- Economic stagnation (zero-spend turns, low growth)
- Tech waste (>20% research points wasted)
- Capacity violations
- AI failures (autopilot, defensive collapse)

**Example:**
```bash
python scripts/analysis/analyze_diagnostics.py red-flags
```

### `compare`
Head-to-head strategy comparison:
- Side-by-side final metrics
- Percentage advantage calculation

**Example:**
```bash
python scripts/analysis/analyze_diagnostics.py compare Aggressive Economic
```

### `custom`
Execute custom Polars queries:
- Filter, select, group_by operations
- Full Polars DataFrame API access

**Examples:**
```bash
# Filter high prestige games
python scripts/analysis/analyze_diagnostics.py custom "filter(pl.col('prestige') > 500)"

# Select specific columns
python scripts/analysis/analyze_diagnostics.py custom "select(['strategy', 'prestige', 'production'])"

# Custom aggregation
python scripts/analysis/analyze_diagnostics.py custom "group_by('strategy').agg(pl.col('prestige').mean())"
```

## Options

- `--min-turn N` - Only analyze turns >= N (default: 0)
- `--max-turn N` - Only analyze turns <= N (default: all)

## Output

All commands print formatted tables to stdout. Redirect to save:

```bash
# Save summary to file
python scripts/analysis/analyze_diagnostics.py summary > summary.txt

# Save red flags to file
python scripts/analysis/analyze_diagnostics.py red-flags > red_flags.txt
```

## Data Format

Scripts expect CSV files in `balance_results/diagnostics/` with format:
```
game_XXXX.csv
```

Each CSV must have the standard EC4X diagnostics columns (see diagnostic header in any game CSV).

## Creating New Analysis Scripts

To create a new analysis script:

1. Copy `analyze_diagnostics.py` as a template
2. Use Polars DataFrame API for efficient analysis
3. Follow the command pattern for consistency
4. Add your script to this README

### Polars Tips

```python
import polars as pl

# Load data
df = pl.read_csv("balance_results/diagnostics/game_0.csv")

# Filter
df.filter(pl.col("turn") > 10)

# Select columns
df.select(["strategy", "prestige", "treasury"])

# Group and aggregate
df.group_by("strategy").agg(pl.col("prestige").mean())

# Sort
df.sort("prestige", descending=True)

# Join
df1.join(df2, on="house")

# Custom expressions
df.with_columns([
    (pl.col("treasury") / pl.col("production")).alias("treasury_ratio")
])
```

## Performance

Polars is significantly faster than Pandas for large datasets:
- **Loading:** ~10x faster
- **Filtering:** ~5-20x faster
- **Aggregations:** ~10-50x faster
- **Memory:** ~50% less memory usage

For 400 games (4000+ CSV files), expect:
- Load time: <5 seconds
- Analysis time: <1 second per command

## Integration with Claude Code

When analyzing diagnostics with Claude Code:

1. Run analysis script to generate insights
2. Share output with Claude (much smaller than raw CSV)
3. Claude can suggest new analyses or script modifications

**Example workflow:**
```bash
# Generate summary
python scripts/analysis/analyze_diagnostics.py summary > summary.txt

# Share summary.txt with Claude (a few KB vs 5MB of raw CSV)
# Claude suggests: "Let's look at economic efficiency"

# Run suggested analysis
python scripts/analysis/analyze_diagnostics.py economy
```

This is **10-100x more token-efficient** than uploading raw CSV data!
