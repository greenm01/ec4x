# EC4X Analysis Scripts

Python scripts for analyzing game diagnostics from SQLite databases using Polars.

## Setup

```bash
# Install dependencies
pip install polars

# Or use requirements.txt
pip install -r scripts/analysis/requirements.txt
```

## Core Analysis Scripts

### `unit_progression.py`

Track ship construction patterns across the 4 dynamic game acts.

**Usage:**
```bash
# Analyze default game (seed 99999)
python3 scripts/analysis/unit_progression.py

# Analyze specific game
python3 scripts/analysis/unit_progression.py -s 12345

# Show detailed breakdown for Act 2
python3 scripts/analysis/unit_progression.py -s 12345 --act 2
```

**Output:**
- Average fleet composition by act (ETACs, scouts, escorts, capitals, carriers)
- Act transition timing (dynamic, based on colonization %)
- Strategy comparison across acts
- Detailed ship-type breakdown per act

**Example:**
```
ACT 1 (LAND GRAB) - DETAILED SHIP BREAKDOWN
================================================================================
  Scout               :   2.50 average
  ETAC                :   3.20 average
  Corvette            :   1.80 average
  ...
```

---

### `colonization_metrics.py`

Analyze expansion patterns, ETAC efficiency, and map control progression.

**Usage:**
```bash
# Analyze colonization for game 99999
python3 scripts/analysis/colonization_metrics.py

# Analyze specific game
python3 scripts/analysis/colonization_metrics.py -s 12345
```

**Output:**
- Colonization rate by act
- Map control percentage over time
- ETAC fleet lifecycle (active in Act 1, salvaged in Act 2)
- ETAC efficiency (colonies per ETAC fleet)
- Strategy comparison (final colonization and prestige)

**Example:**
```
ETAC FLEET ANALYSIS
================================================================================
ETAC Efficiency by Act:
  Act 1: 3.2 ETAC fleets → 8.5 colonies gained (2.7 colonies/fleet)
  Act 2: 0.1 ETAC fleets (salvaged)
```

---

### `military_metrics.py`

Track combat activity, invasions, conquests, and military strength.

**Usage:**
```bash
# Analyze military metrics for game 99999
python3 scripts/analysis/military_metrics.py

# Analyze specific game
python3 scripts/analysis/military_metrics.py -s 12345
```

**Output:**
- Combat statistics by act (battles, win rates)
- Combat intensity timeline (major engagements)
- Invasion success rates
- Territory conquest patterns (gained/lost/net)
- Military strength progression (fleets, marines, armies)
- Strategy conquest performance

**Example:**
```
COMBAT ACTIVITY BY ACT
================================================================================
Act 3 (Total War):    12.5 space battles/turn, 68% win rate
Act 4 (Endgame):      8.3 space battles/turn, 72% win rate
```

---

## Diagnostic Scripts (Legacy)

These scripts are for specific debugging tasks:

- `analyze_single_game.py` - Deep dive into single game
- `check_colonization.py` - Colonization bug diagnosis
- `check_etac_fleet_orders.py` - ETAC order validation
- `check_etac_losses.py` - ETAC combat losses
- `check_fleet_lifecycle.py` - Fleet creation/destruction tracking
- `check_order_events.py` - Order processing validation
- `diagnose_colonization_bug.py` - Colonization stall diagnosis
- `find_uncolonized_systems.py` - Identify unreachable systems
- `investigate_colonization_stall.py` - Colony rate analysis
- `verify_etac_salvage.py` - ETAC salvage verification
- `verify_etac_salvage_simple.py` - Simple ETAC salvage check

---

## Data Format

Scripts read from SQLite databases in `balance_results/diagnostics/`:

```
balance_results/diagnostics/
├── game_99999.db   # Default test game
├── game_12345.db   # Custom seed game
└── game_*.db       # Pattern for batch runs
```

