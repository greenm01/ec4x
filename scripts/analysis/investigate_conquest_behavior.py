#!/usr/bin/env python3.11
"""
Investigate why RBA AI is not conquering planets in Act 2+

This script analyzes:
1. Colony expansion patterns (are colonies being gained?)
2. Fleet positioning (are fleets near unconquered systems?)
3. Military buildup (are invasion-capable ships being built?)
4. Marine production (ground forces needed for invasion)
5. Order submission patterns (are invasion orders being generated?)
"""

import polars as pl
import sqlite3
import sys
import argparse
from pathlib import Path
from glob import glob

def analyze_conquest_behavior(db_paths):
    """Analyze conquest behavior across multiple games"""

    results = []

    for db_path in db_paths:
        if not Path(db_path).exists():
            print(f"Warning: {db_path} not found, skipping...")
            continue

        conn = sqlite3.connect(db_path)
        game_id = Path(db_path).stem.replace('game_', '')

        # Get colony expansion over time
        colony_df = pl.read_database("""
            SELECT
                turn,
                house_id,
                total_colonies,
                colonies_gained,
                colonies_lost
            FROM diagnostics
            ORDER BY turn, house_id
        """, conn)

        # Get marine counts (needed for invasion)
        marine_df = pl.read_database("""
            SELECT
                turn,
                house_id,
                marines_at_colonies,
                marines_on_transports,
                marine_division_units,
                total_transports,
                troop_transport_ships,
                total_ships
            FROM diagnostics
            ORDER BY turn, house_id
        """, conn)

        # Get invasion activity metrics
        invasion_df = pl.read_database("""
            SELECT
                turn,
                house_id,
                total_invasions,
                vulnerable_targets_count,
                invasion_orders_generated,
                invasion_orders_bombard,
                invasion_orders_invade,
                invasion_orders_blitz,
                invasion_orders_canceled,
                colonize_orders_generated,
                active_campaigns_total,
                active_campaigns_scouting,
                active_campaigns_bombardment,
                active_campaigns_invasion,
                campaigns_completed_success
            FROM diagnostics
            ORDER BY turn, house_id
        """, conn)

        # Get fleet tracking data (where are fleets?)
        fleet_df = pl.read_database("""
            SELECT
                turn,
                house_id,
                fleet_id,
                location_system_id,
                active_order_type,
                etac_count,
                scout_count,
                combat_ships,
                troop_transport_count,
                idle_turns_combat,
                idle_turns_etac
            FROM fleet_tracking
            ORDER BY turn, house_id
        """, conn)

        # Get order submission stats
        orders_df = pl.read_database("""
            SELECT
                turn,
                house_id,
                total_orders,
                invalid_orders,
                missed_orders,
                build_orders_generated,
                events_order_completed,
                events_order_failed,
                events_order_rejected
            FROM diagnostics
            ORDER BY turn, house_id
        """, conn)

        conn.close()

        # Analysis 1: Colony expansion by turn bracket
        print(f"\n{'='*60}")
        print(f"Game {game_id}: COLONY EXPANSION ANALYSIS")
        print(f"{'='*60}")

        for turn_bracket in [(1, 7), (8, 15), (16, 25), (26, 35)]:
            bracket_label = f"Turns {turn_bracket[0]}-{turn_bracket[1]}"

            bracket_colonies = colony_df.filter(
                (pl.col("turn") >= turn_bracket[0]) &
                (pl.col("turn") <= turn_bracket[1])
            )

            if len(bracket_colonies) == 0:
                continue

            colonies_gained = bracket_colonies.group_by("house_id").agg([
                pl.col("colonies_gained").sum().alias("total_gained"),
                pl.col("colonies_lost").sum().alias("total_lost"),
                pl.col("total_colonies").max().alias("max_colonies")
            ])

            print(f"\n{bracket_label}:")
            print(colonies_gained)

            avg_gained = colonies_gained["total_gained"].mean()
            print(f"  Average colonies gained per house: {avg_gained:.2f}")

            if avg_gained < 0.5 and turn_bracket[0] >= 8:
                print(f"  ⚠️  WARNING: Very low conquest activity in {bracket_label}")

        # Analysis 2: Marine production
        print(f"\n{'='*60}")
        print(f"Game {game_id}: MARINE & TRANSPORT ANALYSIS")
        print(f"{'='*60}")

        for turn in [7, 15, 25, 35]:
            turn_marines = marine_df.filter(pl.col("turn") == turn)
            if len(turn_marines) > 0:
                avg_marines_colonies = turn_marines["marines_at_colonies"].mean()
                avg_marines_transports = turn_marines["marines_on_transports"].mean()
                avg_marine_divs = turn_marines["marine_division_units"].mean()
                avg_transports = turn_marines["troop_transport_ships"].mean()
                total_marines = avg_marines_colonies + avg_marines_transports

                print(f"\nTurn {turn}:")
                print(f"  Avg Marines (at colonies): {avg_marines_colonies:.1f}")
                print(f"  Avg Marines (on transports): {avg_marines_transports:.1f}")
                print(f"  Avg Total Marines: {total_marines:.1f}")
                print(f"  Avg Marine Divisions: {avg_marine_divs:.1f}")
                print(f"  Avg Troop Transports: {avg_transports:.1f}")

                if total_marines < 10 and turn >= 15:
                    print(f"  ⚠️  WARNING: Low marine count for Turn {turn}")
                if avg_transports < 2 and turn >= 15:
                    print(f"  ⚠️  WARNING: Low transport ship count for Turn {turn}")

        # Analysis 2.5: Invasion activity metrics (NEW)
        print(f"\n{'='*60}")
        print(f"Game {game_id}: INVASION ACTIVITY ANALYSIS")
        print(f"{'='*60}")

        for turn_bracket in [(1, 7), (8, 15), (16, 25), (26, 35)]:
            bracket_label = f"Turns {turn_bracket[0]}-{turn_bracket[1]}"

            bracket_invasion = invasion_df.filter(
                (pl.col("turn") >= turn_bracket[0]) &
                (pl.col("turn") <= turn_bracket[1])
            )

            if len(bracket_invasion) == 0:
                continue

            invasion_summary = bracket_invasion.group_by("house_id").agg([
                pl.col("invasion_orders_generated").sum().alias("orders_generated"),
                pl.col("invasion_orders_invade").sum().alias("invade_orders"),
                pl.col("invasion_orders_bombard").sum().alias("bombard_orders"),
                pl.col("total_invasions").sum().alias("invasions_completed"),
                pl.col("vulnerable_targets_count").max().alias("max_targets_seen"),
                pl.col("colonize_orders_generated").sum().alias("colonize_orders"),
                pl.col("campaigns_completed_success").sum().alias("campaigns_won")
            ])

            print(f"\n{bracket_label}:")
            print(invasion_summary)

            avg_orders = invasion_summary["orders_generated"].mean()
            avg_invasions = invasion_summary["invasions_completed"].mean()
            avg_targets = invasion_summary["max_targets_seen"].mean()

            print(f"  Avg invasion orders generated: {avg_orders:.1f}")
            print(f"  Avg invasions completed: {avg_invasions:.1f}")
            print(f"  Avg max vulnerable targets seen: {avg_targets:.1f}")

            if avg_orders < 1 and turn_bracket[0] >= 8:
                print(f"  ⚠️  WARNING: Very few invasion orders in {bracket_label}")
            if avg_targets > 3 and avg_orders < 1 and turn_bracket[0] >= 8:
                print(f"  ⚠️  CRITICAL: Vulnerable targets exist but NO invasion orders!")

        # Analysis 3: Fleet orders
        print(f"\n{'='*60}")
        print(f"Game {game_id}: FLEET ORDER ANALYSIS")
        print(f"{'='*60}")

        # Count invasion/attack orders (check for non-null active_order_type)
        invasion_orders = fleet_df.filter(
            pl.col("active_order_type").is_not_null() &
            pl.col("active_order_type").str.contains("(?i)invade|attack|bombard")
        )

        if len(invasion_orders) > 0:
            print(f"\nInvasion/Attack/Bombard orders found: {len(invasion_orders)}")
            print(invasion_orders.select([
                "turn", "house_id", "fleet_id", "active_order_type",
                "combat_ships", "troop_transport_count"
            ]).head(10))
        else:
            print("\n⚠️  WARNING: NO invasion/attack/bombard orders found in entire game!")

        # Count ETAC (expansion) fleets
        etac_summary = fleet_df.filter(pl.col("etac_count") > 0).group_by("turn").agg([
            pl.col("etac_count").sum().alias("total_etacs"),
            pl.col("house_id").n_unique().alias("houses_with_etacs")
        ])

        print(f"\nETAC (Expansion) Fleet Activity:")
        if len(etac_summary) > 0:
            print(etac_summary)
        else:
            print("  ⚠️  WARNING: NO ETAC fleets found!")

        # Check for idle combat fleets
        idle_combat = fleet_df.filter(
            (pl.col("combat_ships") > 5) &
            (pl.col("idle_turns_combat") > 3)
        )
        if len(idle_combat) > 0:
            print(f"\n⚠️  WARNING: Found {len(idle_combat)} instances of combat fleets idle >3 turns")
            print(f"   Sample idle fleets:")
            print(idle_combat.select([
                "turn", "house_id", "combat_ships", "idle_turns_combat"
            ]).head(5))

        # Analysis 4: Order submission rates
        print(f"\n{'='*60}")
        print(f"Game {game_id}: ORDER SUBMISSION RATES")
        print(f"{'='*60}")

        for turn in [7, 15, 25, 35]:
            turn_orders = orders_df.filter(pl.col("turn") == turn)
            if len(turn_orders) > 0:
                avg_total = turn_orders["total_orders"].mean()
                avg_invalid = turn_orders["invalid_orders"].mean()
                avg_missed = turn_orders["missed_orders"].mean()
                avg_build = turn_orders["build_orders_generated"].mean()
                avg_completed = turn_orders["events_order_completed"].mean()
                avg_failed = turn_orders["events_order_failed"].mean()

                print(f"\nTurn {turn}:")
                print(f"  Avg Total Orders: {avg_total:.1f}")
                print(f"  Avg Build Orders Generated: {avg_build:.1f}")
                print(f"  Avg Orders Completed: {avg_completed:.1f}")
                print(f"  Avg Orders Failed: {avg_failed:.1f}")
                print(f"  Avg Invalid Orders: {avg_invalid:.1f}")
                print(f"  Avg Missed Orders: {avg_missed:.1f}")

                if avg_total < 5 and turn >= 15:
                    print(f"  ⚠️  WARNING: Very low order activity")
                if avg_missed > 2 and turn >= 15:
                    print(f"  ⚠️  WARNING: AI missing order submissions")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Investigate RBA AI conquest behavior in Act 2+",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Analyze specific seed
  python3.11 scripts/analysis/investigate_conquest_behavior.py -s 12345

  # Analyze multiple seeds
  python3.11 scripts/analysis/investigate_conquest_behavior.py -s 12345 -s 67890

  # Analyze all games in diagnostics folder
  python3.11 scripts/analysis/investigate_conquest_behavior.py balance_results/diagnostics/game_*.db

  # Analyze specific database files
  python3.11 scripts/analysis/investigate_conquest_behavior.py balance_results/diagnostics/game_42.db
        """
    )

    parser.add_argument(
        "-s", "--seed",
        action="append",
        type=int,
        dest="seeds",
        metavar="SEED",
        help="Analyze specific game seed(s). Can be used multiple times. "
             "Looks for balance_results/diagnostics/game_<seed>.db"
    )

    parser.add_argument(
        "db_files",
        nargs="*",
        help="Database file paths to analyze (if not using --seed)"
    )

    args = parser.parse_args()

    # Determine which databases to analyze
    db_paths = []

    if args.seeds:
        # Convert seeds to database paths
        for seed in args.seeds:
            db_path = f"balance_results/diagnostics/game_{seed}.db"
            if Path(db_path).exists():
                db_paths.append(db_path)
            else:
                print(f"Warning: {db_path} not found for seed {seed}")
    elif args.db_files:
        # Use provided database file paths
        db_paths = args.db_files
    else:
        # No arguments provided - show help
        parser.print_help()
        sys.exit(1)

    if not db_paths:
        print("Error: No valid database files found to analyze")
        sys.exit(1)

    analyze_conquest_behavior(db_paths)
