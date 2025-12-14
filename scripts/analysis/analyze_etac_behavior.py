#!/usr/bin/env python3.11
"""
ETAC Behavior Analysis - Why does colonization stop after turn 10?

Analyzes:
1. ETAC production vs losses
2. Colonization order generation
3. Budget allocation for construction
4. Available systems vs colonized systems
5. Strategic decision patterns
"""

import polars as pl
import argparse
from pathlib import Path


def analyze_etac_lifecycle(df: pl.DataFrame, game_id: str = "unknown") -> None:
    """Track ETAC production, losses, and net change."""
    print("=" * 80)
    print("ETAC LIFECYCLE ANALYSIS")
    print("=" * 80)
    print()

    # Calculate per turn across all houses
    lifecycle = (
        df.group_by("turn")
        .agg([
            pl.col("etac_ships").mean().alias("avg_etacs"),
            pl.col("etac_ships").sum().alias("total_etacs"),
            pl.col("ships_gained").sum().alias("ships_built"),
            pl.col("ships_lost").sum().alias("ships_destroyed"),
            pl.col("colonies_gained_via_colonization").sum().alias("colonized"),
            pl.col("total_colonies").mean().alias("avg_colonies"),
            pl.col("total_systems_on_map").first().alias("map_size"),
        ])
        .sort("turn")
    )

    print("Turn | Act    | ETACs (Avg) | Ships Built | Ships Lost | Colonized | Map %")
    print("-" * 80)

    for row in lifecycle.iter_rows(named=True):
        turn = row["turn"]
        if turn <= 7:
            act = "Act1"
        elif turn <= 15:
            act = "Act2"
        elif turn <= 25:
            act = "Act3"
        else:
            act = "Act4"

        etacs = row["avg_etacs"]
        built = row["ships_built"]
        lost = row["ships_destroyed"]
        colonized = row["colonized"]
        map_pct = (row["avg_colonies"] / row["map_size"] * 100)

        # Mark turns with no colonization
        marker = "⚠️ " if colonized == 0 and turn <= 15 and map_pct < 75 else "   "

        print(f"{marker}{turn:2} | {act:6} | {etacs:11.2f} | "
              f"{built:11} | {lost:10} | {colonized:9} | {map_pct:5.1f}%")

    print()
    print("💡 Key Questions:")
    print("   • Are ETACs being built in Act 2? (Ships Built column)")
    print("   • Are ETACs being destroyed? (Ships Lost column)")
    print("   • Does colonization stop when ETACs exist? (Colonized vs ETACs)")
    print()


def analyze_build_orders(df: pl.DataFrame, game_id: str = "unknown") -> None:
    """Analyze build order generation and PP spending patterns."""
    print("=" * 80)
    print("BUILD ORDER & BUDGET ANALYSIS")
    print("=" * 80)
    print()

    builds = (
        df.group_by("turn")
        .agg([
            pl.col("build_orders_generated").sum().alias("total_build_orders"),
            pl.col("pp_spent_construction").sum().alias("total_pp_spent"),
            pl.col("production").sum().alias("total_production"),
            pl.col("treasury").mean().alias("avg_treasury"),
            pl.col("etac_ships").mean().alias("avg_etacs"),
        ])
        .sort("turn")
    )

    print("Turn | Act    | Build Orders | PP Spent | Production | Treasury | ETACs")
    print("-" * 80)

    for row in builds.iter_rows(named=True):
        turn = row["turn"]
        if turn <= 7:
            act = "Act1"
        elif turn <= 15:
            act = "Act2"
        elif turn <= 25:
            act = "Act3"
        else:
            act = "Act4"

        orders = row["total_build_orders"]
        spent = row["total_pp_spent"]
        prod = row["total_production"]
        treasury = row["avg_treasury"]
        etacs = row["avg_etacs"]

        # Calculate spending efficiency
        spend_pct = (spent / prod * 100) if prod > 0 else 0

        # Mark low build activity in early game
        marker = "⚠️ " if orders == 0 and turn <= 15 else "   "

        print(f"{marker}{turn:2} | {act:6} | {orders:12} | {spent:8.0f} | "
              f"{prod:10.0f} | {treasury:8.1f} | {etacs:5.2f}")

    print()
    print("💡 Key Questions:")
    print("   • Are build orders being generated? (Build Orders column)")
    print("   • Is PP being spent on construction? (PP Spent column)")
    print("   • Is treasury blocking builds? (Treasury column)")
    print()


