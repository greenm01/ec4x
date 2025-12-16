#!/usr/bin/env python3
"""Colonization Metrics Analysis - Track expansion and ETAC behavior.

Analyzes:
- Colonization rate by act
- ETAC fleet usage and efficiency
- Map control progression
- Expansion patterns by strategy

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
            total_systems_on_map,
            total_colonies, colonies_gained, colonies_lost,
            etac_ships,
            prestige
        FROM diagnostics
        ORDER BY turn, house_id
    """
    df = pl.read_database(query, conn)
    conn.close()
    return df


def analyze_colonization_rate(df: pl.DataFrame) -> None:
    """Analyze colonization rate across acts."""
    print("\n" + "=" * 80)
    print("COLONIZATION PROGRESSION BY ACT")
    print("=" * 80)

    # Calculate map control percentage
    df = df.with_columns([
        (pl.col("total_colonies") / pl.col("total_systems_on_map") * 100)
        .alias("map_control_pct")
    ])

    act_colonization = (
        df.group_by("act")
        .agg([
            pl.col("colonies_gained").mean().alias("avg_gained_per_turn"),
            pl.col("colonies_lost").mean().alias("avg_lost_per_turn"),
            pl.col("total_colonies").mean().alias("avg_colonies"),
            pl.col("map_control_pct").mean().alias("avg_map_control_pct"),
        ])
        .sort("act")
    )

    print("\nColonization Activity by Act:")
    print(act_colonization)

    # Show total map colonization over time
    total_colonization = (
        df.group_by("turn")
        .agg([
            pl.col("total_colonies").sum().alias("total_colonized"),
            pl.col("total_systems_on_map").first().alias("total_systems"),
            pl.col("act").first().alias("act"),
        ])
        .with_columns([
            (pl.col("total_colonized") / pl.col("total_systems") * 100)
            .alias("map_colonized_pct")
        ])
        .sort("turn")
    )

    print("\n" + "-" * 80)
    print("Map Colonization Progress:")
    print("-" * 80)

    # Show every 5 turns for brevity
    for row in total_colonization.filter(pl.col("turn") % 5 == 0).iter_rows(named=True):
        act_name = ["Land Grab", "Rising Tensions", "Total War", "Endgame"][row["act"] - 1]
        print(f"  Turn {row['turn']:2d} (Act {row['act']} - {act_name:15s}): "
              f"{row['total_colonized']:2d}/{row['total_systems']:2d} systems "
              f"({row['map_colonized_pct']:5.1f}%)")


def analyze_etac_efficiency(df: pl.DataFrame) -> None:
    """Analyze ETAC fleet usage and efficiency."""
    print("\n" + "=" * 80)
    print("ETAC FLEET ANALYSIS")
    print("=" * 80)

    etac_stats = (
        df.filter(pl.col("etac_ships") > 0)
        .group_by("act")
        .agg([
            pl.col("etac_ships").mean().alias("avg_etac_ships"),
            pl.col("colonies_gained").mean().alias("avg_colonies_gained"),
        ])
        .with_columns([
            (pl.col("avg_colonies_gained") / pl.col("avg_etac_ships"))
            .alias("colonies_per_etac")
        ])
        .sort("act")
    )

    print("\nETAC Efficiency by Act:")
    print(etac_stats)

    # ETAC lifecycle
    print("\n" + "-" * 80)
    print("ETAC Fleet Lifecycle:")
    print("-" * 80)

    etac_lifecycle = (
        df.group_by("turn")
        .agg([
            pl.col("etac_ships").mean().alias("avg_etac_ships"),
            pl.col("act").first().alias("act"),
        ])
        .sort("turn")
    )

    # Show when ETACs are active/salvaged
    act1_etacs = etac_lifecycle.filter(pl.col("act") == 1)["avg_etac_ships"].mean()
    act2_etacs = etac_lifecycle.filter(pl.col("act") == 2)["avg_etac_ships"].mean()

    print(f"  Act 1 (Land Grab):       {act1_etacs:.2f} ETAC ships (active colonization)")
    print(f"  Act 2 (Rising Tensions): {act2_etacs:.2f} ETAC ships (should be salvaged)")

    if act2_etacs > 0.5:
        print("\n  ⚠️  WARNING: ETACs not being salvaged properly in Act 2!")


def analyze_by_strategy(df: pl.DataFrame) -> None:
    """Compare colonization patterns by strategy."""
    print("\n" + "=" * 80)
    print("STRATEGY COLONIZATION COMPARISON")
    print("=" * 80)

    strategy_colonization = (
        df.group_by(["strategy", "act"])
        .agg([
            pl.col("total_colonies").mean().alias("avg_colonies"),
            pl.col("colonies_gained").sum().alias("total_gained"),
            pl.col("etac_ships").mean().alias("avg_etacs"),
        ])
        .sort(["act", "strategy"])
    )

    print("\nColonization by Strategy and Act:")
    print(strategy_colonization)

    # Final colonization by strategy
    final_turn = df["turn"].max()
    final_colonization = (
        df.filter(pl.col("turn") == final_turn)
        .group_by("strategy")
        .agg([
            pl.col("total_colonies").mean().alias("avg_final_colonies"),
            pl.col("prestige").mean().alias("avg_final_prestige"),
        ])
        .sort("avg_final_colonies", descending=True)
    )

    print("\n" + "-" * 80)
    print("Final Colonization by Strategy:")
    print("-" * 80)
    print(final_colonization)


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Analyze colonization metrics")
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

    analyze_colonization_rate(df)
    analyze_etac_efficiency(df)
    analyze_by_strategy(df)


if __name__ == "__main__":
    main()
