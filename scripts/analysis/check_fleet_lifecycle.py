#!/usr/bin/env python3.11
"""
Track lifecycle of a specific ETAC fleet to see order transitions
"""

import sqlite3
import sys
from pathlib import Path

def analyze_fleet_lifecycle(db_path, fleet_id):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    print("=" * 80)
    print(f"Fleet Lifecycle: {fleet_id}")
    print("=" * 80)
    print()

    # Get detailed turn-by-turn tracking
    lifecycle = conn.execute("""
        SELECT
            turn,
            location_system_id,
            active_order_type,
            order_target_system_id,
            has_arrived,
            etac_count,
            combat_ships,
            colonists_ptu
        FROM fleet_tracking
        WHERE fleet_id = ?
        ORDER BY turn
    """, (fleet_id,)).fetchall()

    if not lifecycle:
        print(f"Fleet {fleet_id} not found in database")
        return

    print(f"{'Turn':<6} {'Loc':<6} {'Order':<12} {'Target':<8} {'Arrived':<8} {'ETACs':<7} {'Combat':<8} {'PTU':<6}")
    print("-" * 80)

    for row in lifecycle:
        arrived = "Yes" if row['has_arrived'] else "No"
        order = row['active_order_type'] or "None"
        target = str(row['order_target_system_id']) if row['order_target_system_id'] else "none"

        print(f"{row['turn']:<6} {row['location_system_id']:<6} {order:<12} {target:<8} "
              f"{arrived:<8} {row['etac_count']:<7} {row['combat_ships']:<8} {row['colonists_ptu']:<6}")

    print()

    # Check for events related to this fleet
    events = conn.execute("""
        SELECT
            turn,
            event_type,
            description
        FROM game_events
        WHERE fleet_id = ?
        ORDER BY turn
    """, (fleet_id,)).fetchall()

    if events:
        print("Events:")
        print("-" * 80)
        for event in events:
            print(f"Turn {event['turn']:2d} | {event['event_type']:<20s} | {event['description']}")
    else:
        print("No events recorded for this fleet")

    print()
    print("=" * 80)

    conn.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3.11 check_fleet_lifecycle.py <fleet_id> [db_path]")
        print()
        print("Example fleets from most recent game:")

        db_dir = Path("balance_results/diagnostics")
        db_files = sorted(db_dir.glob("game_*.db"))
        if db_files:
            db_path = db_files[-1]
            conn = sqlite3.connect(db_path)
            conn.row_factory = sqlite3.Row

            sample_fleets = conn.execute("""
                SELECT DISTINCT fleet_id, house_id
                FROM fleet_tracking
                WHERE turn = 5 AND etac_count > 0
                LIMIT 5
            """).fetchall()

            print("  " + "\n  ".join(f"{f['fleet_id']} ({f['house_id']})" for f in sample_fleets))
            conn.close()

        sys.exit(1)

    fleet_id = sys.argv[1]

    if len(sys.argv) > 2:
        db_path = sys.argv[2]
    else:
        db_dir = Path("balance_results/diagnostics")
        db_files = sorted(db_dir.glob("game_*.db"))
        if not db_files:
            print("Error: No database files found")
            sys.exit(1)
        db_path = db_files[-1]

    print(f"Analyzing: {db_path}")
    print()
    analyze_fleet_lifecycle(db_path, fleet_id)
