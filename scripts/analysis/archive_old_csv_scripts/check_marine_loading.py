#!/usr/bin/env python3
"""
Check Marine loading and invasion behavior after logistics fix.

Usage:
    python3 scripts/analysis/check_marine_loading.py balance_results/diagnostics/game_99999.csv
"""

import polars as pl
import sys

def analyze_marine_loading(csv_path: str):
    """Analyze Marine loading and invasion patterns."""

    # Load diagnostics
    df = pl.read_csv(csv_path)

    print("=" * 80)
    print("MARINE LOADING & INVASION ANALYSIS")
    print("=" * 80)

    # Get key metrics per turn
    marine_stats = (
        df.group_by("turn")
        .agg([
            pl.col("marine_division_units").sum().alias("total_marines"),
            pl.col("marines_on_transports").sum().alias("loaded_marines"),
            pl.col("troop_transport_ships").sum().alias("total_transports"),
            pl.col("total_invasions").sum().alias("invasions"),
            pl.col("bombard_rounds").sum().alias("bombardments"),
            pl.col("orbital_total").sum().alias("orbital_combats"),
            pl.col("colonies_gained_via_conquest").sum().alias("colonies_captured")
        ])
        .sort("turn")
    )

    print("\nPer-Turn Marine & Combat Stats:")
    print(marine_stats)

    # Check if Marines are staying loaded
    print("\n" + "=" * 80)
    print("MARINE LOADING SUCCESS CHECK")
    print("=" * 80)

    loaded_check = marine_stats.filter(pl.col("turn") >= 5)

    avg_loaded = loaded_check["loaded_marines"].mean()
    avg_transports = loaded_check["total_transports"].mean()

    print(f"\nTurns 5-20 averages:")
    print(f"  Loaded Marines: {avg_loaded:.1f}")
    print(f"  Total Transports: {avg_transports:.1f}")
    print(f"  Load rate: {(avg_loaded / max(1, avg_transports * 3) * 100):.1f}%")

    if avg_loaded > 0:
        print("\n✅ SUCCESS: Marines are staying loaded on transports")
    else:
        print("\n❌ FAIL: Marines still being unloaded")

    # Check invasion activity
    print("\n" + "=" * 80)
    print("INVASION ACTIVITY CHECK")
    print("=" * 80)

    total_invasions = marine_stats["invasions"].sum()
    total_bombardments = marine_stats["bombardments"].sum()
    total_captures = marine_stats["colonies_captured"].sum()

    print(f"\nTotal invasions: {total_invasions}")
    print(f"Total bombardments: {total_bombardments}")
    print(f"Total colonies captured: {total_captures}")

    if total_invasions > 0:
        print("\n✅ SUCCESS: Invasions are executing")
    else:
        print("\n⚠️  WARNING: No invasions yet (may need more turns)")

    if total_captures > 0:
        print("✅ SUCCESS: Colonies are changing hands")
    else:
        print("⚠️  WARNING: No colonies captured yet")

    # Per-house breakdown for invasions
    print("\n" + "=" * 80)
    print("PER-HOUSE COMBAT ACTIVITY (All Turns)")
    print("=" * 80)

    house_combat = (
        df.group_by("house_id")
        .agg([
            pl.col("marine_division_units").mean().alias("avg_marines"),
            pl.col("marines_on_transports").mean().alias("avg_loaded"),
            pl.col("troop_transport_ships").mean().alias("avg_transports"),
            pl.col("total_invasions").sum().alias("invasions"),
            pl.col("bombard_rounds").sum().alias("bombards"),
            pl.col("colonies_gained_via_conquest").sum().alias("captured")
        ])
        .sort("invasions", descending=True)
    )

    print("\n" + str(house_combat))

    # Check space combat (prerequisite for invasions)
    print("\n" + "=" * 80)
    print("SPACE COMBAT (Prerequisite for Invasions)")
    print("=" * 80)

    space_combat = (
        df.group_by("turn")
        .agg([
            pl.col("space_total").sum().alias("space_battles")
        ])
        .filter(pl.col("space_battles") > 0)
        .sort("turn")
    )

    print("\nTurns with space combat:")
    print(space_combat)

    total_space_battles = df["space_total"].sum()
    print(f"\nTotal space battles: {total_space_battles}")

    if total_space_battles > 0:
        print("✅ Fleets are engaging in combat")
    else:
        print("⚠️  No space battles - fleets may not be reaching targets")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 check_marine_loading.py balance_results/diagnostics/game_99999.csv")
        sys.exit(1)

    csv_path = sys.argv[1]
    analyze_marine_loading(csv_path)
