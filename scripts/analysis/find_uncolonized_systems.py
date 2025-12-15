#!/usr/bin/env python3.11
"""
Identify uncolonized systems by analyzing fleet and colony locations.
"""

import sqlite3
import sys

def find_uncolonized_systems(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get all unique system IDs from fleet tracking (proxy for all systems)
    cursor.execute("""
        SELECT DISTINCT location_system_id
        FROM fleet_tracking
        ORDER BY location_system_id
    """)
    all_systems = set(row[0] for row in cursor.fetchall())

    # Get colonized systems at final turn
    cursor.execute("""
        SELECT MAX(turn) FROM diagnostics
    """)
    final_turn = cursor.fetchone()[0]

    # Find systems with colonies (using fleet locations at colonies)
    # This is indirect - we need to infer colonies from diagnostic total_colonies
    cursor.execute(f"""
        SELECT house_id, total_colonies
        FROM diagnostics
        WHERE turn = {final_turn}
    """)

    total_colonies = sum(row[1] for row in cursor.fetchall())
    total_systems = len(all_systems)
    uncolonized_count = total_systems - total_colonies

    print(f"Total systems: {total_systems}")
    print(f"Colonized systems: {total_colonies}")
    print(f"Uncolonized systems: {uncolonized_count}")
    print(f"\nAll system IDs seen in fleet tracking:")
    print(sorted(all_systems))

    # Check ETAC locations at final turn
    cursor.execute(f"""
        SELECT fleet_id, house_id, location_system_id, active_order_type,
               order_target_system_id, etac_count
        FROM fleet_tracking
        WHERE turn = {final_turn} AND etac_count > 0
        ORDER BY house_id, fleet_id
    """)

    print(f"\nETACs at turn {final_turn}:")
    for row in cursor.fetchall():
        fleet_id, house, location, order_type, target, etac_count = row
        print(f"  {fleet_id}: {etac_count} ETACs at system {location}, "
              f"order={order_type}, target={target}")

    conn.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3.11 find_uncolonized_systems.py <db_path>")
        sys.exit(1)

    find_uncolonized_systems(sys.argv[1])