def analyze_strategic_decisions(df: pl.DataFrame, game_id: str = "unknown") -> None:
    """Analyze AI strategic decisions and budget allocations."""
    print("=" * 80)
    print("STRATEGIC DECISIONS BY ACT")
    print("=" * 80)
    print()

    # Analyze by act and strategy
    for act_name, (start_turn, end_turn) in [
        ("Act 1", (1, 7)),
        ("Act 2", (8, 15)),
        ("Act 3", (16, 25)),
    ]:
        print(f"📊 {act_name} (Turns {start_turn}-{end_turn}):")
        print("-" * 80)

        act_data = df.filter(
            (pl.col("turn") >= start_turn) & (pl.col("turn") <= end_turn)
        )

        by_strategy = (
            act_data.group_by("strategy")
            .agg([
                pl.col("etac_ships").mean().alias("avg_etacs"),
                pl.col("colonies_gained_via_colonization").sum().alias("colonized"),
                pl.col("build_orders_generated").sum().alias("build_orders"),
                pl.col("pp_spent_construction").sum().alias("pp_construction"),
                pl.col("ships_gained").sum().alias("ships_built"),
                pl.col("total_ships").mean().alias("avg_fleet_size"),
                pl.col("domestikos_budget_allocated").mean().alias("avg_domestikos_budget"),
            ])
            .sort("strategy")
        )

        print(f"{'Strategy':<15} | ETACs | Colonized | Builds | PP Spent | Ships | Fleet | Budget")
        print("-" * 80)

        for row in by_strategy.iter_rows(named=True):
            strat = row["strategy"] if row["strategy"] else "Unknown"
            etacs = row["avg_etacs"]
            colonized = row["colonized"]
            builds = row["build_orders"]
            pp = row["pp_construction"]
            ships = row["ships_built"]
            fleet = row["avg_fleet_size"]
            budget = row["avg_domestikos_budget"]

            print(f"{strat:<15} | {etacs:5.2f} | {colonized:9} | {builds:6} | "
                  f"{pp:8.0f} | {ships:5} | {fleet:5.1f} | {budget:6.1f}")

        print()

    print("💡 Key Questions:")
    print("   • Do strategies differ in ETAC production? (ETACs column)")
    print("   • Is budget allocation changing between acts? (Budget column)")
    print("   • Are builds dropping off in Act 2? (Builds column)")
    print()


def analyze_order_generation(df: pl.DataFrame, game_id: str = "unknown") -> None:
    """Analyze order generation patterns."""
    print("=" * 80)
    print("ORDER GENERATION ANALYSIS")
    print("=" * 80)
    print()

    orders = (
        df.group_by("turn")
        .agg([
            pl.col("total_orders").sum().alias("total_orders"),
            pl.col("invalid_orders").sum().alias("invalid_orders"),
            pl.col("build_orders_generated").sum().alias("build_orders"),
            pl.col("invasion_orders_generated").sum().alias("invasion_orders"),
            pl.col("etac_ships").mean().alias("avg_etacs"),
            pl.col("colonies_gained_via_colonization").sum().alias("colonized"),
        ])
        .sort("turn")
    )

    print("Turn | Act    | Total Orders | Invalid | Builds | Invasions | ETACs | Colonized")
    print("-" * 80)

    for row in orders.iter_rows(named=True):
        turn = row["turn"]
        if turn <= 7:
            act = "Act1"
        elif turn <= 15:
            act = "Act2"
        elif turn <= 25:
            act = "Act3"
        else:
            act = "Act4"

        total = row["total_orders"]
        invalid = row["invalid_orders"]
        builds = row["build_orders"]
        invasions = row["invasion_orders"]
        etacs = row["avg_etacs"]
        colonized = row["colonized"]

        # Mark suspicious patterns
        marker = ""
        if colonized == 0 and etacs > 0 and turn <= 15:
            marker = "❌ "  # ETACs exist but no colonization
        elif invalid > 0:
            marker = "⚠️ "  # Invalid orders being generated
        else:
            marker = "   "

        print(f"{marker}{turn:2} | {act:6} | {total:12} | {invalid:7} | "
              f"{builds:6} | {invasions:9} | {etacs:5.2f} | {colonized:9}")

    print()
    print("💡 Key Findings:")
    print("   ❌ = ETACs exist but no colonization happening")
    print("   ⚠️  = Invalid orders being rejected")
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Analyze ETAC behavior and colonization patterns"
    )
    parser.add_argument(
        "--seed", "-s",
        type=int,
        help="Analyze specific game seed (looks for game_SEED.csv)"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Analyze all games in balance_results/diagnostics/"
    )

    args = parser.parse_args()

    # Determine which files to load
    if args.seed:
        pattern = f"balance_results/diagnostics/game_{args.seed}.csv"
        print(f"📊 Loading game {args.seed}...")
    elif args.all:
        pattern = "balance_results/diagnostics/game_*.csv"
        print("📊 Loading all games...")
    else:
        # Default: try to find latest game
        diagnostic_path = Path("balance_results/diagnostics/")
        if diagnostic_path.exists():
            csv_files = sorted(diagnostic_path.glob("game_*.csv"))
            if csv_files:
                pattern = str(csv_files[-1])
                print(f"📊 Loading latest game: {csv_files[-1].name}...")
            else:
                print("❌ No diagnostic CSV files found")
                print("💡 Run: ./bin/run_simulation -s 12345")
                return
        else:
            print("❌ balance_results/diagnostics/ directory not found")
            return

    # Load data
    try:
        df = pl.read_csv(pattern)
        game_id = args.seed if args.seed else "aggregated"
        print(f"✓ Loaded {len(df)} rows")
        print()
    except Exception as e:
        print(f"❌ Error loading CSV: {e}")
        return

    # Run analyses
    analyze_etac_lifecycle(df, str(game_id))
    analyze_build_orders(df, str(game_id))
    analyze_order_generation(df, str(game_id))
    analyze_strategic_decisions(df, str(game_id))

    print("=" * 80)
    print("ANALYSIS COMPLETE")
    print("=" * 80)
    print()
    print("✓ Next steps:")
    print("  1. Check if ETACs are being destroyed (Ships Lost column)")
    print("  2. Verify build orders continue past turn 10 (Build Orders column)")
    print("  3. Investigate why colonization stops despite available systems")
    print("  4. Check AI strategic decision logic in RBA")
    print()
    print("💡 To analyze multiple games:")
    print("   python3.11 scripts/analysis/analyze_etac_behavior.py --all")
    print()


if __name__ == "__main__":
    main()
