#!/usr/bin/env python3
"""Debug maintenance cost discrepancy"""

import csv

# Load game data
rows = []
with open("balance_results/diagnostics/game_99999.csv", "r") as f:
    reader = csv.DictReader(f)
    for row in reader:
        if row["turn"] == "10":
            rows.append(row)

print("=" * 80)
print("TURN 10 MAINTENANCE BREAKDOWN")
print("=" * 80)

for row in rows:
    house = row["house"]
    treasury = int(row["treasury"])
    maintenance = int(row["maintenance_cost"])
    total_ships = int(row["total_ships"])

    print(f"\n{house}:")
    print(f"  Treasury: {treasury:,} PP")
    print(f"  Maintenance: {maintenance:,} PP")
    print(f"  TotalShips: {total_ships}")

    # Calculate expected colony maintenance
    spaceports = int(row.get("total_spaceports", 0))
    shipyards = int(row.get("total_shipyards", 0))
    starbases = int(row.get("starbases_actual", 0))
    batteries = int(row.get("ground_battery_units", 0))
    armies = int(row.get("army_units", 0))
    marines = int(row.get("marine_division_units", 0))
    shields = int(row.get("planetary_shield_units", 0))

    colony_maint = (
        spaceports * 5 +
        shipyards * 5 +
        starbases * 15 +
        batteries * 1 +
        armies * 1 +
        marines * 1 +
        shields * 5
    )

    # Estimate fleet maintenance (assume avg ~4 PP per ship)
    estimated_fleet_maint = total_ships * 4

    total_expected = colony_maint + estimated_fleet_maint

    print(f"\n  Expected Colony Maintenance:")
    print(f"    Spaceports:  {spaceports:2} × 5  = {spaceports * 5:3} PP")
    print(f"    Shipyards:   {shipyards:2} × 5  = {shipyards * 5:3} PP")
    print(f"    Starbases:   {starbases:2} × 15 = {starbases * 15:3} PP")
    print(f"    Batteries:   {batteries:2} × 1  = {batteries * 1:3} PP")
    print(f"    Armies:      {armies:2} × 1  = {armies * 1:3} PP")
    print(f"    Marines:     {marines:2} × 1  = {marines * 1:3} PP")
    print(f"    Shields:     {shields:2} × 5  = {shields * 5:3} PP")
    print(f"    Colony Total:              {colony_maint:4} PP")

    print(f"\n  Estimated Fleet Maintenance:")
    print(f"    TotalShips:  {total_ships:2} × 4  = {estimated_fleet_maint:3} PP (estimated avg)")

    print(f"\n  Expected Total:  {total_expected:4} PP")
    print(f"  Actual Total:    {maintenance:4} PP")
    if total_expected > 0:
        print(f"  Discrepancy:     {maintenance - total_expected:4} PP ({maintenance / total_expected:.1f}x)")

    # Calculate implied per-ship cost
    if total_ships > 0:
        implied_fleet_cost = maintenance - colony_maint
        implied_per_ship = implied_fleet_cost / total_ships
        print(f"  Implied per-ship: {implied_per_ship:.1f} PP (fleet maint {implied_fleet_cost} / {total_ships} ships)")

print("\n" + "=" * 80)
