# EC4X Hybrid Storage Strategy: SQLite + Parquet

**Date:** 2025-11-27
**Status:** Proposal
**Context:** Leveraging DoD patterns for optimal storage architecture

---

## Executive Summary

**Recommendation: Hybrid architecture using BOTH SQLite and Parquet**

With the new Data-Oriented Design patterns in place, EC4X can benefit from a **dual-track storage strategy**:

1. **SQLite** for operational workloads (turn resolution, game state)
2. **Parquet** for analytical workloads (balance analysis, AI training, game history)

The DoD patterns make this natural because:
- ✅ Pure calculation functions work with any data source
- ✅ Batch iterators map perfectly to columnar scans
- ✅ Extract → Transform → Apply fits ETL pipelines
- ✅ Data-driven design (action descriptors) serializes efficiently

---

## Current Architecture Analysis

### Strengths of SQLite (Keep for Operations)

**1. ACID Transactions**
```nim
# Turn resolution MUST be atomic
BEGIN TRANSACTION;
  UPDATE houses SET prestige = prestige + 100;
  INSERT INTO combat_results (...);
  UPDATE fleets SET location = 'system-5';
COMMIT;  # All or nothing!
```

**2. Relational Integrity**
```sql
-- Foreign keys prevent orphaned data
FOREIGN KEY (owner_house_id) REFERENCES houses(id) ON DELETE CASCADE
```

**3. Indexed Lookups** (Perfect for our O(1) HashMap patterns!)
```sql
CREATE INDEX idx_fleets_location ON fleets(location_system_id);
-- O(1) lookup: Find all fleets in system-5
SELECT * FROM fleets WHERE location_system_id = 'system-5';
```

**4. Transactional Workload (OLTP)**
- Turn resolution: Read orders → Calculate → Write results
- Player queries: "Show my fleets"
- Intel updates: Incremental changes per turn

**Verdict:** **SQLite is PERFECT for operational game state** ✅

---

### Where SQLite Falls Short (Add Parquet for Analysis)

**1. Analytical Queries Are Slow**

Bad performance with SQLite:
```sql
-- Scan entire table to analyze 10,000 turns of combat data
SELECT AVG(damage_dealt) FROM combat_results
WHERE ship_class = 'Destroyer' AND turn BETWEEN 1 AND 10000;
```

Why slow?
- Row-oriented storage → reads ALL columns even if only need one
- No column-level compression
- Full table scans for aggregations

**2. Historical Analysis**

Current problem:
```sql
-- Want to analyze: "How did Destroyer effectiveness change over 1000 games?"
-- SQLite: Must load 100+ GB of row data into memory
-- Query time: Minutes to hours
```

**3. RBA Balance Analysis**

Your RBA system needs to:
- Analyze 10,000 simulated games
- Extract combat effectiveness metrics
- Train on ship class balance data
- Run statistical analysis

SQLite is not designed for this workload.

**4. No Time-Series Optimization**

EC4X is inherently time-series data:
- Turn 1, Turn 2, Turn 3...
- Combat events over time
- Resource production over time
- Fleet movements over time

SQLite treats this like any other data (no columnar compression, no partition pruning).

---

## Parquet: Perfect for Analysis

### What is Parquet?

Apache Parquet is a **columnar storage format** designed for analytical workloads:

```
SQLite (Row-Oriented):
Row 1: [turn=1, fleet_id=abc, damage=50, system=xyz, ...]
Row 2: [turn=1, fleet_id=def, damage=75, system=xyz, ...]
Row 3: [turn=2, fleet_id=abc, damage=30, system=abc, ...]

Parquet (Column-Oriented):
Column 'turn':      [1, 1, 2, 2, 2, ...]  ← Highly compressible!
Column 'damage':    [50, 75, 30, 45, 60, ...]
Column 'system':    [xyz, xyz, abc, abc, def, ...]
```

### Benefits for EC4X Analysis

**1. Blazing Fast Analytical Queries**

```python
# Query 1 million combat events: "Average Destroyer damage by turn"
import polars as pl

df = pl.scan_parquet("combat_events.parquet")
result = df.filter(pl.col("ship_class") == "Destroyer") \
           .group_by("turn") \
           .agg(pl.col("damage_dealt").mean())
           .collect()
# Time: ~100ms (vs 10+ seconds in SQLite)
```

