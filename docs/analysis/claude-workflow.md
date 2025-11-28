# Claude-Optimized Analysis Workflow

**Status:** Implemented (Phase 1-2 Complete)
**Priority:** HIGH - Enables AI-assisted balance tuning

---

## Overview

EC4X's analysis system now provides Claude-optimized data exports that reduce 2-5M token CSV files to <12K tokens while preserving essential information. This enables direct Claude analysis without manual summarization.

### Key Benefits

- **Token Efficiency:** 99.9% reduction (5 MB CSV → 10 KB Markdown)
- **Claude-Native Formats:** Markdown tables, compact JSON, text summaries
- **Selective Filtering:** Export only relevant houses, turns, and metrics
- **Terminal Workflow:** Command-line interface (no dashboards needed)
- **Excel Compatible:** Original CSV workflow unchanged

---

## Quick Start

### Prerequisites

```bash
# Ensure you're in the nix shell
nix develop

# Run balance diagnostics (generates Parquet data)
nimble testBalance
```

### Basic Usage

```bash
# 1. Quick summary (< 1K tokens)
python -m analysis.cli export-for-claude summary.txt --format=summary

# 2. Markdown table for specific turns
python -m analysis.cli export-for-claude combat.md --turns=10,15 --format=markdown

# 3. JSON with statistics and anomalies
python -m analysis.cli export-for-claude analysis.json --format=json
```

---

## Export Formats

### 1. Markdown Tables (Recommended for Claude)

**Best for:** Visual data analysis, turn-by-turn comparison

**Token efficiency:** ~2.5K tokens for 10 turns × 5 metrics

```bash
python -m analysis.cli export-for-claude combat.md \\
    --turns=10,20 \\
    --metrics=total_fighters,total_destroyers,tech_wep \\
    --format=markdown
```

**Output example:**

```markdown
# EC4X Diagnostic Data Export

**Turns:** 10-20
**Houses:** All
**Metrics:** 3

| Turn | House | total_fighters | total_destroyers | tech_wep |
|------|-------|----------------|------------------|----------|
| 10   | Alpha | 12             | 3                | 2        |
| 11   | Alpha | 14             | 4                | 2        |
| 12   | Alpha | 15             | 4                | 3        |
...

*33 rows exported*
```

**Why Claude loves this:**
- Native markdown parsing (better than CSV)
- Visual table structure preserved
- Easy to reference specific cells
- Minimal whitespace = fewer tokens

---

### 2. Compact JSON (Best for Statistics)

**Best for:** Aggregate analysis, anomaly detection

**Token efficiency:** ~1K tokens (aggregated, not raw data)

```bash
python -m analysis.cli export-for-claude stats.json \\
    --format=json \\
    --metrics=total_fighters,total_destroyers
```

**Output example:**

```json
{
  "summary": {
    "turn_range": [1, 30],
    "houses": "all",
    "total_rows": 120,
    "metrics_count": 2
  },
  "metrics": {
    "total_fighters": {
      "mean": 12.5,
      "median": 12.0,
      "min": 5,
      "max": 25,
      "stddev": 3.2
    },
    "total_destroyers": {
      "mean": 4.2,
      "median": 4.0,
      "min": 1,
      "max": 10,
      "stddev": 1.8
    }
  },
  "anomalies": [
    {
      "turn": 15,
      "house": "Alpha",
      "metric": "total_fighters",
      "value": 25,
      "z_score": 3.9
    }
  ]
}
```

**Why this format:**
- Statistical summaries (no raw data repetition)
- Automatic anomaly detection (z-score > 3.0)
- Highly structured for Claude parsing
- Perfect for balance checks

---

### 3. Text Summary (Ultra-Compact)

**Best for:** Quick assessment, high-level overview

**Token efficiency:** ~500 tokens (99.99% reduction!)

```bash
python -m analysis.cli export-for-claude quick.txt --format=summary
```

**Output example:**

```markdown
# EC4X Diagnostic Summary

## Overview
- **Turn Range:** 1-30
- **Houses:** All
- **Total Data Points:** 120

## Key Metrics

- **treasury_balance:** mean=850.0, min=200.0, max=2000.0
- **total_fighters:** mean=12.5, min=5.0, max=25.0
- **tech_wep:** mean=2.3, min=1.0, max=5.0

## Anomalies Detected

- **total_fighters:** 3 outliers detected
- **tech_wep:** 1 outliers detected

*Summary generated from 120 data points*
```

**Why use this:**
- First pass assessment
- Fastest to generate and read
- Identifies key issues immediately
- Use before drilling down

---

## Common Analysis Patterns

### Pattern 1: "What went wrong in Turn X?"

**Goal:** Investigate a specific turn where something unexpected happened

```bash
# Export 5-turn window around the problematic turn
python -m analysis.cli export-for-claude turn15.md \\
    --turns=13,17 \\
    --format=markdown
```

**Claude prompt:**
```
I'm analyzing turn 15 where House Alpha had major combat losses.
The attached markdown shows turns 13-17. What might have caused the drop
in fighters from 14 to 5?
```

