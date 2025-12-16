#!/usr/bin/env python3
"""Unit Progression Analysis - Track ship builds by dynamic game act.

Analyzes ship construction patterns across the 4 game acts:
- Act 1 (Land Grab): ETACs, scouts, initial colonization
- Act 2 (Rising Tensions): Military buildup, escorts/capitals
- Act 3 (Total War): Combat fleets, invasions
- Act 4 (Endgame): Final push

Uses dynamic act progression from database (respects config changes).
"""

import sqlite3
import sys
from pathlib import Path
from typing import Optional

try:
    import polars as pl
except ImportError:
    print("Error: polars not installed. Run: pip install polars")
    sys.exit(1)


def load_diagnostics(db_path: str) -> pl.DataFrame:
    """Load diagnostics from SQLite database."""
    conn = sqlite3.connect(db_path)
    query = """
        SELECT
            turn, act, house_id, strategy,
            -- Ship totals
            total_ships, ships_gained, ships_lost,
            -- Ship types
            scout_ships, etac_ships, fighter_ships,
            corvette_ships, frigate_ships, destroyer_ships,
            light_cruiser_ships, cruiser_ships, heavy_cruiser_ships,
            battle_cruiser_ships, battleship_ships, dreadnought_ships,
            super_dreadnought_ships, carrier_ships, super_carrier_ships,
            raider_ships, troop_transport_ships
        FROM diagnostics
        ORDER BY turn, house_id
    """
    df = pl.read_database(query, conn)
    conn.close()
    return df


def analyze_by_act(df: pl.DataFrame) -> None:
    """Analyze ship builds by act."""
    print("\n" + "=" * 80)
    print("UNIT PROGRESSION BY ACT (Dynamic Act Tracking)")
    print("=" * 80)

    # Group by act and calculate averages
    act_summary = (
        df.group_by("act")
        .agg([
            pl.col("ships_gained").mean().alias("avg_ships_built"),
            pl.col("ships_lost").mean().alias("avg_ships_lost"),
            pl.col("total_ships").mean().alias("avg_fleet_size"),
            pl.col("etac_ships").mean().alias("avg_etacs"),
            pl.col("scout_ships").mean().alias("avg_scouts"),
            (pl.col("corvette_ships") + pl.col("frigate_ships") +
             pl.col("destroyer_ships")).mean().alias("avg_escorts"),
            (pl.col("light_cruiser_ships") + pl.col("cruiser_ships") +
             pl.col("heavy_cruiser_ships") + pl.col("battle_cruiser_ships")).mean().alias("avg_cruisers"),
            (pl.col("battleship_ships") + pl.col("dreadnought_ships") +
             pl.col("super_dreadnought_ships")).mean().alias("avg_capitals"),
            (pl.col("carrier_ships") + pl.col("super_carrier_ships")).mean().alias("avg_carriers"),
            pl.col("troop_transport_ships").mean().alias("avg_transports"),
        ])
        .sort("act")
    )

    print("\nAverage Per-House Fleet Composition by Act:")
    print(act_summary)

    # Show act transitions
    act_transitions = (
        df.filter(pl.col("act") != pl.col("act").shift(1))
        .select(["turn", "act"])
        .unique()
        .sort("turn")
    )

    print("\n" + "-" * 80)
    print("Act Transitions (Dynamic):")
    print("-" * 80)
    for row in act_transitions.iter_rows(named=True):
        act_name = ["Land Grab", "Rising Tensions", "Total War", "Endgame"][row["act"] - 1]
        print(f"  Act {row['act']} ({act_name}) starts at turn {row['turn']}")


def analyze_by_strategy(df: pl.DataFrame) -> None:
    """Analyze ship builds by strategy across acts."""
    print("\n" + "=" * 80)
    print("STRATEGY COMPARISON BY ACT")
    print("=" * 80)

    strategy_act = (
        df.group_by(["strategy", "act"])
        .agg([
            pl.col("total_ships").mean().alias("avg_fleet"),
            pl.col("ships_gained").sum().alias("total_built"),
            (pl.col("corvette_ships") + pl.col("frigate_ships") +
             pl.col("destroyer_ships")).mean().alias("escorts"),
            (pl.col("battleship_ships") + pl.col("dreadnought_ships") +
             pl.col("super_dreadnought_ships")).mean().alias("capitals"),
        ])
        .sort(["act", "strategy"])
    )

    print("\nFleet Size and Build Rate by Strategy:")
    print(strategy_act)


def analyze_ship_types(df: pl.DataFrame, act: int) -> None:
    """Detailed ship type breakdown for a specific act."""
    act_name = ["Land Grab", "Rising Tensions", "Total War", "Endgame"][act - 1]
    print(f"\n" + "=" * 80)
    print(f"ACT {act} ({act_name.upper()}) - DETAILED SHIP BREAKDOWN")
    print("=" * 80)

    act_df = df.filter(pl.col("act") == act)

    ship_types = {
        "Scout": "scout_ships",
        "ETAC": "etac_ships",
        "Fighter": "fighter_ships",
        "Corvette": "corvette_ships",
        "Frigate": "frigate_ships",
        "Destroyer": "destroyer_ships",
        "Light Cruiser": "light_cruiser_ships",
        "Cruiser": "cruiser_ships",
        "Heavy Cruiser": "heavy_cruiser_ships",
        "Battle Cruiser": "battle_cruiser_ships",
        "Battleship": "battleship_ships",
        "Dreadnought": "dreadnought_ships",
        "Super Dreadnought": "super_dreadnought_ships",
        "Carrier": "carrier_ships",
        "Super Carrier": "super_carrier_ships",
        "Raider": "raider_ships",
        "Transport": "troop_transport_ships",
    }

    for name, col in ship_types.items():
        avg = act_df[col].mean()
        if avg > 0.1:  # Only show ships that are actually built
            print(f"  {name:20s}: {avg:6.2f} average")


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Analyze unit progression by act")
    parser.add_argument("-s", "--seed", type=int, default=99999,
                        help="Game seed to analyze (default: 99999)")
    parser.add_argument("--act", type=int, choices=[1, 2, 3, 4],
                        help="Show detailed breakdown for specific act")
    args = parser.parse_args()

    db_path = f"balance_results/diagnostics/game_{args.seed}.db"
    if not Path(db_path).exists():
        print(f"Error: Database not found: {db_path}")
        print(f"Make sure you've run: ./bin/run_simulation -s {args.seed}")
        sys.exit(1)

    df = load_diagnostics(db_path)

    if df.height == 0:
        print("No diagnostics data found")
        return

    analyze_by_act(df)
    analyze_by_strategy(df)

    if args.act:
        analyze_ship_types(df, args.act)
    else:
        print("\nTip: Use --act N to see detailed ship breakdown for a specific act")


if __name__ == "__main__":
    main()