**Why so fast?**
- Only reads `ship_class`, `turn`, and `damage_dealt` columns (skips others)
- Columnar compression → 10-100x less data to read
- Vectorized operations (SIMD)
- Partition pruning (skip irrelevant data)

**2. Perfect for RBA Balance Analysis**

```python
# Analyze 10,000 simulated games for ship class balance
import polars as pl

# Read only relevant columns (ship_class, damage, turn, game_id)
df = pl.scan_parquet("simulation_results.parquet")
balance_metrics = df.group_by(["ship_class", "game_id"]) \
                    .agg([
                        pl.col("damage_dealt").sum().alias("total_damage"),
                        pl.col("survived").mean().alias("survival_rate"),
                        pl.col("cost").first()
                    ]) \
                    .with_columns([
                        (pl.col("total_damage") / pl.col("cost")).alias("efficiency")
                    ])

# Write results back to Parquet
balance_metrics.collect().write_parquet("balance_analysis.parquet")
```

**3. Time-Series Optimized**

Parquet partitioning:
```
combat_events/
├── turn=1/
│   └── data.parquet  ← Only load this for turn 1 queries
├── turn=2/
│   └── data.parquet
├── turn=3/
│   └── data.parquet
...
```

Query turn 1000-2000 only:
```python
df = pl.scan_parquet("combat_events/turn=*/data.parquet")
     .filter((pl.col("turn") >= 1000) & (pl.col("turn") <= 2000))
# Automatically skips 999 partitions! ⚡
```

**4. Compression**

Real-world example:
```
SQLite: 1 million combat events = 500 MB
Parquet: 1 million combat events = 50 MB (10x compression)

Why? Columnar compression:
- "Destroyer" repeated 100,000 times → dictionary encoded once
- Damage values (similar ranges) → RLE + delta encoding
- Turn numbers (sequential) → delta encoding
```

---

## Hybrid Architecture Design

### Principle: Right Tool for Right Job

**SQLite: Operational (Hot Path)**
- Turn resolution (atomic transactions)
- Player queries ("show my fleets")
- Order submission and validation
- Intel updates (incremental)
- Game state persistence

**Parquet: Analytical (Cold Path)**
- RBA balance simulations (10,000 games)
- Historical analysis ("Destroyer effectiveness over time")
- Game replays (efficient time-series queries)
- Statistical reports
- Machine learning training data

---

### Architecture Diagram

```
┌──────────────────────────────────────────────────────┐
│                  EC4X Game Engine                    │
│                                                      │
│  ┌────────────────┐         ┌──────────────────┐   │
│  │  Turn          │         │   RBA Balance    │   │
│  │  Resolution    │         │   Analysis       │   │
│  │  (Operational) │         │   (Analytical)   │   │
│  └────────────────┘         └──────────────────┘   │
│         │                            │              │
│         ▼                            ▼              │
│  ┌────────────────┐         ┌──────────────────┐   │
│  │    SQLite      │────ETL──▶│    Parquet       │   │
│  │   ec4x.db      │         │  analytics/      │   │
│  │                │         │                  │   │
│  │ - Game state   │         │ - Combat logs    │   │
│  │ - Orders       │         │ - Simulation     │   │
│  │ - Fleets       │         │ - Balance data   │   │
│  │ - Colonies     │         │ - Time series    │   │
│  └────────────────┘         └──────────────────┘   │
│         ▲                            │              │
│         │                            │              │
│    (Operational                 (Analytical         │
│     Queries)                     Queries)           │
└──────────────────────────────────────────────────────┘
```

---

### ETL Pipeline: SQLite → Parquet

**Leverage DoD Patterns for Efficient Export**

With our new DoD architecture, exporting to Parquet is natural:

