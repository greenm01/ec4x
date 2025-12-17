#!/usr/bin/env python3.11
"""
Analyze idle ETAC fleets after colonization
Shows the problem with empty fleets remaining after ETACs deposit cargo
"""

import sqlite3
import polars as pl
import sys

if len(sys.argv) < 2:
    print("Usage: python3.11 analyze_idle_etacs.py <game_id>")
    sys.exit(1)

game_id = sys.argv[1]
db_path = f"balance_results/diagnostics/game_{game_id}.db"

conn = sqlite3.connect(db_path)

# Query 1: Count empty fleets (no ships, no ETACs) by turn
empty_fleets = pl.read_database("""
    SELECT
        turn,
        house_id,
        COUNT(DISTINCT fleet_id) as empty_fleets_count
    FROM fleet_tracking
    WHERE etac_count = 0
      AND scout_count = 0
      AND combat_ships = 0
      AND active_order_type = 'None'
    GROUP BY turn, house_id
    ORDER BY turn, house_id
""", conn)

print("="*70)
print("EMPTY IDLE FLEETS BY TURN (post-colonization waste)")
print("="*70)
print(empty_fleets)

# Query 2: Total ETAC status
etac_status = pl.read_database("""
    SELECT
        turn,
        COUNT(DISTINCT fleet_id) as total_etac_fleets,
        SUM(CASE WHEN active_order_type = 'Colonize' THEN 1 ELSE 0 END) as colonizing,
        SUM(CASE WHEN active_order_type = 'None' THEN 1 ELSE 0 END) as idle
    FROM fleet_tracking
    WHERE etac_count > 0
    GROUP BY turn
    ORDER BY turn
""", conn)

print("\n" + "="*70)
print("ETAC FLEET STATUS BY TURN (ETACs with cargo)")
print("="*70)
print(etac_status)

# Query 3: Fleet lifecycle example
example_fleet = pl.read_database("""
    SELECT
        turn,
        fleet_id,
        location_system_id,
        active_order_type,
        order_target_system_id,
        etac_count,
        ships_total
    FROM fleet_tracking
    WHERE fleet_id = (
        SELECT fleet_id
        FROM fleet_tracking
        WHERE etac_count > 0
        LIMIT 1
    )
    ORDER BY turn
    LIMIT 10
""", conn)

print("\n" + "="*70)
print("EXAMPLE FLEET LIFECYCLE (watch ETAC consumption)")
print("="*70)
print(example_fleet)

conn.close()

print("\n" + "="*70)
print("ANALYSIS SUMMARY")
print("="*70)
print("Problem: After colonization, ETAC is consumed but fleet remains empty")
print("Impact: Empty fleets waste maintenance and fleet capacity slots")
print("Solution: Engine should auto-disband empty fleets OR Eparch should salvage immediately")