**Token cost:** ~500-1K tokens ✅

---

### Pattern 2: "Is House X's strategy working?"

**Goal:** Assess a house's overall performance and identify weaknesses

```bash
# Export JSON statistics for specific house
python -m analysis.cli export-for-claude alpha.json \\
    --houses=alpha \\
    --format=json
```

**Claude prompt:**
```
Attached is aggregate performance data for House Alpha across 30 turns.
Assess their strategy: Are they growing economy fast enough? Is their
military balanced? Any concerning trends?
```

**Token cost:** ~800 tokens ✅

---

### Pattern 3: "Are Destroyers too strong?"

**Goal:** Balance check for a specific ship class

```bash
# Export ship class metrics for all houses
python -m analysis.cli export-for-claude balance_check.md \\
    --metrics=total_fighters,total_destroyers,total_cruisers,space_combat_wins \\
    --format=markdown
```

**Claude prompt:**
```
Attached is ship composition and combat performance data. Analyze the
cost-effectiveness of each ship class. Are Destroyers over-performing?
```

**Token cost:** ~2-3K tokens ✅

---

### Pattern 4: "Did my config change fix the issue?"

**Goal:** Compare before/after metrics for A/B testing

```bash
# Export baseline data (before change)
python -m analysis.cli --parquet=results_baseline.parquet \\
    export-for-claude baseline.md --format=markdown

# Export test data (after change)
python -m analysis.cli --parquet=results_test.parquet \\
    export-for-claude test.md --format=markdown
```

**Claude prompt:**
```
I changed the Destroyer build cost from 40 to 50 PC. Compare the two
attached datasets (baseline vs test) and tell me if this change improved
balance.
```

**Token cost:** ~3-5K tokens (two files) ✅

---

## Filtering Options

### By Houses

```bash
# Single house
--houses=alpha

# Multiple houses
--houses=alpha --houses=beta

# All houses (default)
# (omit --houses flag)
```

### By Turns

```bash
# Specific range
--turns=10,20   # Turns 10 through 20

# All turns (default)
# (omit --turns flag)
```

### By Metrics

```bash
# Specific metrics
--metrics=total_fighters,total_destroyers,tech_wep

# Default important metrics (when omitted):
# - treasury_balance
# - total_fighters, total_destroyers, total_cruisers
# - tech_wep, tech_eli
# - prestige_current
# - space_combat_wins, space_combat_losses
```

---

## Token Optimization Best Practices

### 1. Start Broad, Then Drill Down

```bash
# Step 1: Get high-level summary (< 1K tokens)
python -m analysis.cli export-for-claude summary.txt --format=summary

# Step 2: Claude identifies anomaly in turn 15
# Step 3: Drill down to that specific turn
python -m analysis.cli export-for-claude turn15.md --turns=13,17 --format=markdown
```

**Why:** Minimize total tokens by only fetching detailed data after identifying issues.

---

### 2. Use Markdown for Tables, JSON for Stats

**Markdown:** When you need to see actual data rows
```bash
--format=markdown
```

**JSON:** When you need aggregate statistics
```bash
--format=json
```

---

### 3. Filter Aggressively

```bash
# Bad: Export everything (5M tokens ❌)
python -m analysis.cli export full.csv

# Good: Export focused view (5K tokens ✅)
python -m analysis.cli export-for-claude combat.md \\
    --turns=10,20 --metrics=total_fighters,total_destroyers
```

**Rule of thumb:**
- 10 turns × 5 metrics × 4 houses = ~500-1K tokens ✅
- 30 turns × 80 metrics × 4 houses = ~2-5M tokens ❌

---

### 4. Use Existing Summaries First

```bash
# Already generates 99.9% token reduction!
python tools/ai_tuning/generate_summary.py --format=human
```

**When to use:** Initial assessment before ad-hoc queries.

---

## File Size Reference

| Export Type | Turns | Metrics | Houses | File Size | Tokens | Use Case |
|-------------|-------|---------|--------|-----------|--------|----------|
| Full CSV | 30 | 80 | 4 | 5 MB | 2-5M | Excel deep analysis |
| Markdown (focused) | 10 | 5 | 4 | 10 KB | 2.5K | Claude turn analysis |
| Markdown (broad) | 30 | 10 | 4 | 50 KB | 12K | Claude comprehensive |
| JSON (aggregated) | 30 | 10 | 4 | 5 KB | 1K | Claude balance check |
| Summary | 30 | all | 4 | 2 KB | 500 | Claude quick assess |

**Target for Claude:** 2-50 KB (500-12K tokens) ✅

---

## Example Workflow: Balance Tuning Session

### Scenario: Players report Destroyers feel overpowered

**Step 1: Quick Assessment**
```bash
python -m analysis.cli export-for-claude summary.txt --format=summary
```

**Claude analysis:** "Summary shows high destroyer counts and win rates."

**Step 2: Detailed Balance Check**
```bash
python -m analysis.cli export-for-claude ships.json \\
    --metrics=total_destroyers,total_cruisers,total_battleships,space_combat_wins \\
    --format=json
```

