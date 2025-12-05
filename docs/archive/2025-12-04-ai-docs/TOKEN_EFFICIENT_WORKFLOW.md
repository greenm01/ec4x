# Token-Efficient RBA Optimization Workflow

**Goal:** Maximize feedback quality while minimizing token usage when working with Claude Code to optimize your Rule-Based AI (RBA).

## Token Economics

| Data Format | Size | Tokens | Use Case |
|-------------|------|--------|----------|
| Raw CSV (121 games) | 9.2 MB | ~5,000,000 | ❌ Never share |
| Full Parquet | 270 KB | ~50,000 | Deep dive only |
| JSON Summary | 1.4 KB | ~500 | ✅ Default |
| Filtered Subset | Varies | ~100-5,000 | ✅ Targeted analysis |

**Key Insight:** 99.99% token reduction using summaries = faster responses + lower costs!

## The Optimal Workflow

### Phase 1: Generate Diagnostic Data

```bash
# Quick iteration (2 minutes on 7950X3D)
nimble testBalanceDiagnostics  # 50 games, 30 turns

# Full validation (10 minutes)
nimble testUnknownUnknowns     # 200 games, 30 turns + auto-analysis
```

**Output:** `balance_results/diagnostics/game_*.csv` (130 columns of data per turn)

### Phase 2: Generate Summary

```bash
# Human-readable terminal output
nimble summarizeDiagnostics

# Or just the JSON file
python3 tools/ai_tuning/generate_summary.py --format json --output balance_results/summary.json
```

**Output:** `balance_results/summary.json` (~500 tokens)

### Phase 3: Share with Claude Code

**Default approach (99% of cases):**
```bash
cat balance_results/summary.json
```
Paste the JSON into chat. Claude analyzes and gives actionable feedback.

**Example interaction:**
```
You: I just ran 50 diagnostic games. Here's the summary:
[paste summary.json]

What RBA issues do you see?

Claude: I see 2 critical issues:

1. **phase2b_fighter_carrier: FAIL**
   - Capacity violations: 2.04% (should be 0%)
   - Avg fighters: 0.4 (way too low)

   Issue: Fighters aren't being built. Check ai_controller.nim:312
   where fighter build logic checks `techPriority >= 0.4`

2. **treasury_hoarding anomaly**
   - 82,461 turns with 10+ consecutive zero-spend

   Issue: Budget system not allocating PP. Check budget.nim
   colonization vs military spending balance.

Want me to investigate the fighter build logic?
```

**Result:** Actionable insights from 500 tokens instead of 5 million!

## Advanced: Targeted Analysis

When Claude identifies an issue, dig deeper with filtered data:

### Example 1: Fighter Production Issue

```python
#!/usr/bin/env python3
import polars as pl

# Load full dataset
df = pl.read_parquet("balance_results/diagnostics_combined.parquet")

# Filter: Games where fighters were built
with_fighters = df.filter(pl.col("total_fighters") > 0)

# Analyze conditions when fighters ARE built successfully
fighter_analysis = with_fighters.group_by("house").agg([
    pl.col("total_fighters").mean().alias("avg_fighters"),
    pl.col("treasury").mean().alias("avg_treasury"),
    pl.col("production").mean().alias("avg_production"),
])

print(fighter_analysis)
```

Share the **filtered output** (~200 tokens) instead of full dataset.

### Example 2: Treasury Hoarding Investigation

```python
import polars as pl

df = pl.read_parquet("balance_results/diagnostics_combined.parquet")

# Find hoarding cases
hoarders = df.filter(
    (pl.col("treasury") > 1000) &
    (pl.col("zero_spend_turns") > 10)
)

# What were they NOT spending on?
hoarding_summary = hoarders.select([
    "turn", "house", "treasury", "production",
    "total_colonies", "total_fighters", "scout_ships"
]).head(20)

# Export for Claude
hoarding_summary.write_json("hoarding_cases.json")
```

Share `hoarding_cases.json` (~1-2 KB) for focused debugging.

### Example 3: Compare Good vs Bad Games

```python
import polars as pl

df = pl.read_parquet("balance_results/diagnostics_combined.parquet")

# Turn 15 snapshot (end of Act 2)
act2_end = df.filter(pl.col("turn") == 15)

# Good games: 10-15 colonies, fighters present
good_games = act2_end.filter(
    (pl.col("total_colonies") >= 10) &
    (pl.col("total_colonies") <= 15) &
    (pl.col("total_fighters") > 0)
)

# Bad games: <10 colonies OR no fighters
bad_games = act2_end.filter(
    (pl.col("total_colonies") < 10) |
    (pl.col("total_fighters") == 0)
)

# Compare metrics
comparison = {
    "good_avg_fighters": good_games.select(pl.col("total_fighters").mean()).item(),
    "bad_avg_fighters": bad_games.select(pl.col("total_fighters").mean()).item(),
    "good_avg_treasury": good_games.select(pl.col("treasury").mean()).item(),
    "bad_avg_treasury": bad_games.select(pl.col("treasury").mean()).item(),
}

import json
print(json.dumps(comparison, indent=2))
```

