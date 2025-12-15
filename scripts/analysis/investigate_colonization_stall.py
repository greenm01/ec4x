#!/usr/bin/env python3
"""Deep dive into colonization stall - identify uncolonized systems and ETAC behavior"""

import sqlite3
import argparse
from collections import defaultdict

def investigate_stall(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    print("=" * 80)
    print("COLONIZATION STALL INVESTIGATION")
    print("=" * 80)

    # Get all systems and their colonization status over time
    cursor.execute("""
        SELECT turn, house_id, total_colonies
        FROM diagnostics
        ORDER BY turn, house_id
    """)

    colonies_by_turn = defaultdict(lambda: defaultdict(int))
    for turn, house, colonies in cursor.fetchall():
        colonies_by_turn[turn][house] = colonies

    # Check when colonization stalled
    print("\nColonization progress by turn:")
    print("Turn | Total Colonies | Change from Previous")
    print("-----|----------------|---------------------")
    prev_total = 0
    for turn in sorted(colonies_by_turn.keys()):
        total = sum(colonies_by_turn[turn].values())
        change = total - prev_total
        marker = " ← STALLED" if change == 0 and turn > 5 else ""
        print(f" {turn:2d}  |      {total:2d}        |        +{change:2d}{marker}")
        prev_total = total

    # Get ETAC fleet tracking details at key turns
    print("\n" + "=" * 80)
    print("ETAC FLEET BEHAVIOR AT STALL POINTS")
    print("=" * 80)

    for check_turn in [20, 25, 30]:
        print(f"\n{'='*80}")
        print(f"TURN {check_turn} ANALYSIS")
        print(f"{'='*80}")

        cursor.execute("""
            SELECT house_id, fleet_id, location_system_id,
                   etac_count, active_order_type, standing_order_type
            FROM fleet_tracking
            WHERE turn = ? AND etac_count > 0
            ORDER BY house_id, location_system_id
        """, (check_turn,))

        fleets_by_house = defaultdict(list)
        for house, fleet, loc, etacs, active, standing in cursor.fetchall():
            fleets_by_house[house].append({
                'fleet': fleet,
                'location': loc,
                'etacs': etacs,
                'active_order': active or 'None',
                'standing_order': standing or 'None'
            })

        # Analyze convergence - multiple ETACs at same location
        for house in sorted(fleets_by_house.keys()):
            fleets = fleets_by_house[house]
            print(f"\n{house}:")
            print(f"  Total ETACs: {sum(f['etacs'] for f in fleets)}")

            # Group by location
            by_location = defaultdict(list)
            for f in fleets:
                by_location[f['location']].append(f)

            # Find convergence points (3+ ETACs at same location)
            convergence_points = {loc: fs for loc, fs in by_location.items() if len(fs) >= 3}
            if convergence_points:
                print(f"  ⚠️  CONVERGENCE DETECTED:")
                for loc, fs in convergence_points.items():
                    print(f"    System {loc}: {len(fs)} ETACs")
                    for f in fs:
                        print(f"      {f['fleet']}: {f['active_order']} (standing: {f['standing_order']})")

            # Find idle ETACs (None orders)
            idle = [f for f in fleets if f['active_order'] == 'None']
            if idle:
                print(f"  ⚠️  IDLE ETACs: {len(idle)}")
                for f in idle:
                    print(f"    {f['fleet']} at system {f['location']} (standing: {f['standing_order']})")

    # Get colonized systems at turn 34
    print("\n" + "=" * 80)
    print("COLONIZED vs UNCOLONIZED SYSTEMS (Turn 34)")
    print("=" * 80)

    cursor.execute("""
        SELECT house_id, total_colonies
        FROM diagnostics
        WHERE turn = 34
    """)

    total_colonized = sum(row[1] for row in cursor.fetchall())
    print(f"\nTotal colonized: {total_colonized}/61 systems")
    print(f"Uncolonized: {61 - total_colonized} systems")

    # Check if we can identify which systems are uncolonized
    # This would require star map data which might not be in the database
    print("\n⚠️  Need to identify which specific systems are uncolonized")
    print("   Recommendation: Add star map export to diagnostics")

    # Check AutoColonize order assignment pattern
    print("\n" + "=" * 80)
    print("AUTOCOLONIZE ORDER PATTERNS")
    print("=" * 80)

    cursor.execute("""
        SELECT turn, COUNT(DISTINCT fleet_id) as etac_fleets,
               SUM(CASE WHEN active_order_type = 'Colonize' THEN 1 ELSE 0 END) as colonizing,
               SUM(CASE WHEN active_order_type = 'Move' THEN 1 ELSE 0 END) as moving,
               SUM(CASE WHEN active_order_type IS NULL OR active_order_type = 'None' THEN 1 ELSE 0 END) as idle
        FROM fleet_tracking
        WHERE etac_count > 0 AND turn >= 15
        GROUP BY turn
        ORDER BY turn
    """)

    print("\nTurn | ETAC Fleets | Colonizing | Moving | Idle")
    print("-----|-------------|------------|--------|-----")
    for row in cursor.fetchall():
        turn, total, colonizing, moving, idle = row
        print(f" {turn:2d}  |     {total:2d}      |     {colonizing:2d}     |   {moving:2d}   |  {idle:2d}")

    conn.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-s", "--seed", type=int, default=12345)
    args = parser.parse_args()

    db_path = f"balance_results/diagnostics/game_{args.seed}.db"
    try:
        investigate_stall(db_path)
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
