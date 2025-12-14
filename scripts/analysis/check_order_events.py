#!/usr/bin/env python3.11
"""
Check if OrderCompleted events are firing for ETAC fleets
"""

import sqlite3
from pathlib import Path

db_dir = Path("balance_results/diagnostics")
db_files = sorted(db_dir.glob("game_*.db"))
if not db_files:
    print("Error: No database files found")
    exit(1)

db_path = db_files[-1]
conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row

print("=" * 80)
print("Order Events for ETAC Fleets (Turns 1-7)")
print("=" * 80)
print()

# Get all order-related events for ETAC fleets
events = conn.execute("""
    SELECT DISTINCT
        e.turn,
        e.fleet_id,
        e.event_type,
        e.order_type,
        e.system_id,
        e.description
    FROM game_events e
    WHERE e.fleet_id IN (
        SELECT DISTINCT fleet_id
        FROM fleet_tracking
        WHERE etac_count > 0
    )
    AND e.event_type IN ('OrderIssued', 'OrderCompleted', 'OrderFailed', 'OrderAborted', 'FleetArrived')
    AND e.turn <= 7
    ORDER BY e.fleet_id, e.turn, e.event_type
""").fetchall()

if not events:
    print("No order events found for ETAC fleets!")
else:
    current_fleet = None
    for event in events:
        if event['fleet_id'] != current_fleet:
            current_fleet = event['fleet_id']
            print(f"\n{current_fleet}:")
            print("-" * 70)

        order = event['order_type'] or 'none'
        system = str(event['system_id']) if event['system_id'] else 'none'
        event_type = str(event['event_type']) if event['event_type'] else 'none'
        print(f"  Turn {event['turn']:2d} | {event_type:<20s} | "
              f"{order:<12s} | Sys {system:<4s}")

print()

# Check for Move orders that completed
print("\n" + "=" * 80)
print("Move Order Completions (All Fleets, Turns 1-7)")
print("=" * 80)
print()

move_completions = conn.execute("""
    SELECT
        turn,
        fleet_id,
        event_type,
        system_id,
        description
    FROM game_events
    WHERE order_type = 'Move'
      AND event_type IN ('OrderCompleted', 'FleetArrived')
      AND turn <= 7
    ORDER BY turn, fleet_id
""").fetchall()

if not move_completions:
    print("No Move order completions found!")
else:
    print(f"Found {len(move_completions)} Move completions:")
    for event in move_completions:
        event_type = str(event['event_type']) if event['event_type'] else 'none'
        system = str(event['system_id']) if event['system_id'] else 'none'
        print(f"  Turn {event['turn']:2d} | {event['fleet_id']:<40s} | "
              f"{event_type:<20s} | Sys {system}")

print()

# Check fleet_tracking for fleets at turn 5 with Move orders
print("\n" + "=" * 80)
print("ETAC Fleets with Move Orders at Turn 5")
print("=" * 80)
print()

move_fleets = conn.execute("""
    SELECT
        fleet_id,
        location_system_id,
        order_target_system_id,
        has_arrived,
        etac_count
    FROM fleet_tracking
    WHERE turn = 5
      AND etac_count > 0
      AND active_order_type = 'Move'
    ORDER BY fleet_id
""").fetchall()

if not move_fleets:
    print("No ETAC fleets with Move orders at turn 5")
else:
    print(f"Found {len(move_fleets)} ETAC fleets with Move orders:")
    for fleet in move_fleets:
        arrived = "Yes" if fleet['has_arrived'] else "No"
        loc = fleet['location_system_id']
        target = fleet['order_target_system_id']
        at_dest = " (AT DESTINATION)" if loc == target else ""
        print(f"  {fleet['fleet_id']:<40s} | Loc {loc:3d} → Target {target:3d} | "
              f"Arrived: {arrived} | ETACs: {fleet['etac_count']}{at_dest}")

conn.close()
