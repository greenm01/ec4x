# Rule-Based AI (RBA) Optimization Guide

Practical guide for using diagnostic data to optimize EC4X's rule-based AI system.

## Understanding Your RBA

EC4X uses a personality-driven RBA system located in `src/ai/`:

```
src/ai/
├── rba/
│   ├── intelligence.nim    # Information gathering, scout deployment
│   ├── diplomacy.nim       # Alliance/rivalry decisions
│   ├── tactical.nim        # Combat & invasion tactics
│   ├── strategic.nim       # Long-term planning
│   └── budget.nim          # PP allocation decisions
├── personality.nim         # Trait definitions
└── decisions.nim           # High-level decision framework
```

### Core Personality Traits

Each AI house has these traits (0.0 - 1.0 scale):

- **aggression** - Military focus, attack likelihood
- **expansion** - Colony acquisition drive
- **techPriority** - Research vs expansion balance
- **economy** - Treasury management, infrastructure
- **caution** - Risk aversion, defensive posturing

## Diagnostic Metrics Explained

The diagnostic system outputs 130 columns per turn. Key metrics:

### Fighter/Carrier System (Phase 2b)

```json
"phase2b_fighter_carrier": {
  "capacity_violation_rate": 2.04,    // % turns with orphaned fighters
  "idle_carrier_rate": 0.0,           // % carriers without fighters
  "avg_fighters_per_house": 0.4,      // Mean fighter count
  "avg_carriers_per_house": 0.0       // Mean carrier count
}
```

**What to look for:**
- `capacity_violation_rate > 1%` → Build/disbanding logic broken
- `idle_carrier_rate > 10%` → Assignment logic not working
- `avg_fighters < 5` (by turn 15) → Build thresholds too high
- `avg_carriers == 0` but fighters present → Never building carriers

**Common fixes:**
1. Adjust build thresholds in `ai_controller.nim`
2. Fix capacity tracking in fighter disbanding logic
3. Add carrier build priority when fighters exceed 6

### Scout Operations (Phase 2c)

```json
"phase2c_scouts": {
  "avg_scouts_per_house": 10.8,      // Mean scout count
  "utilization_5plus": 86.6          // % turns with 5+ scouts
}
```

**What to look for:**
- `avg_scouts < 5` → Not building enough for ELI mesh
- `utilization_5plus < 70%` → Inconsistent production
- Scouts high but espionage low → Deployment logic broken

**Common fixes:**
1. Prioritize scouts in early game (turns 1-10)
2. Ensure intelligence.nim uses scouts for recon
3. Check scout survival rate (being destroyed in combat?)

### Espionage (Phase 2g)

```json
"phase2g_espionage": {
  "spy_planet_missions": 4,          // SpyPlanet operations
  "hack_starbase_missions": 0,       // HackStarbase operations
  "total_missions": 4,               // Total espionage
  "usage_rate": 0.0                  // % turns with any espionage
}
```

**What to look for:**
- `total_missions == 0` → Espionage not being triggered
- `usage_rate < 50%` (after turn 10) → Too infrequent
- `spy_planet` high but `hack_starbase == 0` → Missing logic

**Common fixes:**
1. Check intelligence.nim espionage decision tree
2. Verify scout scout_ships count before missions
3. Add aggression/intelligence trait thresholds

### Treasury Management

```json
"anomalies": [{
  "type": "treasury_hoarding",
  "count": 82461,                    // Turns with 10+ zero-spend
  "description": "..."
}]
```

**What to look for:**
- High `treasury` but low unit counts → Budget allocation broken
- `zero_spend_turns > 10` → Not spending available PP
- `production` high but no growth → Income not being used

**Common fixes:**
1. Review budget.nim allocation percentages
2. Check for deadlocks (waiting for prereqs that never trigger)
3. Ensure "urgent needs" override hoarding behavior

## Diagnostic Workflow for RBA Issues

### Step 1: Identify the Problem