```nim
## export_to_parquet.nim
## Leverage DoD batch iterators for efficient export

import std/[tables, json]
import ../engine/[gamestate, iterators]  # DoD iterators!
import parquet_nim  # Hypothetical Parquet bindings

proc exportCombatEventsToParquet*(
  state: GameState,
  outputPath: string
) =
  ## Export combat events using DoD batch iteration
  ## Pure data transformation (no mutations)

  var writer = createParquetWriter(outputPath, schema = combatEventSchema)

  # Leverage DoD iterators for efficient batch processing
  for event in state.eachCombatEvent():  # Batch iterator from iterators.nim
    writer.writeRow({
      "turn": event.turn,
      "system_id": event.systemId,
      "attacker_house": event.attackerHouse,
      "defender_house": event.defenderHouse,
      "attacker_ship_class": event.attackerShipClass,
      "defender_ship_class": event.defenderShipClass,
      "damage_dealt": event.damageDealt,
      "ship_destroyed": event.shipDestroyed,
      "round_number": event.roundNumber,
      "phase": event.phase.ord
    })

  writer.close()
  echo "Exported ", writer.rowCount, " combat events to Parquet"
```

**Why This Works Beautifully with DoD:**

1. **Batch Iterators** (`iterators.nim`)
   ```nim
   # Already have batch iterators from Phase 0!
   for colony in state.eachColony():
     # Process colonies in batch

   for fleet in state.eachFleet():
     # Process fleets in batch
   ```
   These map perfectly to Parquet's columnar write patterns.

2. **Pure Calculations** (No Mutations)
   ```nim
   # DoD pattern: Extract → Transform → Write
   let combatMetrics = calculateCombatMetrics(event)  # Pure function
   writer.writeRow(combatMetrics)  # No game state mutation
   ```

3. **Data Descriptors** (Action Descriptors Pattern)
   ```nim
   # Already have action descriptors from espionage refactoring
   # Export these directly to Parquet for analysis
   let descriptor = getActionDescriptor(action)
   writer.writeRow({
     "action": descriptor.action.ord,
     "attacker_prestige": descriptor.attackerSuccessPrestige,
     "target_prestige": descriptor.targetSuccessPrestige,
     "has_effect": descriptor.hasEffect
   })
   ```

---

### When to Export: Post-Turn Resolution

```nim
## resolution/turn_engine.nim

proc resolveTurn*(state: var GameState, ...) =
  ## Standard turn resolution (Phase 0-7 DoD patterns)

  # Phase 1-4: Resolve turn (existing code)
  resolveIncomePhase(state)
  resolveCommandPhase(state)
  resolveConflictPhase(state)
  resolveMaintenancePhase(state)

  # NEW: Export analytics data to Parquet (async)
  if shouldExportAnalytics(state.turn):
    asyncExportToParquet(state)
```

**Export Strategies:**

1. **Real-Time Export** (Every Turn)
   ```nim
   proc resolveTurn*(state: var GameState) =
     # ... resolve turn ...
     exportTurnToParquet(state, "analytics/turn_" & $state.turn & ".parquet")
   ```

   Pros: Always up-to-date
   Cons: Slight performance overhead

2. **Batch Export** (Every N Turns)
   ```nim
   if state.turn mod 10 == 0:
     exportTurnsToParquet(state, turns = (state.turn - 9)..state.turn)
   ```

   Pros: Better performance
   Cons: Analytics lag by up to N turns

3. **On-Demand Export**
   ```bash
   $ ec4x export-analytics game-123 --format=parquet
   ```

   Pros: No impact on turn resolution
   Cons: Manual trigger required

**Recommendation: Hybrid**
- Export critical events (combat, espionage) every turn
- Export bulk data (full state) every 10 turns
- Support on-demand export for deep analysis

---

## Use Cases Enabled

### 1. RBA Balance Analysis (PRIMARY USE CASE)

**Current Problem:**
RBA needs to simulate 10,000 games to analyze ship class balance. With SQLite:
- 10,000 games × 100 turns × 50 combat events = 50 million rows
- SQLite database: 25+ GB
- Query time: Minutes
- Memory usage: High (must load rows into memory)

