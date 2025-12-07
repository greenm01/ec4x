#!/usr/bin/env python3
"""
Check facility scaling (Shipyards/Spaceports/Drydocks) across Acts.

Expected after Eparch facility fix:
- Act 1: 1-2 Shipyards, 1-2 Spaceports, 0-1 Drydocks
- Act 2: 2-3 Shipyards, 2-3 Spaceports, 1-2 Drydocks
- Act 3: 4-5 Shipyards, 3-4 Spaceports, 2-3 Drydocks
- Act 4: 5-7 Shipyards, 4-5 Spaceports, 3-4 Drydocks

Before fix: All houses stuck at 1 Shipyard, 1 Spaceport entire game.

Usage:
    python3 scripts/analysis/check_facilities.py <game_seed>

Example:
    python3 scripts/analysis/check_facilities.py 99999
"""

import polars as pl
import sys
from pathlib import Path

def main():
    if len(sys.argv) < 2:
        print("Error: Game seed required", file=sys.stderr)
        print("Usage: python3 scripts/analysis/check_facilities.py <game_seed>", file=sys.stderr)
        sys.exit(1)

    game_seed = sys.argv[1]
    csv_file = Path(f"balance_results/diagnostics/game_{game_seed}.csv")

    if not csv_file.exists():
        print(f"Error: {csv_file} not found", file=sys.stderr)
        print(f"Run: ./bin/run_simulation -s {game_seed} -t 30", file=sys.stderr)
        sys.exit(1)

    try:
        df = pl.read_csv(str(csv_file))
    except Exception as e:
        print(f"Error loading CSV: {e}", file=sys.stderr)
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
            "total_drydocks",
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
    max_drydocks = act4_data.select(pl.col("total_drydocks").max()).item()

    print("=" * 80)
    print("FACILITY FIX STATUS")
    print("=" * 80)

    if max_shipyards == 1 and max_spaceports == 1 and max_drydocks == 0:
        print("❌ FACILITIES NOT SCALING - All houses stuck at 1 SY / 1 SP / 0 DD")
        print("   Eparch facility requirements not being generated/fulfilled")
        print()
        print("   Possible causes:")
        print("   1. Binary not rebuilt after Eparch fix")
        print("   2. Facility requirements being generated but unfulfilled")
        print("   3. Facility requirements being deprioritized in mediation")
    else:
        print(f"✅ FACILITIES SCALING - Max: {max_shipyards} Shipyards, {max_spaceports} Spaceports, {max_drydocks} Drydocks")
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