Database contains:
- **diagnostics** table: Per-turn metrics (200+ columns)
- **fleet_tracking** table: Per-turn fleet snapshots
- **games** table: Game metadata

---

## Dynamic Act Progression

All scripts use **dynamic act progression** from the database:
- Act transitions are **game-state driven**, not turn-based
- Act 1 → Act 2: Triggered by colonization threshold (default 90%)
- Act 2 → Act 3: Major power eliminated
- Act 3 → Act 4: One house dominates prestige (50%+)

**Changing thresholds in `config/rba.toml` works automatically:**
```toml
[act_progression]
colonization_threshold = 0.80  # Act 2 starts earlier
```

Scripts read the `act` column directly, so no hardcoded turn ranges!

---

## Running Simulations

Before analysis, run a simulation to generate the database:

```bash
# Build simulation binary
nimble buildSimulation

# Run single game (seed 99999, 35 turns, 4 players)
./bin/run_simulation -s 99999 -t 35 -p 4

# Run with custom parameters
./bin/run_simulation -s 12345 -t 100 -p 6

# Batch run (parallel Python script)
python3 scripts/run_balance_test_parallel.py --workers 8 --games 20 --turns 35
```

Output: `balance_results/diagnostics/game_{seed}.db`

---

## Workflow Example

```bash
# 1. Run simulation
./bin/run_simulation -s 42 -t 35

# 2. Analyze unit progression
python3 scripts/analysis/unit_progression.py -s 42

# 3. Check colonization patterns
python3 scripts/analysis/colonization_metrics.py -s 42

# 4. Review military activity
python3 scripts/analysis/military_metrics.py -s 42

# 5. Deep dive on Act 2 ship builds
python3 scripts/analysis/unit_progression.py -s 42 --act 2
```

---

## Creating Custom Scripts

Template for new analysis scripts:

```python
#!/usr/bin/env python3
import sqlite3
import polars as pl
from pathlib import Path

def load_diagnostics(db_path: str) -> pl.DataFrame:
    conn = sqlite3.connect(db_path)
    query = "SELECT turn, act, house_id, strategy, <columns> FROM diagnostics"
    df = pl.read_database(query, conn)
    conn.close()
    return df

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Your analysis")
    parser.add_argument("-s", "--seed", type=int, default=99999)
    args = parser.parse_args()

    db_path = f"balance_results/diagnostics/game_{args.seed}.db"
    df = load_diagnostics(db_path)

    # Your analysis here
    print(df.group_by("act").agg(pl.col("prestige").mean()))

if __name__ == "__main__":
    main()
```

---

## Performance

Polars + SQLite is highly efficient:
- **Load time:** <100ms for single game database
- **Query time:** <50ms for typical aggregations
- **Memory:** Minimal (lazy evaluation)

For 100-game batch analysis, expect <5 seconds total.

---

## Token-Efficient Development with Claude

**Workflow:**
1. Run simulation → generates SQLite database
2. Run analysis script → generates small text output (1-5KB)
3. Share output with Claude (not raw database!)
4. Claude suggests next analysis or fixes
5. Iterate quickly without recompiling

**Why this saves tokens:**
- Raw database: 5-50MB (unusable)
- Script output: 1-5KB (perfect for Claude context)
- 1000x more efficient!

**Example:**
```bash
# Generate summary (1KB output)
python3 scripts/analysis/colonization_metrics.py -s 99999 > summary.txt

# Share summary.txt with Claude (not the database!)
```

---

## Diagnostic Columns Reference

See `diagnostic_columns.json` for complete list of 200+ columns.

**Common columns:**
- **Economy:** treasury, production, maintenance_cost, gco
- **Military:** total_ships, ships_gained, ships_lost, space_wins, space_losses
- **Colonies:** total_colonies, colonies_gained, colonies_lost
- **Tech:** tech_cst, tech_wep, tech_el, tech_sl
- **Prestige:** prestige, prestige_change, prestige_victory_progress

---

**Last Updated:** 2025-12-15