**With Parquet:**
```python
import polars as pl

# Simulate 10,000 games, export to Parquet
for game_id in range(10000):
    state = simulateGame(rng)
    exportToParquet(state, f"simulations/game_{game_id}.parquet")

# Analyze ALL 10,000 games efficiently
df = pl.scan_parquet("simulations/*.parquet")

# Calculate ship class effectiveness
effectiveness = df.group_by(["ship_class", "tech_level"]) \
                  .agg([
                      pl.col("damage_dealt").sum(),
                      pl.col("survived").mean(),
                      (pl.col("damage_dealt") / pl.col("build_cost")).mean().alias("efficiency")
                  ])

# Result: <1 second query time (vs minutes in SQLite)
```

**RBA Workflow:**
```
1. Run 10,000 simulations → Export to Parquet
2. Analyze balance metrics → Polars DataFrame
3. Identify imbalances → Adjust config
4. Re-simulate → Compare results
5. Iterate until balanced
```

---

### 2. Game Replay System

**Problem:** Players want to watch combat replays

**With Parquet Time-Series:**
```python
# Load combat events for specific system and turn range
import polars as pl

replay_data = pl.scan_parquet("combat_events/turn=*/data.parquet") \
               .filter(
                   (pl.col("turn") >= 50) &
                   (pl.col("turn") <= 55) &
                   (pl.col("system_id") == "system-alpha")
               ) \
               .sort("turn", "round_number", "phase") \
               .collect()

# Generate 3D battle visualization
for event in replay_data.iter_rows(named=True):
    renderCombatFrame(event)
```

Partitioned Parquet enables instant access to specific turn ranges.

---

### 3. Statistical Balance Reports

**Question:** "Is the Battleship too strong compared to Cruisers?"

**Analysis Query:**
```python
import polars as pl

# Compare Battleship vs Cruiser over 1000 games
df = pl.scan_parquet("combat_events/*.parquet")

comparison = df.filter(
    pl.col("ship_class").is_in(["Battleship", "Cruiser"])
).group_by("ship_class").agg([
    pl.col("damage_dealt").mean().alias("avg_damage"),
    pl.col("damage_dealt").std().alias("std_damage"),
    pl.col("survived").mean().alias("survival_rate"),
    pl.col("build_cost").first(),
    (pl.col("damage_dealt") / pl.col("build_cost")).mean().alias("cost_efficiency")
])

print(comparison)
# Output (example):
# ┌─────────────┬─────────────┬─────────────┬─────────────┬──────────────────┐
# │ ship_class  │ avg_damage  │ std_damage  │ survival_rate│ cost_efficiency │
# ├─────────────┼─────────────┼─────────────┼──────────────┼─────────────────┤
# │ Battleship  │ 145.3       │ 35.2        │ 0.78         │ 0.582           │
# │ Cruiser     │ 68.1        │ 22.1        │ 0.62         │ 0.681           │  ← More efficient!
# └─────────────┴─────────────┴─────────────┴──────────────┴─────────────────┘
```

**Insight:** Cruisers are more cost-efficient despite lower raw damage!

---

### 4. Machine Learning Training Data

**Goal:** Train AI to predict combat outcomes

**Parquet as ML Training Data:**
```python
import polars as pl
from sklearn.ensemble import RandomForestClassifier

# Load training data (10,000 games worth)
df = pl.scan_parquet("combat_events/*.parquet").collect()

features = df[["attacker_as", "defender_as", "attacker_cr", "defender_cr", "terrain_type"]]
labels = df["attacker_victory"]

model = RandomForestClassifier()
model.fit(features, labels)

# Model learns: "Attackers win 73% of the time when AS advantage > 20%"
```

Parquet's columnar format is **perfect for ML pipelines** (Pandas/Polars/Arrow integration).

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1)

**1. Add Parquet Export Module**
```nim
# src/engine/analytics/parquet_export.nim

proc exportCombatEventsToParquet*(state: GameState, path: string)
proc exportEspionageEventsToParquet*(state: GameState, path: string)
proc exportEconomyEventsToParquet*(state: GameState, path: string)
```

**2. Leverage Existing DoD Patterns**
- Use batch iterators from `iterators.nim`
- Use pure calculation functions (no mutations)
- Use action descriptors for event data

**3. Export on Turn Resolution**
```nim
proc resolveTurn*(state: var GameState) =
  # ... existing resolution ...

  if state.turn mod 10 == 0:
    exportAnalyticsToParquet(state)
```

