#!/usr/bin/env python3
"""
Diagnostic script to analyze TroopTransport spam in RBA AI simulations.

Usage:
    python3 scripts/analysis/diagnose_transport_spam.py balance_results/diagnostics/game_*.csv
"""

import polars as pl
import sys

def analyze_transport_spam(pattern: str):
    """Analyze TroopTransport construction patterns across game."""

    # Load diagnostics
    df = pl.scan_csv(pattern)

    # Filter for TroopTransport events
    transports_built = (
        df.filter(pl.col("event_type") == "ShipCommissioned")
        .filter(pl.col("ship_class") == "TroopTransport")
        .select([
            "game_id",
            "turn",
            "house_id",
            "ship_class"
        ])
        .collect()
    )

    print("=" * 80)
    print("TROOPTRANSPORT COMMISSIONING ANALYSIS")
    print("=" * 80)
    print(f"\nTotal TroopTransports commissioned: {len(transports_built)}")

    # Per-house breakdown
    by_house = (
        transports_built
        .group_by("house_id")
        .agg([
            pl.count().alias("total_transports"),
            pl.col("turn").min().alias("first_transport_turn"),
            pl.col("turn").max().alias("last_transport_turn")
        ])
        .sort("total_transports", descending=True)
    )

    print("\nPer-House Breakdown:")
    print(by_house)

    # Turn-by-turn rate
    by_turn = (
        transports_built
        .group_by("turn")
        .agg([
            pl.count().alias("transports_this_turn")
        ])
        .sort("turn")
    )

    print("\nTurn-by-Turn Rate:")
    print(by_turn)

    # Act boundaries (approximate)
    print("\n" + "=" * 80)
    print("ACT BREAKDOWN")
    print("=" * 80)

    act1_transports = transports_built.filter(pl.col("turn") <= 7)
    act2_transports = transports_built.filter((pl.col("turn") > 7) & (pl.col("turn") <= 15))
    act3_transports = transports_built.filter((pl.col("turn") > 15) & (pl.col("turn") <= 25))
    act4_transports = transports_built.filter(pl.col("turn") > 25)

    print(f"\nAct 1 (Turns 1-7):   {len(act1_transports)} transports (SHOULD BE 0)")
    print(f"Act 2 (Turns 8-15):  {len(act2_transports)} transports")
    print(f"Act 3 (Turns 16-25): {len(act3_transports)} transports")
    print(f"Act 4 (Turns 26+):   {len(act4_transports)} transports")

    # Check Marine production vs Transport production
    print("\n" + "=" * 80)
    print("MARINES VS TRANSPORTS")
    print("=" * 80)

    marines_built = (
        df.filter(pl.col("event_type") == "UnitCommissioned")
        .filter(pl.col("unit_type") == "Marine")
        .collect()
    )

    print(f"\nTotal Marines commissioned: {len(marines_built)}")
    print(f"Total TroopTransports commissioned: {len(transports_built)}")
    print(f"Ratio: {len(transports_built) / max(1, len(marines_built)):.2f} transports per marine")
    print(f"Expected capacity: {len(transports_built) * 3} Marines (3 per transport)")
    print(f"Actual Marines: {len(marines_built)}")
    print(f"Utilization: {len(marines_built) / max(1, len(transports_built) * 3) * 100:.1f}%")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 diagnose_transport_spam.py balance_results/diagnostics/game_*.csv")
        sys.exit(1)

    pattern = sys.argv[1]
    analyze_transport_spam(pattern)
