#!/usr/bin/env python3.11
"""Verify ETAC salvage behavior at 100% colonization (simple version)"""

import sqlite3
from pathlib import Path

db_path = "balance_results/diagnostics/game_42.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# 1. Find when colonization reached 100%
print("=" * 80)
print("COLONIZATION PROGRESS")
print("=" * 80)

cursor.execute("""
SELECT
    turn,
    SUM(total_colonies) as total_colonized,
    MAX(total_systems_on_map) as total_systems
FROM diagnostics
GROUP BY turn
ORDER BY turn
""")

full_colonization_turn = None
for row in cursor.fetchall():
    turn, total_colonized, total_systems = row
    if total_colonized >= total_systems:
        if full_colonization_turn is None:
            full_colonization_turn = turn
            print(f"\n✓ 100% colonization reached on turn {full_colonization_turn}")
            print(f"  Total colonized: {total_colonized}/{total_systems}")
            break

if full_colonization_turn is None:
    print("\n✗ 100% colonization never reached in this game")
    exit(0)

# 2. Track ETAC behavior around 100% colonization
print("\n" + "=" * 80)
print("ETAC FLEET BEHAVIOR")
print("=" * 80)

cursor.execute(f"""
SELECT
    turn,
    house_id,
    fleet_id,
    location_system_id,
    COALESCE(active_order_type, 'None') as active_order_type,
    COALESCE(order_target_system_id, -1) as order_target_system_id,
    ships_total,
    etac_count,
    scout_count,
    combat_ships
FROM fleet_tracking
WHERE turn >= {full_colonization_turn - 2}
  AND turn <= {min(full_colonization_turn + 10, 34)}
  AND etac_count > 0
ORDER BY house_id, fleet_id, turn
""")

print(f"\nETAC fleets from turn {full_colonization_turn - 2} to {min(full_colonization_turn + 10, 34)}:")
print(f"{'Turn':<6} {'House':<15} {'Fleet':<15} {'Loc':<6} {'Order':<12} {'Target':<7} {'Ships':<6} {'ETACs':<6}")
print("-" * 90)

etac_rows = cursor.fetchall()
for row in etac_rows:
    turn, house_id, fleet_id, loc, order, target, ships, etacs, scouts, combat = row
    target_str = str(target) if target != -1 else "-"
    print(f"{turn:<6} {house_id:<15} {fleet_id:<15} {loc:<6} {order:<12} {target_str:<7} {ships:<6} {etacs:<6}")

if not etac_rows:
    print("✗ No ETAC fleets found in this period")

# 3. Check for salvage orders
print("\n" + "=" * 80)
print("SALVAGE ORDERS ISSUED")
print("=" * 80)

cursor.execute(f"""
SELECT
    turn,
    house_id,
    fleet_id,
    location_system_id,
    etac_count,
    scout_count,
    combat_ships
FROM fleet_tracking
WHERE active_order_type = 'Salvage'
  AND turn >= {full_colonization_turn}
ORDER BY house_id, fleet_id, turn
""")

salvage_rows = cursor.fetchall()
if salvage_rows:
    print(f"\n✓ Found {len(salvage_rows)} Salvage orders:")
    print(f"{'Turn':<6} {'House':<15} {'Fleet':<15} {'Loc':<6} {'ETACs':<6} {'Scouts':<7} {'Combat':<7}")
    print("-" * 80)
    for row in salvage_rows:
        turn, house_id, fleet_id, loc, etacs, scouts, combat = row
        print(f"{turn:<6} {house_id:<15} {fleet_id:<15} {loc:<6} {etacs:<6} {scouts:<7} {combat:<7}")
else:
    print("\n✗ No Salvage orders found after 100% colonization")

# 4. Check ETAC ship counts (should decrease after salvage)
print("\n" + "=" * 80)
print("ETAC SHIP COUNT OVER TIME")
print("=" * 80)

cursor.execute(f"""
SELECT
    turn,
    SUM(etac_count) as total_etac_ships
FROM fleet_tracking
WHERE turn >= {full_colonization_turn - 2}
GROUP BY turn
ORDER BY turn
""")

print(f"\n{'Turn':<6} {'Total ETACs':<12}")
print("-" * 20)
for row in cursor.fetchall():
    turn, total_etacs = row
    marker = " ← 100% colonization" if turn == full_colonization_turn else ""
    print(f"{turn:<6} {total_etacs:<12}{marker}")

# 5. Check for cargo events
print("\n" + "=" * 80)
print("CARGO ACTIVITY (PTU levels)")
print("=" * 80)

cursor.execute(f"""
SELECT
    d.turn,
    d.house_id,
    d.colonist_cargo
FROM diagnostics d
WHERE d.turn >= {full_colonization_turn - 2}
  AND d.turn <= {min(full_colonization_turn + 5, 34)}
ORDER BY d.turn, d.house_id
""")

print(f"\n{'Turn':<6} {'House':<15} {'PTU Cargo':<10}")
print("-" * 40)
for row in cursor.fetchall():
    turn, house_id, ptu = row
    marker = " ← 100% colonization" if turn == full_colonization_turn else ""
    print(f"{turn:<6} {house_id:<15} {ptu:<10}{marker}")

conn.close()

print("\n" + "=" * 80)
print("VERIFICATION COMPLETE")
print("=" * 80)