Run diagnostics and check summary:

```bash
nimble testBalanceDiagnostics
nimble summarizeDiagnostics
```

Look for `"status": "fail"` or `"status": "critical_fail"` phases.

### Step 2: Drill Down with Custom Analysis

**Example: Fighter production issue**

```python
import polars as pl

df = pl.read_parquet("balance_results/diagnostics_combined.parquet")

# When are fighters being built?
with_fighters = df.filter(pl.col("total_fighters") > 0)

analysis = with_fighters.group_by("turn").agg([
    pl.col("total_fighters").mean().alias("avg_fighters"),
    pl.col("treasury").mean().alias("avg_treasury"),
    pl.col("total_colonies").mean().alias("avg_colonies"),
])

print(analysis.sort("turn"))
```

**Questions to answer:**
- What turn do fighters first appear?
- What conditions exist when they ARE built?
- Are all houses building them or just some?

### Step 3: Locate RBA Code

Based on the issue, identify which module to examine:

| Issue | Module | Function |
|-------|--------|----------|
| Fighter build | `ai_controller.nim` | `decideFighterProduction()` |
| Scout deployment | `intelligence.nim` | `deployScouts()` |
| Espionage missions | `intelligence.nim` | `planEspionage()` |
| Budget allocation | `budget.nim` | `allocateProductionPoints()` |
| Colony expansion | `strategic.nim` | `selectColonizationTarget()` |

### Step 4: Form Hypothesis

Example hypothesis:
> "Fighters aren't being built because the build threshold requires BOTH
> techPriority >= 0.4 AND aggression >= 0.4, which only matches 1/4 of
> personalities. Should use OR instead of AND."

### Step 5: Test Hypothesis

Make the code change:

```nim
# Before (ai_controller.nim:312)
if personality.techPriority >= 0.4 and personality.aggression >= 0.4:
  buildFighters()

# After
if personality.techPriority >= 0.3 or personality.aggression >= 0.5:
  buildFighters()
```

### Step 6: Validate with Diagnostics

```bash
nimble testBalanceDiagnostics
nimble summarizeDiagnostics
```

Check if `avg_fighters_per_house` improved.

### Step 7: Share Results with Claude

```
Me: Made this change to fighter build threshold:
[paste code diff]

Old summary:
[paste old summary.json]

New summary:
[paste new summary.json]

Claude: Great improvement! avg_fighters went from 0.4 → 15.2.
But now I see idle_carrier_rate: 23.4%. Fighters exist but aren't
being loaded onto carriers. Let me check the assignment logic...
```

## Common RBA Patterns & Fixes

### Pattern 1: Threshold Tuning

**Problem:** Feature rarely triggers

**Diagnostic:** Low metric values, high variance

**Fix:** Lower threshold or change logic operator (AND → OR)

```nim
# Too restrictive (requires both)
if trait1 >= 0.5 and trait2 >= 0.5:

# More flexible (requires either)
if trait1 >= 0.4 or trait2 >= 0.6:
```

### Pattern 2: Missing Personality Coverage

**Problem:** Only some houses exhibit behavior

**Diagnostic:** High standard deviation in metrics by house

**Fix:** Add multiple trigger paths for different personalities

```nim
# Before: Only aggressive houses
if personality.aggression >= 0.6:
  buildScouts()

# After: Aggressive OR curious
if personality.aggression >= 0.6 or personality.techPriority >= 0.5:
  buildScouts()
```

### Pattern 3: Phase Transitions

**Problem:** Behavior correct in early game, breaks later

**Diagnostic:** Metrics good at turn 7, bad at turn 15

**Fix:** Add phase-aware logic

```nim
# Before: Static threshold
if colonies < 5:
  prioritizeExpansion()

# After: Phase-aware
let targetColonies = if turn <= 7: 5 elif turn <= 15: 12 else: 20
if colonies < targetColonies:
  prioritizeExpansion()
```

### Pattern 4: Resource Deadlock

