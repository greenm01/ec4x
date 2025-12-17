#!/usr/bin/env python3.11
"""Check if specific idle ETAC has colonize orders.

Usage:
    python3.11 scripts/analysis/check_specific_etac.py <game_seed> <fleet_id>
"""

import sys
import sqlite3
from pathlib import Path

def check_specific_etac(db_path: str, fleet_id: str):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    print(f"\nTracking {fleet_id} in {db_path}\n")
    print("="*80)

    # Get full history of this fleet
    cursor = conn.execute("""
        SELECT
            turn,
            location_system_id,
            etac_count,
            active_order_type,
            order_target_system_id,
            idle_turns_etac,
            has_arrived
        FROM fleet_tracking
        WHERE fleet_id = ?
        ORDER BY turn
    """, (fleet_id,))

    results = cursor.fetchall()
    if not results:
        print(f"❌ Fleet {fleet_id} not found in database!")
        return

    print(f"Turn | Location | ETACs | Order Type    | Target | Idle | Arrived")
    print("-" * 80)

    for row in results:
        target = row['order_target_system_id'] if row['order_target_system_id'] else "-"
        arrived = "Yes" if row['has_arrived'] else "No"

        # Highlight turns with no orders but ETACs present
        marker = "❌" if row['active_order_type'] == 'None' and row['etac_count'] > 0 else "  "

        print(f"{marker} {row['turn']:2d} | {row['location_system_id']:8d} | "
              f"{row['etac_count']:5d} | {row['active_order_type']:13s} | "
              f"{str(target):>6s} | {row['idle_turns_etac']:4d} | {arrived}")

    conn.close()

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3.11 scripts/analysis/check_specific_etac.py <game_seed> <fleet_id>")
        print("\nExample:")
        print("  python3.11 scripts/analysis/check_specific_etac.py 99999 house-atreides_fleet44")
        sys.exit(1)

    game_seed = sys.argv[1]
    fleet_id = sys.argv[2]
    db_path = f"balance_results/diagnostics/game_{game_seed}.db"

    if not Path(db_path).exists():
        print(f"Error: Database not found: {db_path}")
        sys.exit(1)

    check_specific_etac(db_path, fleet_id)
