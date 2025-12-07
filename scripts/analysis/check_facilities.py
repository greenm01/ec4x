#!/usr/bin/env python3
"""
Check facility scaling (Shipyards/Spaceports) across Acts.

Expected after Eparch facility fix:
- Act 1: 1-2 Shipyards, 1-2 Spaceports
- Act 2: 2-3 Shipyards, 2-3 Spaceports
- Act 3: 4-5 Shipyards, 3-4 Spaceports
- Act 4: 5-7 Shipyards, 4-5 Spaceports

Before fix: All houses stuck at 1 Shipyard, 1 Spaceport entire game.
"""

import polars as pl
import sys

def main():
    csv_file = "balance_results/diagnostics/game_99999.csv"

    try:
        df = pl.read_csv(csv_file)
    except FileNotFoundError:
        print(f"ERROR: {csv_file} not found!")
        print("Run: ./bin/run_simulation -s 99999 -t 30")
        sys.exit(1)

    # Get facility counts at end of each Act
    result = (
        df.filter(pl.col("turn").is_in([7, 14, 21, 30]))
        .select([
            "turn",
            "act",
            "house",
            "total_shipyards",
            "total_spaceports",
            "total_colonies"
        ])
        .sort(["house", "turn"])
    )

    print("=" * 80)
    print("FACILITY SCALING BY ACT")
    print("=" * 80)
    print(result)
    print()

    # Check if facilities are scaling (any house with >1 facility by Act 4)
    act4_data = df.filter(pl.col("turn") == 30)
    max_shipyards = act4_data.select(pl.col("total_shipyards").max()).item()
    max_spaceports = act4_data.select(pl.col("total_spaceports").max()).item()

    print("=" * 80)
    print("FACILITY FIX STATUS")
    print("=" * 80)

    if max_shipyards == 1 and max_spaceports == 1:
        print("❌ FACILITIES NOT SCALING - All houses stuck at 1/1")
        print("   Eparch facility requirements not being generated/fulfilled")
        print()
        print("   Possible causes:")
        print("   1. Binary not rebuilt after Eparch fix")
        print("   2. Facility requirements being generated but unfulfilled")
        print("   3. Facility requirements being deprioritized in mediation")
    else:
        print(f"✅ FACILITIES SCALING - Max: {max_shipyards} Shipyards, {max_spaceports} Spaceports")
        print("   Eparch facility requirements working!")

    print("=" * 80)

    # Show capital ship progression for context
    print()
    print("=" * 80)
    print("CAPITAL SHIP PROGRESSION (for context)")
    print("=" * 80)

    capitals = (
        df.filter(pl.col("turn") == 30)
        .select([
            "house",
            "cruiser_ships",
            "light_cruiser_ships",
            "battlecruiser_ships",
            "battleship_ships",
            "dreadnought_ships",
            "total_ships"
        ])
    )

    print(capitals)
    print("=" * 80)

if __name__ == "__main__":
    main()