---

### Phase 2: RBA Integration (Week 2)

**1. Update RBA to Use Parquet**
```python
# tests/balance/analyze_results.py

import polars as pl

# OLD: Read from SQLite (slow)
# df = pl.read_database("SELECT * FROM combat_results", "ec4x.db")

# NEW: Read from Parquet (fast!)
df = pl.scan_parquet("analytics/combat_events/*.parquet")

# Analysis code unchanged (still uses DataFrames)
```

**2. Simulation Export**
```nim
# tests/balance/run_simulation.nim

proc runSimulation*(config: RBAConfig): SimulationResults =
  for game_id in 0..<config.numGames:
    let state = simulateGame(config, game_id)

    # Export to Parquet for analysis
    exportToParquet(state, f"simulations/game_{game_id}.parquet")

  # Analysis runs on Parquet files
  analyzeResults("simulations/*.parquet")
```

---

### Phase 3: Analytics Dashboard (Week 3-4)

**1. Build Analysis CLI**
```bash
$ ec4x analyze balance --games=simulations/*.parquet
Analyzing 10,000 games (50M combat events)...
Ship Class Balance Report:
  Destroyer:   Efficiency: 0.68  ✓ Balanced
  Cruiser:     Efficiency: 0.71  ✓ Balanced
  Battleship:  Efficiency: 0.58  ⚠ Underperforming

$ ec4x analyze combat-trends --game=game-123.db --turns=1..100
Combat Effectiveness Over Time:
  [ASCII graph showing trends]

$ ec4x analyze espionage-success --format=parquet
Espionage Success Rates:
  Tech Theft:     62% success  ✓
  Assassination:  45% success  ✓
  Sabotage:       78% success  ⚠ Too high
```

**2. Web Dashboard (Optional)**
- Visualize Parquet data with charts
- Interactive balance exploration
- Real-time RBA results

---

## Performance Comparison

### Benchmark: "Analyze 10,000 games for ship class balance"

**SQLite Approach:**
```sql
SELECT ship_class,
       AVG(damage_dealt) as avg_damage,
       AVG(survived) as survival_rate
FROM combat_results
GROUP BY ship_class;
```

- **Data Size:** 25 GB (50M rows)
- **Query Time:** 3-5 minutes
- **Memory:** 8+ GB (must load into memory)

**Parquet Approach:**
```python
df = pl.scan_parquet("simulations/*.parquet")
df.group_by("ship_class").agg([...]).collect()
```

- **Data Size:** 2.5 GB (10x compression)
- **Query Time:** 5-10 seconds (30x faster!)
- **Memory:** <1 GB (columnar streaming)

**Winner:** Parquet by 30-100x for analytical queries 🏆

---

## Costs and Trade-offs

### SQLite-Only (Current)

**Pros:**
- ✅ Simple (one database file)
- ✅ ACID transactions
- ✅ Great for operational queries
- ✅ Already implemented

**Cons:**
- ❌ Slow analytical queries (minutes)
- ❌ Large storage (25+ GB for analysis)
- ❌ High memory usage (full row loading)
- ❌ Poor RBA performance

---

### Hybrid SQLite + Parquet (Proposed)

**Pros:**
- ✅ Best of both worlds
- ✅ Fast operations (SQLite)
- ✅ Fast analytics (Parquet)
- ✅ 10x compression (Parquet)
- ✅ Perfect for RBA simulations
- ✅ Leverages DoD patterns naturally

**Cons:**
- ⚠ ETL complexity (export pipeline)
- ⚠ Storage duplication (if exporting everything)
- ⚠ Learning curve (Parquet tools)

**Mitigations:**
- Export only analytics data (not full game state)
- Use DoD batch iterators (already implemented)
- Document with examples (Python notebooks)

---

## Recommended Tools

### Nim → Parquet Export

**Option 1: Arrow C Data Interface**
```nim
# Use Apache Arrow C API bindings
import arrow_nim

proc exportToParquet*(data: seq[CombatEvent], path: string) =
  var schema = createArrowSchema(...)
  var table = createArrowTable(schema, data)
  writeParquet(table, path)
```

