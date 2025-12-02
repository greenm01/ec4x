#!/usr/bin/env python3
"""
Example custom analysis using Polars.

Demonstrates how to efficiently query diagnostic data for specific insights.
Run after generating Parquet file with: nimble convertToParquet

Examples:
    # Fighter production analysis
    python3 tools/ai_tuning/example_custom_analysis.py fighters

    # Treasury patterns
    python3 tools/ai_tuning/example_custom_analysis.py treasury

    # Combat effectiveness
    python3 tools/ai_tuning/example_custom_analysis.py combat
"""

import sys
from pathlib import Path

try:
    import polars as pl
except ImportError:
    print("ERROR: Polars not installed. Run: pip install polars")
    sys.exit(1)


def load_data():
    """Load Parquet file."""
    parquet_path = Path("balance_results/diagnostics_combined.parquet")

    if not parquet_path.exists():
        print("ERROR: Parquet file not found. Run: nimble convertToParquet")
        sys.exit(1)

    return pl.read_parquet(parquet_path)


def analyze_fighters(df):
    """Analyze fighter production and deployment."""
    print("=" * 70)
    print("Fighter Production Analysis")
    print("=" * 70)

    # Fighter count by turn (aggregate across all houses)
    by_turn = df.group_by("turn").agg([
        pl.col("total_fighters").mean().alias("avg_fighters"),
        pl.col("total_fighters").max().alias("max_fighters"),
        pl.col("total_carriers").mean().alias("avg_carriers"),
    ]).sort("turn")

    print("\nFighters by Turn (first 30 turns):")
    print(by_turn.head(30))

    # Houses with fighters
    with_fighters = df.filter(pl.col("total_fighters") > 0)
    print(f"\nTurns with fighters: {len(with_fighters)}/{len(df)} ({len(with_fighters)/len(df)*100:.1f}%)")

    # Capacity violations
    violations = df.filter(pl.col("capacity_violations") > 0)
    print(f"Capacity violations: {len(violations)}/{len(df)} ({len(violations)/len(df)*100:.2f}%)")

    # High fighter games
    high_fighters = df.filter(pl.col("total_fighters") >= 10)
    if len(high_fighters) > 0:
        print(f"\nTurns with 10+ fighters: {len(high_fighters)}")
        print("\nSample turns with high fighter count:")
        print(high_fighters.select([
            "turn", "house", "total_fighters", "total_carriers", "fighter_ships"
        ]).head(10))


def analyze_treasury(df):
    """Analyze treasury and spending patterns."""
    print("=" * 70)
    print("Treasury & Spending Analysis")
    print("=" * 70)

    # Zero-spend analysis
    zero_spend = df.filter(pl.col("zero_spend_turns") > 0)
    high_zero_spend = df.filter(pl.col("zero_spend_turns") > 10)

    print(f"\nTurns with zero-spend streaks: {len(zero_spend)}/{len(df)}")
    print(f"Turns with 10+ zero-spend streak: {len(high_zero_spend)}/{len(df)}")

    # Treasury by turn
    treasury_by_turn = df.group_by("turn").agg([
        pl.col("treasury").mean().alias("avg_treasury"),
        pl.col("treasury").max().alias("max_treasury"),
        pl.col("production").mean().alias("avg_production"),
    ]).sort("turn")

    print("\nTreasury by Turn (first 30 turns):")
    print(treasury_by_turn.head(30))

    # Find hoarding cases
    hoarders = df.filter(
        (pl.col("treasury") > 1000) &
        (pl.col("zero_spend_turns") > 5)
    )

    if len(hoarders) > 0:
        print(f"\nPotential hoarding detected: {len(hoarders)} cases")
        print("\nSample hoarding cases:")
        print(hoarders.select([
            "turn", "house", "treasury", "production", "zero_spend_turns"
        ]).head(10))


def analyze_combat(df):
    """Analyze combat effectiveness."""
    print("=" * 70)
    print("Combat Effectiveness Analysis")
    print("=" * 70)

    # Overall combat stats
    total_wins = df.select(pl.col("space_wins").sum()).item()
    total_losses = df.select(pl.col("space_losses").sum()).item()
    total_battles = total_wins + total_losses

    if total_battles > 0:
        win_rate = total_wins / total_battles * 100
        print(f"\nTotal space battles: {total_battles}")
        print(f"Win rate: {win_rate:.1f}% (should be ~50% in balanced play)")
    else:
        print("\nNo space battles recorded")

    # Combat by turn
    combat_by_turn = df.group_by("turn").agg([
        pl.col("space_wins").sum().alias("wins"),
        pl.col("space_losses").sum().alias("losses"),
        pl.col("space_total").sum().alias("total_battles"),
    ]).sort("turn")

    print("\nCombat by Turn (first 30 turns):")
    print(combat_by_turn.head(30))

    # Orbital failures (won space but lost orbital)
    orbital_failures = df.select(pl.col("orbital_failures").sum()).item()
    orbital_total = df.select(pl.col("orbital_total").sum()).item()

    if orbital_total > 0:
        failure_rate = orbital_failures / orbital_total * 100
        print(f"\nOrbital phase:")
        print(f"  Total attempts: {orbital_total}")
        print(f"  Failures: {orbital_failures}")
        print(f"  Failure rate: {failure_rate:.1f}%")
        if failure_rate > 20:
            print("  ⚠ High failure rate suggests starbase strength underestimated")


def analyze_custom_query(df):
    """Interactive custom query."""
    print("=" * 70)
    print("Custom Query Mode")
    print("=" * 70)
    print("\nAvailable columns:")
    print(", ".join(sorted(df.columns)))
    print("\nExample queries:")
    print("  df.filter(pl.col('total_fighters') > 10)")
    print("  df.group_by('house').agg(pl.col('space_wins').sum())")
    print("  df.select(['turn', 'house', 'treasury', 'total_fighters'])")
    print("\nEntering Python REPL with 'df' loaded...")
    print("Press Ctrl+D to exit\n")

    import code
    code.interact(local={'df': df, 'pl': pl})


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 example_custom_analysis.py <analysis>")
        print("\nAvailable analyses:")
        print("  fighters  - Fighter production and deployment")
        print("  treasury  - Treasury and spending patterns")
        print("  combat    - Combat effectiveness")
        print("  custom    - Interactive query mode")
        sys.exit(1)

    analysis_type = sys.argv[1].lower()

    # Load data
    print("Loading diagnostics...")
    df = load_data()
    print(f"Loaded {len(df):,} rows, {len(df.columns)} columns\n")

    # Run analysis
    if analysis_type == "fighters":
        analyze_fighters(df)
    elif analysis_type == "treasury":
        analyze_treasury(df)
    elif analysis_type == "combat":
        analyze_combat(df)
    elif analysis_type == "custom":
        analyze_custom_query(df)
    else:
        print(f"ERROR: Unknown analysis type: {analysis_type}")
        sys.exit(1)


if __name__ == "__main__":
    main()
