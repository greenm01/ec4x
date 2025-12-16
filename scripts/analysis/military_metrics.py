#!/usr/bin/env python3
"""Military Metrics Analysis - Track combat, invasions, and conquests.

Analyzes:
- Combat activity and win rates by act
- Invasion success rates
- Territory conquest patterns
- Military strength progression

Uses dynamic act progression from database.
"""

import sqlite3
import sys
from pathlib import Path

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
            -- Combat
            space_wins, space_losses, ground_wins, ground_losses,
            -- Ships
            total_ships, ships_gained, ships_lost,
            -- Military strength
            total_marines, total_armies,
            troop_transport_ships,
            -- Conquest
            total_colonies, colonies_gained, colonies_lost,
            invasions_launched, invasions_won,
            -- Economic
            prestige
        FROM diagnostics
        ORDER BY turn, house_id
    """
    df = pl.read_database(query, conn)
    conn.close()
    return df


def analyze_combat_activity(df: pl.DataFrame) -> None:
    """Analyze combat frequency and outcomes by act."""
    print("\n" + "=" * 80)
    print("COMBAT ACTIVITY BY ACT")
    print("=" * 80)

    combat_stats = (
        df.group_by("act")
        .agg([
            (pl.col("space_wins") + pl.col("space_losses")).mean().alias("avg_space_battles"),
            (pl.col("ground_wins") + pl.col("ground_losses")).mean().alias("avg_ground_battles"),
            pl.col("space_wins").mean().alias("avg_space_wins"),
            pl.col("space_losses").mean().alias("avg_space_losses"),
            pl.col("ground_wins").mean().alias("avg_ground_wins"),
            pl.col("ground_losses").mean().alias("avg_ground_losses"),
        ])
        .with_columns([
            (pl.col("avg_space_wins") / (pl.col("avg_space_wins") + pl.col("avg_space_losses") + 0.001) * 100)
            .alias("space_win_rate_pct"),
            (pl.col("avg_ground_wins") / (pl.col("avg_ground_wins") + pl.col("avg_ground_losses") + 0.001) * 100)
            .alias("ground_win_rate_pct"),
        ])
        .sort("act")
    )

    print("\nCombat Statistics by Act:")
    print(combat_stats)

    # Show combat intensity over time
    combat_timeline = (
        df.group_by("turn")
        .agg([
            pl.col("space_wins").sum().alias("total_space_wins"),
            pl.col("space_losses").sum().alias("total_space_losses"),
            pl.col("act").first().alias("act"),
        ])
        .with_columns([
            (pl.col("total_space_wins") + pl.col("total_space_losses")).alias("total_battles")
        ])
        .sort("turn")
    )

    print("\n" + "-" * 80)
    print("Combat Intensity Timeline:")
    print("-" * 80)

    # Show turns with significant combat (5+ battles)
    major_combat = combat_timeline.filter(pl.col("total_battles") >= 5)
    if major_combat.height > 0:
        for row in major_combat.iter_rows(named=True):
            act_name = ["Land Grab", "Rising Tensions", "Total War", "Endgame"][row["act"] - 1]
            print(f"  Turn {row['turn']:2d} (Act {row['act']} - {act_name:15s}): "
                  f"{row['total_battles']:2d} battles "
                  f"(W: {row['total_space_wins']:2d}, L: {row['total_space_losses']:2d})")
    else:
        print("  No major combat engagements (5+ battles per turn)")


def analyze_invasion_success(df: pl.DataFrame) -> None:
    """Analyze invasion attempts and success rates."""
    print("\n" + "=" * 80)
    print("INVASION ANALYSIS")
    print("=" * 80)

    invasion_stats = (
        df.filter((pl.col("invasions_launched") > 0) | (pl.col("invasions_won") > 0))
        .group_by("act")
        .agg([
            pl.col("invasions_launched").sum().alias("total_invasions"),
            pl.col("invasions_won").sum().alias("total_won"),
            pl.col("total_marines").mean().alias("avg_marines"),
            pl.col("total_armies").mean().alias("avg_armies"),
            pl.col("troop_transport_ships").mean().alias("avg_transports"),
        ])
        .with_columns([
            (pl.col("total_won") / (pl.col("total_invasions") + 0.001) * 100)
            .alias("invasion_success_rate_pct")
        ])
        .sort("act")
    )

    print("\nInvasion Statistics by Act:")
    print(invasion_stats)

    if invasion_stats.height == 0:
        print("\n  ℹ️  No invasions recorded in this game")


def analyze_conquest_patterns(df: pl.DataFrame) -> None:
    """Analyze territory conquest and losses."""
    print("\n" + "=" * 80)
    print("CONQUEST PATTERNS")
    print("=" * 80)

    conquest_stats = (
        df.group_by("act")
        .agg([
            pl.col("colonies_gained").sum().alias("total_gained"),
            pl.col("colonies_lost").sum().alias("total_lost"),
            (pl.col("colonies_gained") - pl.col("colonies_lost")).sum().alias("net_gain"),
        ])
        .sort("act")
    )

    print("\nTerritory Changes by Act:")
    print(conquest_stats)

    # Identify aggressive vs defensive strategies
    strategy_conquest = (
        df.group_by("strategy")
        .agg([
            pl.col("colonies_gained").sum().alias("total_gained"),
            pl.col("colonies_lost").sum().alias("total_lost"),
            pl.col("space_wins").sum().alias("space_wins"),
            pl.col("invasions_won").sum().alias("invasions_won"),
        ])
        .with_columns([
            (pl.col("total_gained") - pl.col("total_lost")).alias("net_conquest")
        ])
        .sort("net_conquest", descending=True)
    )

    print("\n" + "-" * 80)
    print("Strategy Conquest Performance:")
    print("-" * 80)
    print(strategy_conquest)


def analyze_military_strength(df: pl.DataFrame) -> None:
    """Analyze military strength progression."""
    print("\n" + "=" * 80)
    print("MILITARY STRENGTH PROGRESSION")
    print("=" * 80)

    strength_by_act = (
        df.group_by("act")
        .agg([
            pl.col("total_ships").mean().alias("avg_fleet_size"),
            pl.col("ships_lost").sum().alias("total_losses"),
            pl.col("total_marines").mean().alias("avg_marines"),
            pl.col("total_armies").mean().alias("avg_armies"),
        ])
        .sort("act")
    )

    print("\nMilitary Strength by Act:")
    print(strength_by_act)

    # Final military comparison by strategy
    final_turn = df["turn"].max()
    final_military = (
        df.filter(pl.col("turn") == final_turn)
        .group_by("strategy")
        .agg([
            pl.col("total_ships").mean().alias("avg_fleet"),
            pl.col("total_marines").mean().alias("avg_marines"),
            pl.col("total_armies").mean().alias("avg_armies"),
            pl.col("prestige").mean().alias("prestige"),
        ])
        .sort("prestige", descending=True)
    )

    print("\n" + "-" * 80)
    print("Final Military Strength by Strategy:")
    print("-" * 80)
    print(final_military)


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Analyze military metrics")
    parser.add_argument("-s", "--seed", type=int, default=99999,
                        help="Game seed to analyze (default: 99999)")
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

    analyze_combat_activity(df)
    analyze_invasion_success(df)
    analyze_conquest_patterns(df)
    analyze_military_strength(df)


if __name__ == "__main__":
    main()