**Claude analysis:** "Destroyers have 0.92 cost efficiency (30% higher than other classes)."

**Step 3: Historical Trend**
```bash
python -m analysis.cli export-for-claude ship_trend.md \\
    --metrics=total_destroyers,total_cruisers \\
    --format=markdown
```

**Claude analysis:** "Destroyer adoption accelerates after turn 10, suggesting early-game advantage."

**Step 4: Make Config Change**
```toml
# ships.toml
[destroyer]
build_cost = 50  # Was 40
```

**Step 5: Re-test and Compare**
```bash
nimble testBalance
python -m analysis.cli export-for-claude test_results.json --format=json
```

**Claude analysis:** "After cost increase, destroyer adoption matches cruisers. Balance improved!"

**Total tokens used:** ~5K tokens across 4 exports ✅

---

## Tips and Tricks

### Tip 1: Color-Coded Token Warnings

The CLI automatically warns if exports are too large:

```bash
✓ Exported to combat.md
File size: 8.5 KB
Estimated tokens: ~2,125 [green]   # < 5K tokens: Perfect! ✅

⚠ File is large for Claude. Consider filtering by turns/houses/metrics.
Estimated tokens: ~15,000 [red]    # > 12K tokens: Too big! ❌
```

### Tip 2: Combine with Excel

```bash
# Export for Excel (full data, manual analysis)
python -m analysis.cli export full.csv --type=raw

# Export for Claude (focused view, AI analysis)
python -m analysis.cli export-for-claude focused.md --turns=10,20 --format=markdown
```

**Best of both worlds:** Manual exploration in Excel, AI insights from Claude.

### Tip 3: Iterative Filtering

```bash
# Start broad
python -m analysis.cli export-for-claude all.md --format=markdown

# Claude: "Anomaly in House Alpha, Turn 15"

# Refine
python -m analysis.cli export-for-claude alpha_t15.md \\
    --houses=alpha --turns=13,17 --format=markdown
```

### Tip 4: Save Exports for Future Reference

```bash
# Create analysis directory
mkdir -p analysis/exports/

# Export with descriptive names
python -m analysis.cli export-for-claude \\
    analysis/exports/$(date +%Y%m%d)_destroyer_balance.json \\
    --format=json
```

---

## Architecture Notes

### Implementation

**Nim Modules (Planned for future use):**
- `src/engine/analytics/smart_export.nim` - DoD-powered selective export
- `src/engine/analytics/claude_formats.nim` - Token-efficient formatting
- `src/engine/analytics/types.nim` - Shared type definitions

**Python Implementation (Current):**
- `analysis/balance_analyzer.py` - Polars-based export engine
- `analysis/cli.py` - Terminal CLI with `export-for-claude` command

**Why Python?** Faster to implement, leverages existing Polars infrastructure, no Nim/Python FFI complexity.

### Data Flow

```
Balance Diagnostics (diagnostics.nim)
    ↓
Combined Parquet File (3-5x compressed)
    ↓
Polars DataFrame (fast loading)
    ↓
Filter (houses, turns, metrics)
    ↓
Export Format (markdown, JSON, summary)
    ↓
Token Estimation (file_size / 4)
    ↓
Claude Analysis! 🚀
```

### Performance

- **Parquet Loading:** ~50ms (vs 2-3s for CSV)
- **Filter + Export:** ~100-500ms (depends on data size)
- **Parallel Processing:** Uses all CPU cores (Ryzen 9 7950X3D)

---

## Troubleshooting

### Issue: "Parquet file not found"

**Solution:**
```bash
# Generate diagnostics first
nimble testBalance

# Default path
python -m analysis.cli export-for-claude output.md
```

### Issue: "File is too large for Claude"

**Solution:**
```bash
# Reduce turn range
--turns=10,15   # Instead of all 30 turns

# Reduce metrics
--metrics=total_fighters,total_destroyers   # Instead of all 80 metrics

# Filter by house
--houses=alpha   # Instead of all houses
```

### Issue: "Invalid turn range format"

**Solution:**
```bash
# Correct format (comma-separated)
--turns=10,20   ✅

# Incorrect formats
--turns=10..20  ❌
--turns="10-20" ❌
```

---

## Future Enhancements

### Planned Features

1. **Automatic Turn Detection:** Find anomalous turns automatically
2. **Comparative Exports:** Built-in A/B testing support
3. **Custom Metric Sets:** Save frequently-used metric combinations
4. **Visualization Hints:** Suggest which format to use for each query

### Integration Ideas

- **CI/CD Pipeline:** Auto-export on every balance test run
- **Git Hooks:** Pre-commit balance validation
- **Web Dashboard:** Optional GUI for non-terminal users

---

## See Also

- [Architecture Overview](/docs/architecture/overview.md)
- [Balance Testing Guide](/docs/testing/balance.md)
- [AI Tuning Tools](/tools/ai_tuning/)
- [Diagnostic Metrics Reference](/tests/balance/diagnostics.nim)

---

**Questions?** Check the implementation in `analysis/` or ask Claude! 🚀
