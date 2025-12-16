#!/usr/bin/env python3
"""
Check if houses have the military assets needed to generate Invade orders.

Per offensive_ops.nim, Invade orders require:
- TroopTransports (to carry Marines)
- Marines (ground assault forces)
- Sufficient combined strength to overcome defenses

This script checks if the absence of Invade orders is due to:
1. Lack of TroopTransports
2. Lack of Marines
3. Insufficient strength ratios
"""

import polars as pl
import argparse

def analyze_invasion_capability(seed: int):
    """Analyze why houses aren't generating Invade orders."""

    csv_path = f"balance_results/diagnostics/game_{seed}.csv"

    try:
        df = pl.read_csv(csv_path)
    except FileNotFoundError:
        print(f"Error: {csv_path} not found")
        print(f"Run: ./bin/run_simulation -s {seed} --fixed-turns -t 35")
        return

    print(f"Invasion Capability Analysis (game {seed})")
    print("=" * 70)

    # Check available columns
    columns = df.columns

    # Map to actual column names
    transport_col = "troop_transport_ships"
    marines_col = "marines_at_colonies"  # Total marines at colonies
    marines_transport_col = "marines_on_transports"  # Marines loaded on transports

    required_cols = [transport_col, marines_col]
    missing_cols = [c for c in required_cols if c not in columns]

    if missing_cols:
        print(f"\n⚠️  Missing columns: {missing_cols}")
        print("Available columns:", columns)
        print("\nNeed to rebuild diagnostics.nim to include these metrics")
        return

    # Get final turn data
    final_turn = df.select(pl.col("turn").max()).item()

    # Military capability over time (last 10 turns)
    print("\n[MILITARY BUILDUP] Last 10 turns")
    print("-" * 70)

    military_timeline = (
        df.filter(pl.col("turn") >= final_turn - 9)
        .group_by("turn")
        .agg([
            pl.col(transport_col).sum().alias("transports"),
            pl.col(marines_col).sum().alias("marines_at_colonies"),
            pl.col(marines_transport_col).sum().alias("marines_on_transports"),
            pl.col("destroyer_ships").sum().alias("destroyers"),
            pl.col("battleship_ships").sum().alias("battleships"),
            pl.col("invasion_orders_bombard").sum().alias("bombard_orders"),
            pl.col("invasion_orders_invade").sum().alias("invade_orders")
        ])
        .sort("turn")
    )
    print(military_timeline)

    # Per-house analysis for final turn
    print(f"\n[HOUSE ANALYSIS] Turn {final_turn}")
    print("-" * 70)

    house_data = (
        df.filter(pl.col("turn") == final_turn)
        .select([
            "house",
            transport_col,
            marines_col,
            marines_transport_col,
            "destroyer_ships",
            "battleship_ships",
            "vulnerable_targets_count",
            "invasion_orders_bombard",
            "invasion_orders_invade",
            "active_campaigns_total"
        ])
        .sort("house")
    )
    print(house_data)

    # Check invasion capability threshold
    print("\n[CAPABILITY CHECK]")
    print("-" * 70)

    capable_houses = (
        df.filter(pl.col("turn") == final_turn)
        .filter(
            (pl.col(transport_col) > 0) &
            (pl.col(marines_col) > 0)
        )
        .select(["house", transport_col, marines_col, marines_transport_col])
    )

    if len(capable_houses) > 0:
        print(f"✅ {len(capable_houses)} houses have invasion capability:")
        print(capable_houses)
    else:
        print("❌ NO houses have invasion capability!")
        print("   Houses are generating Bombard orders because they lack:")
        print("   - TroopTransports (to carry Marines)")
        print("   - Marines (ground assault forces)")

    # Check if houses ever had these assets
    print("\n[ASSET HISTORY] Did houses ever build invasion assets?")
    print("-" * 70)

    # Check max values over entire game
    max_transports_per_house = (
        df.group_by("house")
        .agg([
            pl.col(transport_col).max().alias("max_transports"),
            pl.col(marines_col).max().alias("max_marines")
        ])
        .sort("house")
    )
    print(max_transports_per_house)

    # Check if anyone ever had invasion capability
    total_max_transports = max_transports_per_house.select(
        pl.col("max_transports").sum()
    ).item()
    total_max_marines = max_transports_per_house.select(
        pl.col("max_marines").sum()
    ).item()

    if total_max_transports == 0:
        print("\n❌ NO house ever built TroopTransports!")
        print("   → Check: RBA build priorities in budget.nim")
        print("   → Check: TroopTransport construction costs in config")

    if total_max_marines == 0:
        print("\n❌ NO house ever built Marines!")
        print("   → Check: RBA build priorities in budget.nim")
        print("   → Check: Marine construction costs in config")

    # Strategic analysis
    print("\n[DIAGNOSIS]")
    print("=" * 70)

    if total_max_transports == 0 and total_max_marines == 0:
        print("❌ ROOT CAUSE: Houses never built invasion assets")
        print()
        print("   RBA AI is not prioritizing TroopTransports or Marines in build queue.")
        print("   This explains why only Bombard orders are generated:")
        print("   - Bombard uses Battleships/Destroyers (which ARE being built)")
        print("   - Invade requires TroopTransports + Marines (which are NOT built)")
        print()
        print("   Next steps:")
        print("   1. Check RBA build priority logic in src/ai/rba/budget.nim")
        print("   2. Check if invasion capability is considered in strategy profiles")
        print("   3. Verify TroopTransport/Marine costs aren't prohibitively expensive")
    elif len(capable_houses) == 0:
        print("⚠️  Houses built some invasion assets but never had both at same time")
        print("   → Check: Build queue coordination")
        print("   → Check: Asset survival rates (transports getting destroyed?)")
    else:
        print("⚠️  Houses HAVE invasion capability but aren't using it")
        print(f"   {len(capable_houses)} houses have TroopTransports + Marines")
        print("   → Check: Fleet composition requirements for Invade orders")
        print("   → Check: Strength calculation thresholds in offensive_ops.nim")
        print("   → Check: If Marines need to be loaded on transports first")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Analyze invasion capability and identify why Invade orders aren't generated"
    )
    parser.add_argument("--seed", "-s", type=int, default=12345,
                        help="Game seed to analyze (default: 12345)")
    args = parser.parse_args()

    analyze_invasion_capability(args.seed)
