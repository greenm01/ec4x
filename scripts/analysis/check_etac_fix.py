#!/usr/bin/env python3
"""Quick analysis of ETAC production to verify treadmill fix"""

import polars as pl

# Load the CSV
df = pl.read_csv("balance_results/diagnostics/game_99999.csv")

print("=== ETAC Ship Counts by House and Turn ===")
print("Expected: Cap at 4 ETACs per house (4 map rings)")
print()

# Show ETAC counts per house per turn
etac_by_turn = (
    df.filter(pl.col("turn") <= 10)
    .select(["turn", "house", "etac_ships"])
    .sort(["house", "turn"])
)

# Pivot to show all houses side by side
etac_pivot = etac_by_turn.pivot(
    values="etac_ships",
    index="turn",
    columns="house"
)

print(etac_pivot)
print()

# Calculate total ETACs per house at turn 10
final_counts = (
    df.filter(pl.col("turn") == 9)  # Game ended at turn 9
    .select(["house", "etac_ships"])
    .sort("etac_ships", descending=True)
)

print("=== Final ETAC Counts (Turn 9) ===")
print(final_counts)
print()

# Check for treadmill: Did any house exceed cap?
max_etacs = df.select(pl.col("etac_ships").max()).item()
print(f"Maximum ETACs seen: {max_etacs}")
print(f"Expected cap: 4 (map rings)")

if max_etacs > 6:
    print("⚠️  TREADMILL DETECTED: ETACs exceeded reasonable cap!")
elif max_etacs > 4:
    print("⚠️  Slight overproduction (may be normal due to build timing)")
else:
    print("✅ Cap appears to be working correctly")
print()

# Show growth pattern for one house
print("=== Sample House ETAC Growth (house-atreides) ===")
atreides = (
    df.filter((pl.col("house") == "house-atreides") & (pl.col("turn") <= 10))
    .select(["turn", "etac_ships", "scout_ships", "destroyer_ships"])
)
print(atreides)
