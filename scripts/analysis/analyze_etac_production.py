#!/usr/bin/env python3.11
"""
Analyze ETAC production patterns to verify exponential decay logic.

Checks:
1. ETAC production over time
2. Decay as colonization approaches 100%
3. Act transitions and their impact
"""

import polars as pl
import sqlite3
import sys

def analyze_etac_production(db_path: str):
    """Analyze ETAC production patterns from diagnostics database."""
    conn = sqlite3.connect(db_path)

    # Load diagnostics with ETAC and colonization data
    df = pl.read_database("""
        SELECT
            turn,
            house_id,
            act,
            etac_ships,
            total_colonies,
            total_systems_on_map,
            colonies_gained_via_colonization,
            colonize_orders_generated
        FROM diagnostics
        ORDER BY turn, house_id
    """, conn)

    conn.close()

    print("=" * 80)
    print("ETAC PRODUCTION ANALYSIS")
    print("=" * 80)

    # Calculate colonization progress
    df = df.with_columns([
        ((pl.col("total_colonies") / pl.col("total_systems_on_map")) * 100.0)
        .alias("colonization_pct")
    ])

    # Group by turn to get aggregate stats
    turn_summary = df.group_by("turn").agg([
        pl.col("etac_ships").sum().alias("total_etacs"),
        pl.col("total_colonies").sum().alias("total_colonies_all"),
        pl.col("total_systems_on_map").first().alias("map_systems"),
        pl.col("colonies_gained_via_colonization").sum().alias("new_colonies"),
        pl.col("colonize_orders_generated").sum().alias("colonize_orders"),
        pl.col("act").first().alias("act")
    ]).sort("turn")

    # Calculate colonization progress across all houses
    turn_summary = turn_summary.with_columns([
        ((pl.col("total_colonies_all") / pl.col("map_systems")) * 100.0)
        .alias("map_colonization_pct")
    ])

    print("\n📊 ETAC Production Over Time (All Houses)")
    print("-" * 80)
    print(f"{'Turn':<6} {'Act':<6} {'ETACs':<8} {'Colonies':<10} {'Map %':<10} "
          f"{'New':<6} {'Orders':<8}")
    print("-" * 80)

    for row in turn_summary.iter_rows(named=True):
        print(f"{row['turn']:<6} {row['act']:<6} {row['total_etacs']:<8} "
              f"{row['total_colonies_all']:<10} "
              f"{row['map_colonization_pct']:>7.1f}%  "
              f"{row['new_colonies']:<6} {row['colonize_orders']:<8}")

    # Analyze per-house ETAC production
    print("\n" + "=" * 80)
    print("ETAC PRODUCTION BY HOUSE")
    print("=" * 80)

    houses = df.select("house_id").unique().sort("house_id")

    for house_row in houses.iter_rows(named=True):
        house = house_row["house_id"]
        house_df = df.filter(pl.col("house_id") == house).sort("turn")

        print(f"\n📍 {house}")
        print("-" * 80)
        print(f"{'Turn':<6} {'Act':<6} {'ETACs':<8} {'Colonies':<10} {'Col %':<10} "
              f"{'ΔETAC':<8}")
        print("-" * 80)

        prev_etacs = 0
        for row in house_df.iter_rows(named=True):
            delta_etacs = row['etac_ships'] - prev_etacs
            delta_str = f"+{delta_etacs}" if delta_etacs > 0 else str(delta_etacs)

            print(f"{row['turn']:<6} {row['act']:<6} {row['etac_ships']:<8} "
                  f"{row['total_colonies']:<10} "
                  f"{row['colonization_pct']:>7.1f}%  "
                  f"{delta_str:<8}")

            prev_etacs = row['etac_ships']

    # Analyze decay pattern
    print("\n" + "=" * 80)
    print("DECAY ANALYSIS")
    print("=" * 80)

    # Look at turns where colonization > 70% (where decay should kick in)
    high_colonization = turn_summary.filter(
        pl.col("map_colonization_pct") > 70.0
    ).sort("turn")

    if len(high_colonization) > 0:
        print("\n⚠️  High Colonization Turns (>70% - decay should activate):")
        print("-" * 80)
        print(f"{'Turn':<6} {'Map %':<10} {'Total ETACs':<12} {'New Colonies':<14}")
        print("-" * 80)

        for row in high_colonization.iter_rows(named=True):
            print(f"{row['turn']:<6} {row['map_colonization_pct']:>7.1f}%  "
                  f"{row['total_etacs']:<12} {row['new_colonies']:<14}")

    # Check for Act transitions
    act_transitions = []
    prev_act = None
    for row in turn_summary.iter_rows(named=True):
        if prev_act is not None and row['act'] != prev_act:
            act_transitions.append((row['turn'], prev_act, row['act']))
        prev_act = row['act']

    if act_transitions:
        print("\n📅 Act Transitions:")
        for turn, old_act, new_act in act_transitions:
            print(f"  Turn {turn}: {old_act} → {new_act}")

    # Final summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)

    final_turn = turn_summary.tail(1)
    for row in final_turn.iter_rows(named=True):
        print(f"\nFinal State (Turn {row['turn']}):")
        print(f"  Total ETACs: {row['total_etacs']}")
        print(f"  Map Colonization: {row['map_colonization_pct']:.1f}%")
        print(f"  Total Colonies: {row['total_colonies_all']}/{row['map_systems']}")

    # Check for expected decay behavior
    print("\n✅ Expected Decay Behavior:")
    print("  - Act 1: No decay until >70% colonized")
    print("  - Act 2+: Quadratic decay when <30% systems remain uncolonized")
    print("  - ETAC production should slow significantly in final turns")

    return df, turn_summary


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3.11 analyze_etac_production.py <game_id>")
        print("Example: python3.11 analyze_etac_production.py 99999")
        sys.exit(1)

    game_id = sys.argv[1]
    db_path = f"balance_results/diagnostics/game_{game_id}.db"

    try:
        analyze_etac_production(db_path)
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
