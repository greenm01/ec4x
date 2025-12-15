#!/usr/bin/env python3.11
"""Verify ETAC salvage behavior at 100% colonization"""

import polars as pl
import sqlite3
from pathlib import Path

db_path = "balance_results/diagnostics/game_42.db"
conn = sqlite3.connect(db_path)

# 1. Find when colonization reached 100%
print("=" * 80)
print("COLONIZATION PROGRESS")
print("=" * 80)

colonization_query = """
SELECT
    turn,
    SUM(total_colonies) as total_colonized,
    MAX(total_systems_on_map) as total_systems
FROM diagnostics
GROUP BY turn
ORDER BY turn
"""

colonization_df = pl.read_database(colonization_query, conn)
print(colonization_df)

# Find the turn where 100% was reached
full_colonization_turn = None
for row in colonization_df.iter_rows(named=True):
    if row['total_colonized'] >= row['total_systems']:
        full_colonization_turn = row['turn']
        print(f"\n✓ 100% colonization reached on turn {full_colonization_turn}")
        print(f"  Total colonized: {row['total_colonized']}/{row['total_systems']}")
        break

if full_colonization_turn is None:
    print("\n✗ 100% colonization never reached in this game")
    exit(0)

# 2. Track ETAC behavior around 100% colonization
print("\n" + "=" * 80)
print("ETAC FLEET BEHAVIOR")
print("=" * 80)

etac_query = f"""
SELECT
    turn,
    house_id,
    fleet_id,
    location_system_id,
    active_order_type,
    order_target_system_id,
    ships_total,
    etac_count,
    scout_count,
    combat_ships
FROM fleet_tracking
WHERE turn >= {full_colonization_turn - 2}
  AND turn <= {min(full_colonization_turn + 5, 34)}
  AND etac_count > 0
ORDER BY house_id, fleet_id, turn
"""

etac_df = pl.read_database(etac_query, conn)
print(f"\nETAC fleets around turn {full_colonization_turn}:")
print(etac_df)

# 3. Check for salvage orders
print("\n" + "=" * 80)
print("SALVAGE ORDERS ISSUED")
print("=" * 80)

salvage_query = f"""
SELECT
    turn,
    house_id,
    fleet_id,
    location_system_id,
    active_order_type,
    etac_count,
    scout_count,
    combat_ships
FROM fleet_tracking
WHERE active_order_type = 'Salvage'
ORDER BY house_id, fleet_id, turn
"""

salvage_df = pl.read_database(salvage_query, conn)
if len(salvage_df) > 0:
    print(f"\n✓ Found {len(salvage_df)} Salvage orders:")
    print(salvage_df)
else:
    print("\n✗ No Salvage orders found in database")

# 4. Check ETAC ship counts (should decrease after salvage)
print("\n" + "=" * 80)
print("ETAC SHIP COUNT OVER TIME")
print("=" * 80)

etac_count_query = f"""
SELECT
    turn,
    SUM(etac_count) as total_etac_ships
FROM fleet_tracking
WHERE turn >= {full_colonization_turn - 2}
GROUP BY turn
ORDER BY turn
"""

etac_count_df = pl.read_database(etac_count_query, conn)
print(etac_count_df)

# 5. Check for unload cargo events in diagnostics
print("\n" + "=" * 80)
print("CARGO UNLOAD ACTIVITY")
print("=" * 80)

# Check PTU cargo levels around 100% colonization
ptu_query = f"""
SELECT
    d.turn,
    d.house_id,
    d.colonist_cargo
FROM diagnostics d
WHERE d.turn >= {full_colonization_turn - 2}
  AND d.turn <= {min(full_colonization_turn + 3, 34)}
ORDER BY d.house_id, d.turn
"""

ptu_df = pl.read_database(ptu_query, conn)
print(f"\nPTU cargo levels (should drop to 0 after unload):")
print(ptu_df)

conn.close()

print("\n" + "=" * 80)
print("VERIFICATION COMPLETE")
print("=" * 80)