**Option 2: JSON → Parquet (Simpler)**
```nim
# Export to JSON, convert with external tool
proc exportToJSON*(data: seq[CombatEvent], path: string) =
  let json = serializeToJSON(data)
  writeFile(path, json)

# Then: json-to-parquet.py converts to Parquet
```

**Option 3: CSV → Parquet (Simplest)**
```nim
# Export to CSV, convert with Polars
proc exportToCSV*(data: seq[CombatEvent], path: string) =
  # Write CSV

# Python: pl.read_csv("data.csv").write_parquet("data.parquet")
```

**Recommendation:** Start with Option 3 (CSV), migrate to Option 1 later.

---

### Analysis Tools

**Python: Polars** (Recommended)
```python
import polars as pl

# Blazing fast DataFrame library
df = pl.scan_parquet("*.parquet")
result = df.group_by(...).agg(...).collect()
```

Why Polars?
- ✅ 10-100x faster than Pandas
- ✅ Built on Apache Arrow (same as Parquet)
- ✅ Lazy evaluation (query optimization)
- ✅ Rust-based (zero-cost abstractions)

**Python: DuckDB** (Alternative)
```python
import duckdb

# SQL queries directly on Parquet!
result = duckdb.query("""
  SELECT ship_class, AVG(damage_dealt)
  FROM 'simulations/*.parquet'
  GROUP BY ship_class
""").to_df()
```

**Nim: DataFrame Library** (Future)
- Consider building Nim DataFrame library using DoD patterns
- Could integrate with existing iterators.nim

---

## Migration Plan: Gradual Adoption

### Step 1: Keep SQLite (No Breaking Changes)

Current architecture stays as-is:
- SQLite for operational game state ✅
- Turn resolution unchanged ✅
- Player queries unchanged ✅

### Step 2: Add Parquet Export (Opt-In)

```bash
# Enable analytics export in config
[analytics]
enabled = true
export_format = "parquet"
export_interval = 10  # Every 10 turns
```

### Step 3: Migrate RBA to Parquet

```bash
# Run simulations with Parquet export
$ ec4x simulate --games=10000 --export=parquet

# Analyze using Parquet
$ python analyze_balance.py --input=simulations/*.parquet
```

### Step 4: Build Analytics Tools

```bash
# New analytics commands
$ ec4x analyze balance
$ ec4x analyze trends
$ ec4x export-analytics --game=game-123
```

### Step 5: Optimize (Optional)

- Partition Parquet by turn/house/system
- Compress with ZSTD
- Build indexes for common queries

---

## Conclusion: Hybrid is Best

**Don't abandon SQLite!** It's perfect for:
- ✅ Operational workloads (turn resolution)
- ✅ ACID transactions
- ✅ Relational integrity
- ✅ Player queries

**Add Parquet for** what SQLite can't do well:
- ✅ Analytical queries (RBA balance analysis)
- ✅ Time-series data (combat logs over 1000 turns)
- ✅ Machine learning (training data)
- ✅ Statistical reports

**The DoD patterns make this natural:**
- Batch iterators → Columnar writes
- Pure functions → No side effects in ETL
- Data descriptors → Efficient serialization
- Extract → Transform → Apply → Perfect ETL pattern

**Next Steps:**
1. Create `src/engine/analytics/parquet_export.nim`
2. Implement CSV export first (simplest)
3. Integrate with RBA simulations
4. Build analysis CLI
5. Measure and optimize

**Expected Impact:**
- 30-100x faster RBA analysis
- 10x storage savings (compression)
- Enables ML/AI training
- Better balance insights

---

## Related Documents

- [Storage Architecture](./storage.md) - Current SQLite design
- [Data Flow](./dataflow.md) - Turn resolution pipeline
- [DoD Implementation Complete](../dod_implementation_complete.md) - Phase 0-7
- [DoD Phases 8-10 Complete](../dod_phases_8_10_complete.md) - Recent work

---

**Recommendation: Proceed with hybrid SQLite + Parquet architecture** ✅

The DoD refactorings (Phases 0-10) have positioned EC4X perfectly for this dual-track approach. The batch iterators, pure functions, and data-driven design patterns make ETL natural and efficient.
