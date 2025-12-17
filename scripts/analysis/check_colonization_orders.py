#!/usr/bin/env python3.11
"""Check if colonization orders are being generated.

Usage:
    python3.11 scripts/analysis/check_colonization_orders.py <game_seed>
"""

import sys
import sqlite3
from pathlib import Path

def check_colonization_orders(db_path: str):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    print(f"\nChecking colonization orders in {db_path}\n")
    print("="*80)

    # Check if ANY Colonize orders exist
    cursor = conn.execute("""
        SELECT
            turn,
            house_id,
            COUNT(*) as colonize_order_count
        FROM fleet_tracking
        WHERE active_order_type = 'Colonize'
        GROUP BY turn, house_id
        ORDER BY turn, house_id
    """)

    results = cursor.fetchall()
    if not results:
        print("❌ NO COLONIZE ORDERS FOUND IN DATABASE!")
        print("\nThis means expansion logic is NOT generating orders.")
    else:
        print(f"✓ Found Colonize orders:")
        for row in results:
            print(f"  Turn {row['turn']:2d} | {row['house_id']:12s} | {row['colonize_order_count']} Colonize orders")

    # Check ETAC counts over time
    print(f"\n{'='*80}")
    print("ETAC counts per turn (should increase as they're built):\n")
    cursor = conn.execute("""
        SELECT
            turn,
            house_id,
            SUM(etac_count) as total_etacs,
            COUNT(DISTINCT fleet_id) as fleet_count
        FROM fleet_tracking
        WHERE etac_count > 0
        GROUP BY turn, house_id
        ORDER BY turn, house_id
    """)

    for row in cursor.fetchall():
        print(f"  Turn {row['turn']:2d} | {row['house_id']:12s} | "
              f"{row['total_etacs']:2d} ETACs in {row['fleet_count']:2d} fleets")

    conn.close()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3.11 scripts/analysis/check_colonization_orders.py <game_seed>")
        sys.exit(1)

    game_seed = sys.argv[1]
    db_path = f"balance_results/diagnostics/game_{game_seed}.db"

    if not Path(db_path).exists():
        print(f"Error: Database not found: {db_path}")
        sys.exit(1)

    check_colonization_orders(db_path)
