# AI Analysis Workflow

Guide for efficiently sharing diagnostic data with Claude Code using minimal tokens.

## Token Efficiency Comparison

| Format | Size | Estimated Tokens | Use Case |
|--------|------|-----------------|----------|
| Raw CSV (121 files) | 9.2 MB | ~5,000,000 | ❌ Never share directly |
| Parquet | 270 KB | ~50,000 | ✅ Share for deep analysis |
| JSON Summary | 1.4 KB | ~500 | ✅ Share for quick checks |

**Token Savings: 99.99%** by using JSON summary instead of raw CSV!

## Workflow

### 1. Run Diagnostics

```bash
# Quick test (50 games, 30 turns)
nimble testBalanceDiagnostics

# Full analysis (200 games, 30 turns)
nimble testUnknownUnknowns

# Custom run
python3 tools/ai_tuning/run_parallel_diagnostics.py <games> <turns> <workers>
```

This generates CSV files in `balance_results/diagnostics/`

### 2. Generate Summary (Automatic)

The `testUnknownUnknowns` task automatically generates the summary. To manually generate:

```bash
# Generate JSON + human-readable output
nimble summarizeDiagnostics

# Or directly
python3 tools/ai_tuning/generate_summary.py --format human
python3 tools/ai_tuning/generate_summary.py --format json --output balance_results/summary.json
```

### 3. Share with Claude Code

**For Routine Checks:**
```bash
cat balance_results/summary.json
```
Paste the JSON output (~500 tokens) into chat.

**For Deep Analysis:**
```bash
# Convert to Parquet first
nimble convertToParquet

# Share the Parquet file (270 KB vs 9.2 MB CSV)
# Upload: balance_results/diagnostics_combined.parquet
```

**For Targeted Questions:**
```python
# Example: "Show me games where fighters > 10"
import polars as pl

df = pl.read_parquet("balance_results/diagnostics_combined.parquet")
filtered = df.filter(pl.col("total_fighters") > 10)

# Share only the filtered subset
print(filtered.to_json())
```

## Analysis Tasks

### Built-in Nimble Tasks

```bash
# Generate AI-friendly summary (JSON + human-readable)
nimble summarizeDiagnostics

# Convert CSVs to Parquet (34x compression)
nimble convertToParquet

# Phase 2 gap analysis (detailed Python report)
nimble analyzeDiagnostics

# 4-act progression analysis
nimble analyzeProgression
```

### Python Scripts (Direct Use)

All scripts support `--help`:

```bash
# Summary generation
python3 tools/ai_tuning/generate_summary.py --help
python3 tools/ai_tuning/generate_summary.py --format human

# Parquet conversion
python3 tools/ai_tuning/convert_to_parquet.py --help

# Legacy analysis (verbose)
python3 tools/ai_tuning/analyze_phase2_gaps.py
python3 tools/ai_tuning/analyze_4act_progression.py
```

## Custom Analysis with Polars

Leverage your **7950X3D** for parallel data processing:

```python
#!/usr/bin/env python3
import polars as pl

# Load Parquet (instant!)
df = pl.read_parquet("balance_results/diagnostics_combined.parquet")

# Example: Fighters by turn
fighters_by_turn = df.groupby("turn").agg([
    pl.col("total_fighters").mean().alias("avg_fighters"),
    pl.col("total_fighters").max().alias("max_fighters")
])
print(fighters_by_turn)

# Example: Find anomalies
anomalies = df.filter(
    (pl.col("total_fighters") > 20) |
    (pl.col("capacity_violations") > 0)
)
print(f"Found {len(anomalies)} anomalous turns")

# Export filtered data
anomalies.write_json("anomalies.json")
```

## Integration with Test Workflow

### Typical Development Cycle

1. **Make AI changes** to `src/ai/`
2. **Run diagnostics**: `nimble testBalanceDiagnostics` (50 games, ~2 minutes)
3. **Check summary**: `nimble summarizeDiagnostics`
4. **Share with Claude**: Paste `summary.json` (~500 tokens)
5. **Get feedback** and iterate

### Deep Validation Cycle

1. **Run full suite**: `nimble testUnknownUnknowns` (200 games, ~10 minutes)
2. **Auto-generates**: CSVs + Summary + Gap Analysis
3. **Share with Claude**: Paste `summary.json` for overview
4. **If issues found**: Share specific filtered data or Parquet file

## Example Claude Code Interaction

**User:**
```
I just ran nimble testUnknownUnknowns. Here's the summary:

[paste summary.json]

What issues do you see?
```

**Claude:**
```
I see one critical issue:

**phase2b_fighter_carrier: FAIL**
- Capacity violation rate: 2.04% (target: 0%)
- Avg fighters: 0.4 (too low)

This suggests:
1. Fighters not being built (only 0.4 avg)
2. When built, capacity logic is broken (2% violations)

Also note the **treasury_hoarding** anomaly:
- 82,461 turns with 10+ consecutive zero-spend

Let me examine the fighter build logic...
```

**Result:** Actionable feedback from **500 tokens** instead of **5 million tokens**!

## Advanced: Parallel Processing

Your **7950X3D** has 16 cores. Maximize throughput:

```bash
# Run diagnostics with all cores
python3 tools/ai_tuning/run_parallel_diagnostics.py 100 30 16

# Process multiple analyses in parallel
python3 tools/ai_tuning/analyze_phase2_gaps.py &
python3 tools/ai_tuning/analyze_4act_progression.py &
python3 tools/ai_tuning/generate_summary.py --format json --output summary.json &
wait

# All complete in ~same time as longest task
```

## File Locations

- **Diagnostics**: `balance_results/diagnostics/game_*.csv`
- **Summary**: `balance_results/summary.json`
- **Parquet**: `balance_results/diagnostics_combined.parquet`
- **Archives**: `~/.ec4x_test_data/` (restic backup)

## Dependencies

```bash
# Install Polars (required)
pip install polars

# Verify
python3 -c "import polars as pl; print(f'Polars {pl.__version__} installed')"
```

## Tips

1. **Always use JSON summary first** - saves 99.99% tokens
2. **Use Parquet for Claude uploads** - 34x smaller than CSV
3. **Filter data before sharing** - only share relevant subsets
4. **Use human format for quick reads**: `nimble summarizeDiagnostics`
5. **Archive old runs**: `run_parallel_diagnostics.py` auto-archives to restic

## Troubleshooting

**"No CSV files found":**
```bash
# Run diagnostics first
nimble testBalanceDiagnostics
```

**"Polars not installed":**
```bash
pip install polars
```

**Summary shows "issues_found":**
- Expected! This means analysis detected problems
- Share summary.json with Claude for investigation
- Exit code 1 is intentional (CI integration)

**Want even smaller summaries:**
```bash
# Filter by specific phases
python3 -c "
import json
summary = json.load(open('balance_results/summary.json'))
print(json.dumps({
    'overall': summary['overall_status'],
    'fighters': summary['phase2b_fighter_carrier'],
    'anomalies': summary['anomalies']
}, indent=2))
"
```

---

**Remember:** The goal is to **crunch data locally** with your powerful CPU, then share **tiny summaries** with Claude for feedback. This workflow saves you money on tokens and gets faster responses!