**Problem:** High treasury, low activity

**Diagnostic:** `zero_spend_turns > 10`, high avg_treasury

**Fix:** Add "urgent needs override" logic

```nim
# Before: Waits for perfect conditions
if treasury >= 500 and threat == low:
  buildColonyShip()

# After: Urgent override
if treasury >= 500 and (threat == low or treasury >= 1500):
  buildColonyShip()  # Don't hoard indefinitely
```

### Pattern 5: Capacity Management

**Problem:** Units disbanded due to capacity violations

**Diagnostic:** `capacity_violations > 0`, fighters disappear

**Fix:** Build carriers BEFORE fighters hit cap

```nim
# Before: Reactive
if fighters > carrierCapacity:
  buildCarrier()

# After: Proactive
if fighters >= carrierCapacity * 0.8:  # 80% threshold
  buildCarrier()
```

## Interpreting Anomalies

### Treasury Hoarding

```json
"anomalies": [{
  "type": "treasury_hoarding",
  "count": 82461,
  "severity": "warning"
}]
```

**Likely causes:**
1. Budget allocation percentages too conservative
2. Build preconditions never satisfied
3. Missing "emergency spending" logic

**Investigation:**
```python
hoarders = df.filter(
    (pl.col("treasury") > 1000) &
    (pl.col("zero_spend_turns") > 10)
)

print(hoarders.select([
    "turn", "house", "treasury", "production",
    "total_colonies", "total_fighters"
]))
```

Look for patterns: What DIDN'T they build despite having PP?

### Combat Imbalance

```json
"anomalies": [{
  "type": "combat_imbalance",
  "win_rate": 72.3,
  "severity": "warning"
}]
```

**Likely causes:**
1. Some personalities too aggressive (attacking prematurely)
2. Tactical decisions favor attacker or defender
3. Fleet composition imbalanced

**Investigation:**
```python
combat_by_house = df.group_by("house").agg([
    pl.col("space_wins").sum(),
    pl.col("space_losses").sum(),
])

combat_by_house = combat_by_house.with_columns(
    (pl.col("space_wins") /
     (pl.col("space_wins") + pl.col("space_losses")) * 100
    ).alias("win_rate")
)

print(combat_by_house.sort("win_rate"))
```

If one house dominates, check their personality traits vs. tactical.nim decisions.

### CLK Without Raiders

```json
"anomalies": [{
  "type": "clk_no_raiders",
  "count": 156,
  "severity": "error"
}]
```

**Likely cause:** Research completed but build logic missing

**Fix:**
```nim
# Check if this logic exists in ai_controller.nim
if hasResearch(tech_cloak) and raiders < 3:
  buildRaider()
```

### Orbital Failures

```json
"anomalies": [{
  "type": "orbital_failures",
  "failure_rate": 34.2,
  "severity": "warning"
}]
```

**Likely causes:**
1. Underestimating starbase strength in tactical.nim
2. Not bringing enough ground forces
3. Intelligence gathering failed to spot defenses

**Investigation:**
```python
orbital_fails = df.filter(
    (pl.col("orbital_failures") > 0) &
    (pl.col("space_wins") > 0)  # Won space but lost orbital
)

print(orbital_fails.select([
    "turn", "house", "ground_battery_units",
    "army_units", "marine_division_units"
]))
```

## A/B Testing RBA Changes

Compare before/after metrics:

```bash
# Baseline
git checkout main
nimble testBalanceDiagnostics
mv balance_results/summary.json results_baseline.json

# Variant (your change)
git checkout feature/fighter-threshold-fix
nimble testBalanceDiagnostics
mv balance_results/summary.json results_variant.json

# Compare
python3 -c "
import json
b = json.load(open('results_baseline.json'))
v = json.load(open('results_variant.json'))

print('Fighter Production:')
print(f'  Baseline: {b[\"phase2b_fighter_carrier\"][\"avg_fighters_per_house\"]}')
print(f'  Variant:  {v[\"phase2b_fighter_carrier\"][\"avg_fighters_per_house\"]}')
print()
print('Capacity Violations:')
print(f'  Baseline: {b[\"phase2b_fighter_carrier\"][\"capacity_violation_rate\"]}%')
print(f'  Variant:  {v[\"phase2b_fighter_carrier\"][\"capacity_violation_rate\"]}%')
"
```

