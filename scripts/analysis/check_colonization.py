#!/usr/bin/env python3
"""
Check colonization progress and Act transitions from simulation CSV
"""

import polars as pl
import sys

# Load the game CSV
df = pl.read_csv("balance_results/diagnostics/game_99999.csv")

# Get turn-by-turn colonization summary
print("=" * 80)
print("COLONIZATION PROGRESS BY TURN")
print("=" * 80)

# Group by turn and summarize
summary = (
    df.group_by("turn")
    .agg([
        pl.col("colonies").sum().alias("total_colonies"),
        pl.col("etacs").sum().alias("total_etacs"),
        pl.col("treasury").sum().alias("total_treasury"),
        pl.col("act").first().alias("act")
    ])
    .sort("turn")
)

for row in summary.iter_rows(named=True):
    turn = row["turn"]
    colonies = row["total_colonies"]
    etacs = row["total_etacs"]
    treasury = row["total_treasury"]
    act = row["act"]

    print(f"Turn {turn:2d}: {colonies:2d}/37 systems colonized | "
          f"{etacs:2d} ETACs active | Treasury: {treasury:6d} PP | Act: {act}")

print()
print("=" * 80)
print("PER-HOUSE COLONIZATION (Final Turn)")
print("=" * 80)

# Get final turn data per house
final_turn = df.filter(pl.col("turn") == 15)
for row in final_turn.iter_rows(named=True):
    house = row["house"]
    colonies = row["colonies"]
    etacs = row["etacs"]
    treasury = row["treasury"]
    print(f"{house:20s}: {colonies} colonies | {etacs} ETACs | {treasury:6d} PP")

print()
print("=" * 80)
print("ETAC PRODUCTION SUMMARY")
print("=" * 80)

# Check ETAC counts by turn
etac_summary = (
    df.group_by("turn")
    .agg([
        pl.col("etacs").sum().alias("total_etacs"),
        pl.col("etacs").max().alias("max_per_house")
    ])
    .sort("turn")
)

print("Turn | Total ETACs | Max per House")
print("-----|-------------|---------------")
for row in etac_summary.iter_rows(named=True):
    print(f" {row['turn']:2d}  |     {row['total_etacs']:2d}      |      {row['max_per_house']:2d}")

print()
