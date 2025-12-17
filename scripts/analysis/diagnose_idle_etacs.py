#!/usr/bin/env python3.11
"""Diagnose why ETACs are sitting idle after turn 6.

Usage:
    python3.11 scripts/analysis/diagnose_idle_etacs.py <game_seed>

Example:
    python3.11 scripts/analysis/diagnose_idle_etacs.py 12345
"""

import sys
import sqlite3
from pathlib import Path

def diagnose_idle_etacs(db_path: str):
    """Analyze idle ETAC behavior."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    print(f"\n{'='*80}")
    print(f"IDLE ETAC DIAGNOSTIC REPORT")
    print(f"{'='*80}\n")

    # 1. Find all idle ETACs (idle > 1 turn)
    print("1. ETACs idle for multiple turns:\n")
    cursor = conn.execute("""
        SELECT
            turn,
            house_id,
            fleet_id,
            location_system_id,
            etac_count,
            idle_turns_etac,
            active_order_type,
            order_target_system_id
        FROM fleet_tracking
        WHERE etac_count > 0 AND idle_turns_etac > 1
        ORDER BY house_id, turn, idle_turns_etac DESC
    """)

    idle_etacs = cursor.fetchall()
    if not idle_etacs:
        print("   ✓ No ETACs found idle for multiple turns!")
    else:
        print(f"   Found {len(idle_etacs)} idle ETAC fleet snapshots:\n")
        for row in idle_etacs:
            print(f"   Turn {row['turn']:3d} | {row['house_id']:12s} | "
                  f"Fleet {row['fleet_id']:20s} | "
                  f"Location: {row['location_system_id']:4d} | "
                  f"ETACs: {row['etac_count']} | "
                  f"Idle: {row['idle_turns_etac']} turns")

    # 2. Check colonization progress at turn 6
    print(f"\n2. Colonization status at turn 6:\n")
    cursor = conn.execute("""
        SELECT
            house_id,
            total_colonies,
            colonies_gained,
            etac_ships,
            total_systems_on_map
        FROM diagnostics
        WHERE turn = 6
        ORDER BY house_id
    """)

    turn6_data = cursor.fetchall()
    for row in turn6_data:
        colonized_pct = (row['total_colonies'] / row['total_systems_on_map'] * 100)
        print(f"   {row['house_id']:12s}: {row['total_colonies']:2d} colonies "
              f"({colonized_pct:5.1f}% of {row['total_systems_on_map']} systems) | "
              f"ETACs: {row['etac_ships']}")

    # 3. Track specific idle ETAC example
    if idle_etacs:
        example = idle_etacs[0]
        print(f"\n3. Tracking example idle ETAC: {example['fleet_id']} ({example['house_id']}):\n")

        cursor = conn.execute("""
            SELECT
                turn,
                location_system_id,
                etac_count,
                idle_turns_etac,
                active_order_type,
                order_target_system_id,
                has_arrived
            FROM fleet_tracking
            WHERE fleet_id = ? AND house_id = ?
            ORDER BY turn
        """, (example['fleet_id'], example['house_id']))

        history = cursor.fetchall()
        print(f"   Turn | Location | ETACs | Idle | Order Type    | Target | Arrived")
        print(f"   {'-'*72}")
        for row in history:
            target = str(row['order_target_system_id']) if row['order_target_system_id'] else "-"
            arrived = "Yes" if row['has_arrived'] else "No"
            print(f"   {row['turn']:4d} | {row['location_system_id']:8d} | "
                  f"{row['etac_count']:5d} | {row['idle_turns_etac']:4d} | "
                  f"{row['active_order_type']:13s} | {target:>6s} | {arrived}")

    # 4. Check if all systems are colonized
    print(f"\n4. Uncolonized systems remaining:\n")
    cursor = conn.execute("""
        SELECT
            turn,
            COUNT(DISTINCT house_id) as num_houses,
            AVG(total_systems_on_map) as total_systems,
            SUM(total_colonies) as colonized_systems
        FROM diagnostics
        WHERE turn >= 6 AND turn <= 10
        GROUP BY turn
        ORDER BY turn
    """)

    for row in cursor.fetchall():
        uncolonized = int(row['total_systems'] - row['colonized_systems'])
        print(f"   Turn {row['turn']:2d}: {uncolonized:3d} uncolonized systems remaining")

    # 5. Check for ETAC assignment conflicts
    print(f"\n5. Multiple ETACs targeting same system:\n")
    cursor = conn.execute("""
        SELECT
            turn,
            order_target_system_id,
            COUNT(*) as etac_fleet_count,
            GROUP_CONCAT(house_id || ':' || fleet_id) as fleets
        FROM fleet_tracking
        WHERE etac_count > 0
          AND order_target_system_id IS NOT NULL
          AND turn >= 6
        GROUP BY turn, order_target_system_id
        HAVING COUNT(*) > 1
        ORDER BY turn, etac_fleet_count DESC
    """)

    conflicts = cursor.fetchall()
    if not conflicts:
        print("   ✓ No assignment conflicts found!")
    else:
        print(f"   Found {len(conflicts)} cases of multiple ETACs targeting same system:\n")
        for row in conflicts[:10]:  # Show first 10
            target_sys = row['order_target_system_id']
            if target_sys is None:
                target_str = "None"
            else:
                target_str = str(target_sys)
            print(f"   Turn {row['turn']:3d} | System {target_str:>6s} | "
                  f"{row['etac_fleet_count']} ETACs targeting")

    print(f"\n{'='*80}\n")
    conn.close()

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3.11 scripts/analysis/diagnose_idle_etacs.py <game_seed>")
        print("\nExample:")
        print("  python3.11 scripts/analysis/diagnose_idle_etacs.py 12345")
        sys.exit(1)

    game_seed = sys.argv[1]
    db_path = f"balance_results/diagnostics/game_{game_seed}.db"

    if not Path(db_path).exists():
        print(f"Error: Database not found: {db_path}")
        print(f"\nRun simulation first:")
        print(f"  ./bin/run_simulation -s {game_seed}")
        sys.exit(1)

    diagnose_idle_etacs(db_path)