Share both summaries with Claude for statistical significance analysis.

## Personality-Specific Tuning

Test how changes affect different personality types:

```python
import polars as pl

df = pl.read_parquet("balance_results/diagnostics_combined.parquet")

# Metrics by house (proxy for personality in tests)
by_house = df.group_by("house").agg([
    pl.col("total_fighters").mean().alias("avg_fighters"),
    pl.col("total_colonies").mean().alias("avg_colonies"),
    pl.col("space_wins").sum().alias("total_wins"),
])

print(by_house.sort("avg_fighters"))
```

If House Atreides (balanced) performs well but House Harkonnen (aggressive)
doesn't, the issue is personality-specific logic.

## Validation Checklist

Before committing an RBA change, verify:

- [ ] All 4 phases pass (or improved)
- [ ] No new critical anomalies introduced
- [ ] Avg metrics within target ranges (see BALANCE_TESTING_METHODOLOGY.md)
- [ ] Behavior consistent across turn ranges (7/15/25/30)
- [ ] No regressions in other subsystems
- [ ] At least 50 games tested (100+ for major changes)

## Quick Reference: Key Thresholds

From `BALANCE_TESTING_METHODOLOGY.md`:

| Metric | Turn 7 | Turn 15 | Turn 30 |
|--------|--------|---------|---------|
| Colonies | 5-8 | 10-15 | 20-30 |
| Scouts | 2-4 | 5-7 | 8-12 |
| Fighters | 0-2 | 4-10 | 10-20 |
| Treasury | 200-600 | 500-1500 | 1000-3000 |

Use these as targets when tuning RBA logic.

## Getting Help from Claude

### Good Question Format

```
Me: I'm optimizing [specific RBA subsystem]. Ran 50 diagnostic games.

Issue: [specific metric] is [value] but should be [target]

Current logic (ai_controller.nim:312):
[paste relevant code]

Diagnostic summary:
[paste summary.json]

What's the root cause?
```

### Bad Question Format

```
Me: AI not working. Here's 9 MB of CSV files...
```

**Why bad:** Too vague, wastes tokens, no actionable code reference

## Advanced: Multi-Metric Optimization

When optimizing interconnected systems:

```python
import polars as pl

df = pl.read_parquet("balance_results/diagnostics_combined.parquet")

# Turn 15 snapshot (end of Act 2)
act2 = df.filter(pl.col("turn") == 15)

# Multi-dimensional health check
health = {
    "avg_colonies": act2.select(pl.col("total_colonies").mean()).item(),
    "avg_fighters": act2.select(pl.col("total_fighters").mean()).item(),
    "avg_scouts": act2.select(pl.col("scout_ships").mean()).item(),
    "avg_treasury": act2.select(pl.col("treasury").mean()).item(),
    "espionage_usage": (len(act2.filter(pl.col("total_espionage") > 0)) / len(act2) * 100),
}

import json
print(json.dumps(health, indent=2))
```

Share this multi-metric snapshot when changes affect multiple systems.

## Summary

1. **Use diagnostics to quantify problems** - "Fighters too low" → "0.4 avg, target 5-10"
2. **Form testable hypotheses** - "Threshold too high" not "AI is dumb"
3. **Make surgical changes** - One RBA rule at a time
4. **Validate with 50+ games** - Catch regressions early
5. **Share summaries with Claude** - Get expert feedback in 500 tokens
6. **Iterate rapidly** - 3-5 minute cycles, not hours

This workflow enables systematic RBA optimization with Claude Code's help.
