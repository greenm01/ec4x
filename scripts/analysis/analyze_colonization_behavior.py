#!/usr/bin/env python3.11
"""
Analyze colonization behavior to validate Act-aware scoring
"""

import polars as pl
from pathlib import Path

db_dir = Path("balance_results/diagnostics")
csv_files = sorted(db_dir.glob("game_*.csv"))
if not csv_files:
    print("Error: No CSV files found")
    exit(1)

# Use the most recent game
csv_path = csv_files[-1]
print(f"Analyzing: {csv_path}")
print()

# Load the data
df = pl.read_csv(csv_path)

print("=" * 80)
print("COLONIZATION PERFORMANCE ANALYSIS")
print("=" * 80)
print()

# Colony count over time
print("Colony Count by Turn:")
print("-" * 80)

for turn in range(1, 31):
    turn_data = df.filter(pl.col("turn") == turn)

    if len(turn_data) == 0:
        continue

    # Determine Act
    if turn <= 7:
        act = 1
    elif turn <= 14:
        act = 2
    elif turn <= 21:
        act = 3
    else:
        act = 4

    print(f"Turn {turn:2d} (Act {act}):")

    for row in turn_data.iter_rows(named=True):
        house = row['house']
        colonies = row['total_colonies']
        colonies_gained = row.get('colonies_gained', 0) or 0

        gained_str = f" (+{colonies_gained})" if colonies_gained > 0 else ""
        print(f"  {house:<20s}: {colonies:2d} colonies{gained_str}")
    print()

print()
print("=" * 80)
print("COLONIZATION EVENTS")
print("=" * 80)
print()

# Look for colonization gains (colonies_gained > 0)
colonization_events = df.filter(pl.col("colonies_gained") > 0)

if len(colonization_events) > 0:
    print("Turns with new colonies:")
    print("-" * 80)

    for row in colonization_events.iter_rows(named=True):
        turn = row['turn']
        house = row['house']
        gained = row['colonies_gained']
        total = row['total_colonies']

        # Determine Act
        if turn <= 7:
            act = 1
            act_name = "Land Grab"
        elif turn <= 14:
            act = 2
            act_name = "Consolidation"
        elif turn <= 21:
            act = 3
            act_name = "Dominance"
        else:
            act = 4
            act_name = "End Game"

        print(f"Turn {turn:2d} (Act {act}: {act_name:<15s}) | {house:<20s} | +{gained} colony(ies) → {total} total")
else:
    print("No colonization events found in this game")

print()
print("=" * 80)
print("ACT-BY-ACT SUMMARY")
print("=" * 80)
print()

# Summarize by Act
for act in range(1, 5):
    if act == 1:
        act_name = "Land Grab (Distance Priority)"
        turn_range = (1, 7)
    elif act == 2:
        act_name = "Consolidation (Balanced)"
        turn_range = (8, 14)
    elif act == 3:
        act_name = "Dominance (Quality Priority)"
        turn_range = (15, 21)
    else:
        act_name = "End Game (Quality Priority)"
        turn_range = (22, 30)

    act_data = df.filter(
        (pl.col("turn") >= turn_range[0]) &
        (pl.col("turn") <= turn_range[1])
    )

    if len(act_data) == 0:
        continue

    print(f"Act {act}: {act_name}")
    print("-" * 80)

    # Get colonization events in this Act
    act_colonizations = act_data.filter(pl.col("colonies_gained") > 0)

    total_new_colonies = act_colonizations.select(pl.col("colonies_gained").sum()).item()

    print(f"Total new colonies in Act {act}: {total_new_colonies}")

    if len(act_colonizations) > 0:
        # Show per-house breakdown
        house_summary = act_colonizations.group_by("house").agg([
            pl.col("colonies_gained").sum().alias("total_gained")
        ]).sort("total_gained", descending=True)

        print()
        print("Per-house breakdown:")
        for row in house_summary.iter_rows(named=True):
            print(f"  {row['house']:<20s}: {row['total_gained']} colonies")

    print()

print()
print("=" * 80)
print("FINAL STANDINGS")
print("=" * 80)
print()

# Final turn standings
final_turn = df.filter(pl.col("turn") == 30)

if len(final_turn) > 0:
    standings = final_turn.select([
        "house",
        "total_colonies",
        "prestige"
    ]).sort("prestige", descending=True)

    print(f"{'House':<20s} {'Colonies':<10s} {'Prestige':<10s}")
    print("-" * 80)

    for row in standings.iter_rows(named=True):
        print(f"{row['house']:<20s} {row['total_colonies']:<10d} {row['prestige']:<10d}")
else:
    print("No final turn data available")

print()
