#!/usr/bin/env python3
"""Quick analysis of ETAC production to verify treadmill fix

Usage:
    python3 scripts/analysis/check_etac_fix.py <game_seed>

Example:
    python3 scripts/analysis/check_etac_fix.py 99999
"""

import polars as pl
import sys
from pathlib import Path

def main():
    if len(sys.argv) < 2:
        print("Error: Game seed required", file=sys.stderr)
        print("Usage: python3 scripts/analysis/check_etac_fix.py <game_seed>", file=sys.stderr)
        sys.exit(1)

    game_seed = sys.argv[1]
    csv_path = Path(f"balance_results/diagnostics/game_{game_seed}.csv")

    if not csv_path.exists():
        print(f"Error: {csv_path} not found", file=sys.stderr)
        sys.exit(1)

    # Load the CSV
    df = pl.read_csv(str(csv_path))

    print(f"=== ETAC Ship Counts by House and Turn (Game {game_seed}) ===")
    print("Expected: Cap at 4 ETACs per house (4 map rings)")
    print()

    # Show ETAC counts per house per turn
    max_turn = min(10, df["turn"].max())
    etac_by_turn = (
        df.filter(pl.col("turn") <= max_turn)
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

    # Calculate final ETAC counts
    final_turn = df["turn"].max()
    final_counts = (
        df.filter(pl.col("turn") == final_turn)
        .select(["house", "etac_ships"])
        .sort("etac_ships", descending=True)
    )

    print(f"=== Final ETAC Counts (Turn {final_turn}) ===")
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

    # Show growth pattern for first house
    first_house = df["house"].unique()[0]
    print(f"=== Sample House ETAC Growth ({first_house}) ===")
    sample = (
        df.filter((pl.col("house") == first_house) & (pl.col("turn") <= max_turn))
        .select(["turn", "etac_ships", "scout_ships", "destroyer_ships"])
    )
    print(sample)

if __name__ == "__main__":
    main()
