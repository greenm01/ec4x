#!/usr/bin/env python3.11
"""
Check what orders ETAC fleets are receiving
"""

import sqlite3
import sys
from pathlib import Path

def analyze_etac_orders(db_path):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    print("=" * 80)
    print("ETAC Fleet Order Analysis")
    print("=" * 80)
    print()

    # Check what orders ETAC fleets have at turn 5
    print("1. ETAC Fleet Orders at Turn 5")
    print("-" * 80)

    etac_fleets = conn.execute("""
        SELECT
            turn,
            fleet_id,
            house_id,
            active_order_type,
            etac_count,
            combat_ships,
            location_system_id,
            order_target_system_id
        FROM fleet_tracking
        WHERE turn = 5 AND etac_count > 0
        ORDER BY house_id, fleet_id
    """).fetchall()

    if etac_fleets:
        print(f"Found {len(etac_fleets)} ETAC fleets at turn 5:\n")

        order_counts = {}
        for fleet in etac_fleets:
            order_type = fleet['active_order_type'] or 'None'
            order_counts[order_type] = order_counts.get(order_type, 0) + 1

            target = str(fleet['order_target_system_id']) if fleet['order_target_system_id'] else 'none'
            print(f"  {fleet['fleet_id']:40s} | {fleet['house_id']:15s}")
            print(f"    Order: {order_type:15s} | Target: {target:>4s} | "
                  f"ETACs: {fleet['etac_count']} | Combat: {fleet['combat_ships']} | "
                  f"Loc: {fleet['location_system_id']}")

        print()
        print("Order Type Distribution:")
        for order_type, count in sorted(order_counts.items()):
            pct = count / len(etac_fleets) * 100
            print(f"  {order_type:20s}: {count:2d} ({pct:5.1f}%)")
    else:
        print("  No ETAC fleets found at turn 5")

    print()

    # Check colonization targets vs available targets
    print("2. Colonization Target Analysis (Turn 5)")
    print("-" * 80)

    # Get total uncolonized systems
    diagnostics = conn.execute("""
        SELECT
            house_id,
            total_colonies,
            etac_ships,
            colonize_orders_generated,
            total_systems_on_map
        FROM diagnostics
        WHERE turn = 5
        ORDER BY house_id
    """).fetchall()

    total_systems = diagnostics[0]['total_systems_on_map'] if diagnostics else 0

    print(f"Total systems on map: {total_systems}")
    print()

    total_colonized = sum(d['total_colonies'] for d in diagnostics)
    uncolonized = total_systems - total_colonized

    print(f"Colonized systems: {total_colonized}")
    print(f"Uncolonized systems: {uncolonized}")
    print()

    print("Per-house stats:")
    for d in diagnostics:
        print(f"  {d['house_id']:15s}: {d['total_colonies']:2d} colonies | "
              f"{d['etac_ships']} ETACs | {d['colonize_orders_generated']} colonize orders")

    print()

    # Check turns 3-7 for order generation patterns
    print("3. Colonize Order Generation (Turns 3-7)")
    print("-" * 80)

    orders_by_turn = conn.execute("""
        SELECT
            turn,
            house_id,
            etac_ships,
            colonize_orders_generated,
            colonies_gained_via_colonization
        FROM diagnostics
        WHERE turn BETWEEN 3 AND 7
        ORDER BY turn, house_id
    """).fetchall()

    if orders_by_turn:
        current_turn = None
        for row in orders_by_turn:
            if row['turn'] != current_turn:
                current_turn = row['turn']
                print(f"\nTurn {current_turn}:")

            print(f"  {row['house_id']:15s}: {row['etac_ships']} ETACs → "
                  f"{row['colonize_orders_generated']} orders → "
                  f"{row['colonies_gained_via_colonization']} colonies gained")

    print()

    # Check for mixed fleets (combat + ETAC) that might not be getting orders
    print("4. Mixed Fleet Analysis (Turn 5)")
    print("-" * 80)

    mixed_fleets = conn.execute("""
        SELECT
            fleet_id,
            house_id,
            active_order_type,
            etac_count,
            combat_ships
        FROM fleet_tracking
        WHERE turn = 5
          AND etac_count > 0
          AND combat_ships > 0
        ORDER BY house_id, fleet_id
    """).fetchall()

    if mixed_fleets:
        print(f"Found {len(mixed_fleets)} mixed fleets (combat + ETAC):\n")
        for fleet in mixed_fleets:
            order = fleet['active_order_type'] or 'None'
            print(f"  {fleet['fleet_id']:40s} | {fleet['house_id']:15s}")
            print(f"    Order: {order:15s} | ETACs: {fleet['etac_count']} | "
                  f"Combat: {fleet['combat_ships']}")
    else:
        print("  No mixed fleets found")

    print()
    print("=" * 80)

    conn.close()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        db_path = sys.argv[1]
    else:
        db_dir = Path("balance_results/diagnostics")
        db_files = sorted(db_dir.glob("game_*.db"))
        if not db_files:
            print("Error: No database files found")
            sys.exit(1)
        db_path = db_files[-1]

    print(f"Analyzing: {db_path}")
    print()
    analyze_etac_orders(db_path)
