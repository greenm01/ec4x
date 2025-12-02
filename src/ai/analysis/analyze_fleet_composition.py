#!/usr/bin/env python3
"""Analyze fleet composition by house personality"""
import polars as pl
import sys

if len(sys.argv) < 2:
    print("Usage: analyze_fleet_composition.py <game_number>")
    sys.exit(1)

game = sys.argv[1]
csv_path = f"balance_results/diagnostics/game_{game}.csv"

# Load diagnostic data
df = pl.read_csv(csv_path)

# Get turn 30 data only
turn30 = df.filter(pl.col("turn") == 30)

# Ship class columns (combat ships only)
ship_cols = [
    "frigate_ships", "destroyer_ships", "cruiser_ships",
    "heavy_cruiser_ships", "battlecruiser_ships",
    "battleship_ships", "dreadnought_ships", "super_dreadnought_ships"
]

print("=" * 70)
print("Fleet Composition Analysis - Turn 30")
print("=" * 70)

for row in turn30.iter_rows(named=True):
    house = row["house"]

    # Count escorts vs capitals
    escorts = row["frigate_ships"] + row["destroyer_ships"] + row["cruiser_ships"]
    capitals = (row["heavy_cruiser_ships"] + row["battlecruiser_ships"] +
                row["battleship_ships"] + row["dreadnought_ships"] +
                row["super_dreadnought_ships"])
    total = escorts + capitals

    print(f"\n{house} (Total: {total} combat ships)")
    print(f"  Escorts  ({100*escorts/total if total > 0 else 0:.0f}%): " +
          f"Frigates={row['frigate_ships']}, Destroyers={row['destroyer_ships']}, Cruisers={row['cruiser_ships']}")
    print(f"  Capitals ({100*capitals/total if total > 0 else 0:.0f}%): " +
          f"H.Cruisers={row['heavy_cruiser_ships']}, B.Cruisers={row['battlecruiser_ships']}, " +
          f"Battleships={row['battleship_ships']}, Dreadnoughts={row['dreadnought_ships']}")

    # Economy stats
    print(f"  Economy: Treasury={row['treasury']} PP, Production={row['production']} PP/turn, Colonies={row['total_colonies']}")

print("\n" + "=" * 70)
