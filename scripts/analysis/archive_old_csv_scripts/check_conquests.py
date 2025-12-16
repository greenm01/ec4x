#!/usr/bin/env python3
"""Check if conquests are happening in recent test games."""
import polars as pl
import argparse

# Parse command-line arguments
parser = argparse.ArgumentParser(description='Analyze conquest activity in a game')
parser.add_argument('--seed', '-s', type=int, default=77777,
                    help='Game seed to analyze (default: 77777)')
args = parser.parse_args()

# Load test data for specified seed
csv_file = f"balance_results/diagnostics/game_{args.seed}.csv"
df = pl.scan_csv(csv_file)

# Check conquest activity
results = (
    df
    .group_by(["house"])
    .agg([
        pl.col("total_colonies").first().alias("start_colonies"),
        pl.col("total_colonies").last().alias("end_colonies"),
        pl.col("colonies_gained_via_colonization").sum().alias("total_colonized"),
        pl.col("colonies_gained_via_conquest").sum().alias("total_conquered"),
        pl.col("colonies_lost").sum().alias("total_lost"),
        pl.col("turn").max().alias("final_turn")
    ])
    .collect()
)

print(f"Colony Activity Summary (game {args.seed}):")
print(results)

# Check per-turn conquest activity
conquest_timeline = (
    df
    .group_by("turn")
    .agg([
        pl.col("colonies_gained_via_conquest").sum().alias("conquests_this_turn")
    ])
    .filter(pl.col("conquests_this_turn") > 0)
    .collect()
)

print("\n\nTurns with Conquest Activity:")
print(conquest_timeline)
