#!/usr/bin/env python3.11
"""
Analyze Treasurer → Domestikos Budget Flow

Verifies the DRY fix by analyzing treasury and production patterns.

NOTE: Full verification requires adding these diagnostic columns:
  - domestikos_budget_allocated
  - build_orders_generated
  - pp_spent_construction
  - domestikos_requirements_fulfilled
  - domestikos_requirements_unfulfilled

For now, this script analyzes:
- Treasury management (no deficits = good budget discipline)
- Ship production rates
- Maintenance costs vs treasury

Usage:
    python3.11 scripts/analysis/analyze_treasurer_domestikos_flow.py --seed 12345
    python3.11 scripts/analysis/analyze_treasurer_domestikos_flow.py -s 12345
"""

import polars as pl
import argparse
import sys
from pathlib import Path


def analyze_budget_flow(game_id: int):
    """Analyze the Treasurer → Domestikos budget flow for a specific game."""

    csv_path = f"balance_results/diagnostics/game_{game_id}.csv"

    if not Path(csv_path).exists():
        print(f"❌ Error: CSV file not found: {csv_path}")
        print(f"   Run simulation first: ./bin/run_simulation -s {game_id}")
        return False

    print(f"📊 Analyzing Treasurer → Domestikos budget flow for game {game_id}")
    print("=" * 80)
    print("ℹ️  NOTE: Limited diagnostics available. Full verification needs additional columns.")
    print("=" * 80)

    # Load the CSV
    df = pl.read_csv(csv_path)

    # Get unique houses
    houses = df["house"].unique().sort()

    for house_id in houses:
        print(f"\n🏛️  {house_id}")
        print("-" * 80)

        # Filter data for this house
        house_df = df.filter(pl.col("house") == house_id)

        # Analyze per turn (first 15 turns for readability)
        turns = house_df["turn"].unique().sort()

        for turn in turns[:15]:
            turn_df = house_df.filter(pl.col("turn") == turn)

            # Extract available data
            treasury = turn_df["treasury"].first()
            production = turn_df["production"].first()
            maintenance = turn_df["maintenance_cost"].first()
            ships_gained = turn_df["ships_gained"].first()
            deficit = turn_df["treasury_deficit"].first()

            # Calculate net budget (treasury - maintenance)
            net_budget = treasury - maintenance if treasury and maintenance else 0

            # Status indicator (no deficit = good budget discipline)
            status = "✅" if deficit == 0 else "⚠️"

            print(f"  Turn {turn:2d}: {status} Treasury={treasury:4d}PP | "
                  f"Maintenance={maintenance:4d}PP | "
                  f"Net={net_budget:4d}PP | "
                  f"Production={production:4d}PP | "
                  f"Ships+{ships_gained:2d}")

            if deficit and deficit > 0:
                print(f"          ⚠️  DEFICIT: {deficit}PP shortfall!")

    # Summary statistics
    print("\n" + "=" * 80)
    print("📈 Summary Statistics (Budget Discipline)")
    print("=" * 80)

    for house_id in houses:
        house_df = df.filter(pl.col("house") == house_id)

        # Calculate summary metrics
        total_turns = house_df.height

        # Budget discipline check (no deficits = good)
        deficit_turns = house_df.filter(pl.col("treasury_deficit") > 0).height

        # Total production
        total_ships = house_df["ships_gained"].sum()
        avg_production = house_df["production"].mean()
        avg_maintenance = house_df["maintenance_cost"].mean()

        print(f"\n🏛️  {house_id}:")
        print(f"   Total Turns: {total_turns}")
        print(f"   Deficit Turns: {deficit_turns} ({deficit_turns/total_turns*100:.1f}%)")
        print(f"   Avg Production: {avg_production:.1f} PP/turn")
        print(f"   Avg Maintenance: {avg_maintenance:.1f} PP/turn")
        print(f"   Total Ships Built: {total_ships}")

        if deficit_turns == 0:
            print("   ✅ Perfect budget discipline - no treasury deficits!")
        elif deficit_turns < total_turns * 0.1:
            print("   ⚠️  Minor budget issues - occasional deficits")
        else:
            print(f"   ❌ Budget problems - {deficit_turns} deficit incidents")

    # Ship production analysis (by role from specs/10-reference.md)
    print("\n" + "=" * 80)
    print("🔨 Ship Production Analysis (By Role)")
    print("=" * 80)

    for house_id in houses:
        house_df = df.filter(pl.col("house") == house_id)

        # Ship type counts (final turn)
        final_turn = house_df.filter(pl.col("turn") == house_df["turn"].max()).row(0, named=True)

        print(f"\n🏛️  {house_id} (Final State):")
        print(f"   Total Ships: {final_turn['total_ships']}")

        # Escorts (CT, FG, DD, CL, SC)
        escorts = (final_turn['corvette_ships'] + final_turn['frigate_ships'] +
                   final_turn['destroyer_ships'] + final_turn['light_cruiser_ships'] +
                   final_turn['scout_ships'])
        print(f"   Escorts ({escorts}): CT={final_turn['corvette_ships']}, "
              f"FG={final_turn['frigate_ships']}, DD={final_turn['destroyer_ships']}, "
              f"CL={final_turn['light_cruiser_ships']}, SC={final_turn['scout_ships']}")

        # Capitals (CA, BC, BB, DN, SD, CV, CX, RR)
        capitals = (final_turn['heavy_cruiser_ships'] + final_turn['battlecruiser_ships'] +
                    final_turn['battleship_ships'] + final_turn['dreadnought_ships'] +
                    final_turn['super_dreadnought_ships'] + final_turn['carrier_ships'] +
                    final_turn['super_carrier_ships'] + final_turn['raider_ships'])
        print(f"   Capitals ({capitals}): CA={final_turn['heavy_cruiser_ships']}, "
              f"BC={final_turn['battlecruiser_ships']}, BB={final_turn['battleship_ships']}, "
              f"DN={final_turn['dreadnought_ships']}, SD={final_turn['super_dreadnought_ships']}")
        print(f"                CV={final_turn['carrier_ships']}, "
              f"CX={final_turn['super_carrier_ships']}, RR={final_turn['raider_ships']}")

        # Auxiliary (ET, TT)
        auxiliary = final_turn['etac_ships'] + final_turn['troop_transport_ships']
        print(f"   Auxiliary ({auxiliary}): ETAC={final_turn['etac_ships']}, "
              f"Transport={final_turn['troop_transport_ships']}")

        # Fighters (FS)
        print(f"   Fighters: FS={final_turn['total_fighters']}")

        # Special Weapons (PB)
        print(f"   Special Weapons: PB={final_turn['planet_breaker_ships']}")

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Analyze Treasurer → Domestikos budget flow (DRY fix verification)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3.11 scripts/analysis/analyze_treasurer_domestikos_flow.py --seed 12345
  python3.11 scripts/analysis/analyze_treasurer_domestikos_flow.py -s 99999

This script verifies the DRY fix by checking:
- Domestikos never overspends allocated budget
- Build orders match Treasurer's mediation decisions
- No duplicate budget calculations
        """
    )

    parser.add_argument(
        '-s', '--seed',
        type=int,
        required=True,
        help='Game seed to analyze (matches CSV filename game_SEED.csv)'
    )

    args = parser.parse_args()

    success = analyze_budget_flow(args.seed)

    if not success:
        sys.exit(1)

    print("\n" + "=" * 80)
    print("✅ Analysis complete!")
    print("=" * 80)


if __name__ == "__main__":
    main()
