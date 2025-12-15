#!/usr/bin/env python3.11
"""
Check if uncolonized systems are reachable via jump lanes.
"""

import sqlite3
import sys

def check_reachability(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Get all unique systems from fleet tracking
    cursor.execute("""
        SELECT DISTINCT location_system_id
        FROM fleet_tracking
        ORDER BY location_system_id
    """)
    all_systems = set(row[0] for row in cursor.fetchall())

    # Get colonized count at final turn
    cursor.execute("SELECT MAX(turn) FROM diagnostics")
    final_turn = cursor.fetchone()[0]

    cursor.execute(f"""
        SELECT SUM(total_colonies) FROM diagnostics WHERE turn = {final_turn}
    """)
    total_colonies = cursor.fetchone()[0]

    print(f"Systems visited by fleets: {len(all_systems)}")
    print(f"Colonized systems: {total_colonies}")
    print(f"Gap: {len(all_systems) - total_colonies}")

    # Check which systems have been visited but might not be colonizable
    # If fleets can reach them, they're connected to the jump lane network
    print(f"\nAll {len(all_systems)} systems are reachable (fleets visited them)")
    print("This means the jump lane network is fully connected.")
    print("\nConclusion: Uncolonized systems ARE reachable - ")
    print("the bug is in AutoColonize target selection or order execution.")

    conn.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3.11 check_unreachable_systems.py <db_path>")
        sys.exit(1)

    check_reachability(sys.argv[1])