Share the comparison JSON (~100 tokens) to identify divergence points.

## RBA-Specific Analysis Patterns

### Pattern 1: Threshold Tuning

**Question:** "Should fighter build threshold be 0.4 or 0.3 for techPriority?"

```python
import polars as pl

df = pl.read_parquet("balance_results/diagnostics_combined.parquet")

# Analyze fighter production by turn range
early_game = df.filter(pl.col("turn").is_between(5, 10))
mid_game = df.filter(pl.col("turn").is_between(11, 20))

summary = {
    "early_fighter_rate": (len(early_game.filter(pl.col("total_fighters") > 0)) / len(early_game) * 100),
    "mid_fighter_rate": (len(mid_game.filter(pl.col("total_fighters") > 0)) / len(mid_game) * 100),
    "avg_fighters_when_built": early_game.filter(pl.col("total_fighters") > 0).select(pl.col("total_fighters").mean()).item(),
}

print(summary)
```

Share summary → Claude recommends threshold adjustment.

### Pattern 2: Personality Trait Impact

**Question:** "Does aggression trait affect scout production?"

```python
import polars as pl

df = pl.read_parquet("balance_results/diagnostics_combined.parquet")

# Group by house (proxy for personality in test games)
scout_by_house = df.group_by("house").agg([
    pl.col("scout_ships").mean().alias("avg_scouts"),
    pl.col("space_total").sum().alias("total_battles"),
])

print(scout_by_house.sort("avg_scouts", descending=True))
```

Share sorted results → Claude identifies personality correlations.

### Pattern 3: Budget Allocation Balance

**Question:** "Is military spending crowding out colony expansion?"

```python
import polars as pl

df = pl.read_parquet("balance_results/diagnostics_combined.parquet")

# Calculate growth rates
turn_progression = df.group_by("turn").agg([
    pl.col("total_colonies").mean().alias("avg_colonies"),
    pl.col("total_fighters").mean().alias("avg_fighters"),
    pl.col("scout_ships").mean().alias("avg_scouts"),
    pl.col("treasury").mean().alias("avg_treasury"),
])

# Show turns 5-20 (critical expansion window)
print(turn_progression.filter(pl.col("turn").is_between(5, 20)))
```

Share progression table → Claude spots allocation issues.

## Iteration Loop

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Make RBA Change                                          │
│    (e.g., adjust fighter build threshold in ai_controller) │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Run Diagnostics                                          │
│    nimble testBalanceDiagnostics  # 50 games, 2 minutes    │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Generate Summary                                         │
│    nimble summarizeDiagnostics    # ~500 tokens            │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Share with Claude                                        │
│    cat balance_results/summary.json                         │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Get Feedback                                             │
│    Claude: "Fighter build logic fixed! But now carriers... │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. Targeted Analysis (if needed)                           │
│    python3 custom_query.py > carriers.json                  │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   └──────> Repeat from step 1
```

**Typical cycle time:** 3-5 minutes (2 min diagnostics + 1 min analysis)

## Pre-Built Analysis Scripts

Use these as starting points:

```bash
# Fighter production deep dive
python3 tools/ai_tuning/example_custom_analysis.py fighters

# Treasury/spending patterns
python3 tools/ai_tuning/example_custom_analysis.py treasury

# Combat effectiveness
python3 tools/ai_tuning/example_custom_analysis.py combat

# Interactive exploration
python3 tools/ai_tuning/example_custom_analysis.py custom
```

## Best Practices

### ✅ DO

1. **Always start with summary.json** - 99% of issues visible here
2. **Use filtered subsets** - only share relevant data
3. **Export to JSON** - easy to paste, Claude parses instantly
4. **Iterate quickly** - 50 games is enough to spot trends
5. **Ask specific questions** - "Why aren't fighters being built at turn 10?"

### ❌ DON'T

1. **Never paste raw CSV** - wastes millions of tokens
2. **Don't upload Parquet first** - start with summary
3. **Don't analyze 1-2 games** - variance is too high
4. **Don't share all 130 columns** - filter to relevant metrics
5. **Don't ask vague questions** - "Is the AI good?" → No actionable feedback

## Example Session Transcript

```
You: I'm working on Phase 2b (fighter/carrier system). Ran 50 games.

[paste summary.json showing 2.04% capacity violations, 0.4 avg fighters]

Claude: Two issues:

