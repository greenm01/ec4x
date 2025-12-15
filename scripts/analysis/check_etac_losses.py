#!/usr/bin/env python3
"""Analyze ETAC fleet losses and reasons"""

import sqlite3
import argparse

def analyze_etac_losses(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    print("=" * 80)
    print("ETAC FLEET TRACKING")
    print("=" * 80)

    # Track ETAC fleets over time
    cursor.execute("""
        SELECT turn, house_id, fleet_id, location_system_id,
               etac_count, ships_total, active_order_type
        FROM fleet_tracking
        WHERE etac_count > 0
        ORDER BY turn, house_id, fleet_id
    """)

    fleets_by_turn = {}
    for row in cursor.fetchall():
        turn, house, fleet, location, etacs, total, order = row
        if turn not in fleets_by_turn:
            fleets_by_turn[turn] = {}
        if house not in fleets_by_turn[turn]:
            fleets_by_turn[turn][house] = []
        fleets_by_turn[turn][house].append({
            'fleet': fleet,
            'location': location,
            'etacs': etacs,
            'total': total,
            'order': order
        })

    # Check key turns
    for turn in [10, 15, 20, 25, 30]:
        if turn not in fleets_by_turn:
            continue

        print(f"\nTurn {turn}:")
        for house in sorted(fleets_by_turn[turn].keys()):
            fleets = fleets_by_turn[turn][house]
            total_etacs = sum(f['etacs'] for f in fleets)
            print(f"  {house}: {total_etacs} ETACs in {len(fleets)} fleets")
            for f in fleets:
                print(f"    {f['fleet']}: {f['etacs']} ETACs at {f['location']} ({f['order']})")

    # Check ETAC count changes and ship losses
    print("\n" + "=" * 80)
    print("ETAC COUNT CHANGES & SHIP LOSSES")
    print("=" * 80)

    cursor.execute("""
        SELECT turn, house_id, etac_ships, ships_lost, ships_gained
        FROM diagnostics
        WHERE turn >= 20 AND turn <= 30
        ORDER BY turn, house_id
    """)

    print("\nTurns 20-30 (when ETAC counts collapsed):")
    for row in cursor.fetchall():
        turn, house, etacs, lost, gained = row
        if lost > 0 or gained > 0:
            print(f"Turn {turn} {house}: {etacs} ETACs | Lost: {lost} | Gained: {gained}")

    # Check total ETAC production over time
    print("\n" + "=" * 80)
    print("ETAC PRODUCTION HISTORY")
    print("=" * 80)

    cursor.execute("""
        SELECT turn,
               SUM(etac_ships) as total_etacs,
               SUM(ships_lost) as total_lost,
               SUM(ships_gained) as total_gained
        FROM diagnostics
        GROUP BY turn
        ORDER BY turn
    """)

    print("\nTurn | Total ETACs | Ships Lost | Ships Gained")
    print("-----|-------------|------------|-------------")
    for row in cursor.fetchall():
        turn, etacs, lost, gained = row
        if turn <= 5 or turn % 5 == 0 or turn == 34:
            print(f" {turn:2d}  |     {etacs:2d}      |     {lost:2d}     |     {gained:2d}")

    print("=" * 80)
    conn.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-s", "--seed", type=int, default=12345)
    args = parser.parse_args()

    db_path = f"balance_results/diagnostics/game_{args.seed}.db"
    try:
        analyze_etac_losses(db_path)
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
