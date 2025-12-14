#!/usr/bin/env python3.11
"""
Diagnose ETAC Colonization Bug

Analyzes SQLite database to understand why colonize orders are generated
but fail to execute in Act 2.
"""

import sqlite3
import sys
from pathlib import Path

def analyze_colonization_bug(db_path):
    """Main analysis function"""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    print("=" * 70)
    print("ETAC Colonization Bug Analysis")
    print("=" * 70)
    print()

    # Get game metadata
    game = conn.execute("SELECT * FROM games").fetchone()
    print(f"Game: {game['game_id']} | Players: {game['num_players']} | Turns: {game['actual_turns']}")
    print()

    # 1. Find turns with colonize orders but no colonies gained
    print("1. COLONIZATION FAILURES")
    print("-" * 70)

    failures = conn.execute("""
        SELECT
            turn,
            house_id,
            colonize_orders_generated,
            colonies_gained_via_colonization,
            etac_ships,
            total_colonies
        FROM diagnostics
        WHERE colonize_orders_generated > 0
          AND colonies_gained_via_colonization = 0
        ORDER BY turn, house_id
    """).fetchall()

    if failures:
        print(f"Found {len(failures)} instances of colonize orders with no colonies gained:")
        print()
        for f in failures:
            print(f"  Turn {f['turn']:2d} | {f['house_id']:20s} | "
                  f"Orders: {f['colonize_orders_generated']} | "
                  f"ETACs: {f['etac_ships']} | "
                  f"Total Colonies: {f['total_colonies']}")
    else:
        print("  No colonization failures found!")

    print()

    # 2. Track ETAC fleets with colonize orders
    print("2. ETAC FLEET TRACKING")
    print("-" * 70)

    etac_fleets = conn.execute("""
        SELECT DISTINCT
            ft.fleet_id,
            ft.house_id,
            MIN(ft.turn) as first_seen,
            MAX(ft.turn) as last_seen
        FROM fleet_tracking ft
        WHERE ft.etac_count > 0
          AND ft.active_order_type = 'Colonize'
        GROUP BY ft.fleet_id, ft.house_id
        ORDER BY ft.house_id, MIN(ft.turn)
    """).fetchall()

    if etac_fleets:
        print(f"Found {len(etac_fleets)} ETAC fleets with colonize orders:")
        print()
        for fleet in etac_fleets:
            print(f"  {fleet['fleet_id']:30s} | {fleet['house_id']:20s} | "
                  f"Turns {fleet['first_seen']}-{fleet['last_seen']}")

            # Get detailed lifecycle for first fleet
            if fleet == etac_fleets[0]:
                print()
                print(f"  Detailed lifecycle of {fleet['fleet_id']}:")
                lifecycle = conn.execute("""
                    SELECT
                        ft.turn,
                        ft.location_system_id,
                        ft.order_target_system_id,
                        ft.has_arrived,
                        ft.etac_count,
                        GROUP_CONCAT(e.event_type) as events
                    FROM fleet_tracking ft
                    LEFT JOIN game_events e ON
                        e.game_id = ft.game_id AND
                        e.turn = ft.turn AND
                        e.fleet_id = ft.fleet_id
                    WHERE ft.game_id = ? AND ft.fleet_id = ?
                    GROUP BY ft.turn
                    ORDER BY ft.turn
                """, (game['game_id'], fleet['fleet_id'])).fetchall()

                for lc in lifecycle:
                    arrived = "✓" if lc['has_arrived'] else " "
                    events_str = lc['events'] or "none"
                    target_str = str(lc['order_target_system_id']) if lc['order_target_system_id'] else "none"
                    print(f"    Turn {lc['turn']:2d}: Loc={lc['location_system_id']:3d} "
                          f"Target={target_str:>4s} "
                          f"Arrived=[{arrived}] ETACs={lc['etac_count']} "
                          f"Events: {events_str}")
    else:
        print("  No ETAC fleets with colonize orders found!")

    print()

    # 3. Examine colonize-related game events
    print("3. COLONIZE ORDER EVENTS")
    print("-" * 70)

    events = conn.execute("""
        SELECT
            turn,
            event_type,
            house_id,
            fleet_id,
            system_id,
            description,
            reason
        FROM game_events
        WHERE order_type = 'Colonize'
           OR description LIKE '%colonize%'
           OR description LIKE '%ETAC%'
        ORDER BY turn, event_type
        LIMIT 50
    """).fetchall()

    if events:
        print(f"Found {len(events)} colonize-related events:")
        print()
        for e in events:
            reason_str = f" | Reason: {e['reason']}" if e['reason'] else ""
            print(f"  Turn {e['turn']:2d} | {e['event_type']:20s} | "
                  f"{e['house_id'] or 'none':20s} | "
                  f"Sys={e['system_id'] or 0:3d}")
            print(f"    {e['description']}{reason_str}")
    else:
        print("  No colonize-related events found!")

    print()

    # 4. Check for order execution patterns
    print("4. ORDER EXECUTION STATISTICS")
    print("-" * 70)

    order_stats = conn.execute("""
        SELECT
            order_type,
            event_type,
            COUNT(*) as count
        FROM game_events
        WHERE order_type IS NOT NULL AND order_type != ''
        GROUP BY order_type, event_type
        ORDER BY order_type, count DESC
    """).fetchall()

    if order_stats:
        current_order = None
        for stat in order_stats:
            if stat['order_type'] != current_order:
                current_order = stat['order_type']
                print(f"\n  {current_order}:")
            print(f"    {stat['event_type']:20s}: {stat['count']:3d}")

    print()

    # 5. Summary and hypothesis
    print("5. DIAGNOSTIC SUMMARY")
    print("-" * 70)

    # Count total colonize orders vs actual colonizations
    total_orders = conn.execute("""
        SELECT SUM(colonize_orders_generated) as total
        FROM diagnostics
    """).fetchone()['total'] or 0

    total_colonized = conn.execute("""
        SELECT SUM(colonies_gained_via_colonization) as total
        FROM diagnostics
    """).fetchone()['total'] or 0

    success_rate = (total_colonized / total_orders * 100) if total_orders > 0 else 0

    print(f"Total colonize orders: {total_orders}")
    print(f"Successful colonizations: {total_colonized}")
    print(f"Success rate: {success_rate:.1f}%")
    print()

    if success_rate < 50:
        print("⚠️  CRITICAL: Colonization success rate is below 50%!")
        print()
        print("Possible causes:")
        print("  1. ETAC fleets not arriving at target systems")
        print("  2. Orders not being executed when fleets arrive")
        print("  3. Target systems already colonized or invalid")
        print("  4. ETAC ships being destroyed/lost in transit")
        print("  5. Order execution logic bug in engine")

    print()
    print("=" * 70)

    conn.close()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        db_path = sys.argv[1]
    else:
        # Default to most recent game
        db_dir = Path("balance_results/diagnostics")
        db_files = sorted(db_dir.glob("game_*.db"))
        if not db_files:
            print("Error: No database files found in balance_results/diagnostics/")
            print("Run a simulation first: ./bin/run_simulation -s 12345 -t 20")
            sys.exit(1)
        db_path = db_files[-1]

    print(f"Analyzing: {db_path}")
    print()
    analyze_colonization_bug(db_path)