1. Fighters rarely built (0.4 avg). Check build conditions.
2. When built, 2.04% violate capacity. Grace period not working.

Let me read ai_controller.nim to diagnose...

[Claude reads file]

Found it! Line 312:
  if personality.techPriority >= 0.4 and personality.aggression >= 0.4:

This requires BOTH traits high. Try:
  if personality.techPriority >= 0.3 or personality.aggression >= 0.5:

This allows tech-focused OR aggressive houses to build fighters.

You: Good catch! Made the change. Re-running diagnostics...

[2 minutes later]

You: New results:

[paste updated summary.json showing 15.2 avg fighters, 0.1% violations]

Claude: Excellent! Fighter production fixed. Violations dropped to 0.1%
(within tolerance).

Next issue: "idle_carrier_rate: 23.4%" - carriers exist but not loading
fighters. Want me to check the carrier assignment logic?

You: Yes please.

[Continue iteration...]
```

## Measuring Progress

Track these metrics across iterations:

```bash
# Save each iteration's summary
cp balance_results/summary.json balance_results/iteration_01.json
cp balance_results/summary.json balance_results/iteration_02.json
# ... after each change

# Compare
python3 -c "
import json

i1 = json.load(open('balance_results/iteration_01.json'))
i2 = json.load(open('balance_results/iteration_02.json'))

print('Phase 2b Status:')
print(f'  Before: {i1[\"phase2b_fighter_carrier\"][\"status\"]}')
print(f'  After:  {i2[\"phase2b_fighter_carrier\"][\"status\"]}')

print('\nFighter Count:')
print(f'  Before: {i1[\"phase2b_fighter_carrier\"][\"avg_fighters_per_house\"]}')
print(f'  After:  {i2[\"phase2b_fighter_carrier\"][\"avg_fighters_per_house\"]}')
"
```

## Token Budget Planning

For a typical RBA optimization session:

| Activity | Tokens | Time |
|----------|--------|------|
| Initial summary | 500 | Instant |
| Claude analysis | 0 | 10 sec |
| 3x targeted queries | 1,500 | Instant |
| Discussion (10 exchanges) | 5,000 | 5 min |
| **Total** | **~7,000** | **~5 min** |

**vs. naive approach:**
- Upload raw CSV: 5,000,000 tokens
- Hit context limit, can't continue
- No conversation possible

## Integration with Git

Track improvements in commit messages:

```bash
git commit -m "fix(ai): Lower fighter build threshold to 0.3

Before: 0.4 avg fighters, 2.04% capacity violations
After:  15.2 avg fighters, 0.1% violations

Summary: balance_results/iteration_02.json"
```

This creates a searchable history of optimizations.

## Advanced: A/B Testing

Compare two RBA strategies:

```bash
# Baseline
nimble testBalanceDiagnostics
cp balance_results/summary.json baseline.json

# Make change (e.g., adjust fighter threshold)
# ... edit ai_controller.nim ...

# Test variant
nimble testBalanceDiagnostics
cp balance_results/summary.json variant.json

# Compare
python3 -c "
import json
baseline = json.load(open('baseline.json'))
variant = json.load(open('variant.json'))

print('Fighter Production:')
print(f'  Baseline: {baseline[\"phase2b_fighter_carrier\"][\"avg_fighters_per_house\"]}')
print(f'  Variant:  {variant[\"phase2b_fighter_carrier\"][\"avg_fighters_per_house\"]}')

# Share both summaries with Claude for analysis
"
```

## When to Use Full Parquet

Only use the full Parquet file when:

1. **Claude asks for it** - "Can I see the raw turn-by-turn progression?"
2. **Multiple interconnected issues** - Need to cross-reference many columns
3. **Pattern discovery** - Looking for unknown-unknowns
4. **Final validation** - Confirming fix across all edge cases

Otherwise, stick with summaries and filtered subsets.

## Automation

Create a quick feedback script:

```bash
#!/bin/bash
# feedback.sh - One-command RBA optimization cycle

nimble testBalanceDiagnostics
nimble summarizeDiagnostics
cat balance_results/summary.json | xclip -selection clipboard
echo "Summary copied to clipboard. Paste into Claude Code."
```

Usage:
```bash
# After making RBA change
./feedback.sh
# → Paste into Claude
# → Get feedback
# → Repeat
```

## Summary

**The Golden Rule:** Crunch data locally (7950X3D), share tiny summaries with Claude.

- **Default:** summary.json (~500 tokens)
- **Targeted:** Filtered JSON (~100-2000 tokens)
- **Deep dive:** Parquet file (~50,000 tokens)
- **Never:** Raw CSV (~5,000,000 tokens)

This workflow gives you fast, actionable feedback while staying well within token budgets.
