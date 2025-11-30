#!/usr/bin/env python3
"""Analyze unit costs vs combat power from official specs"""

# From docs/specs/reference.md
official_units = {
    # Ships: Class, PC, AS, DS
    "CT": {"name": "Corvette", "pc": 20, "as": 2, "ds": 3},
    "FG": {"name": "Frigate", "pc": 30, "as": 3, "ds": 4},
    "DD": {"name": "Destroyer", "pc": 40, "as": 5, "ds": 6},
    "CL": {"name": "Light Cruiser", "pc": 60, "as": 8, "ds": 9},
    "CA": {"name": "Heavy Cruiser", "pc": 80, "as": 12, "ds": 13},
    "BC": {"name": "Battle Cruiser", "pc": 100, "as": 16, "ds": 18},
    "BB": {"name": "Battleship", "pc": 150, "as": 20, "ds": 25},
    "DN": {"name": "Dreadnought", "pc": 200, "as": 28, "ds": 30},
    "SD": {"name": "Super Dreadnought", "pc": 250, "as": 35, "ds": 40},
    "PB": {"name": "Planet-Breaker", "pc": 400, "as": 50, "ds": 20},
    "CV": {"name": "Carrier", "pc": 120, "as": 5, "ds": 18},
    "CX": {"name": "Super Carrier", "pc": 200, "as": 8, "ds": 25},
    "FS": {"name": "Fighter Squadron", "pc": 20, "as": 4, "ds": 3},
    "RR": {"name": "Raider", "pc": 150, "as": 12, "ds": 10},
    "SC": {"name": "Scout", "pc": 50, "as": 1, "ds": 2},
    "SB": {"name": "Starbase", "pc": 300, "as": 45, "ds": 50},
}

print("=" * 80)
print("UNIT COST/POWER ANALYSIS (Official Specs)")
print("=" * 80)
print()
print(f"{'Class':<4} {'Name':<20} {'PC':>5} {'AS':>4} {'DS':>4} {'Total':>5} {'PP/Pwr':>7}")
print("-" * 80)

for cls, data in official_units.items():
    total_power = data["as"] + data["ds"]
    pp_per_power = data["pc"] / total_power if total_power > 0 else 0
    print(f"{cls:<4} {data['name']:<20} {data['pc']:>5} {data['as']:>4} {data['ds']:>4} {total_power:>5} {pp_per_power:>7.2f}")

print()
print("=" * 80)
print("EFFICIENCY ANALYSIS")
print("=" * 80)
print()

# Group by PP/Power ratio
units_by_efficiency = sorted(official_units.items(),
                             key=lambda x: x[1]["pc"] / (x[1]["as"] + x[1]["ds"]))

print("Most Efficient (lowest PP per power point):")
for cls, data in units_by_efficiency[:5]:
    total_power = data["as"] + data["ds"]
    pp_per_power = data["pc"] / total_power
    print(f"  {cls:<4} {data['name']:<20} {pp_per_power:>6.2f} PP/pwr ({data['pc']}PP / {total_power}pwr)")

print()
print("Least Efficient (highest PP per power point):")
for cls, data in units_by_efficiency[-5:]:
    total_power = data["as"] + data["ds"]
    pp_per_power = data["pc"] / total_power
    print(f"  {cls:<4} {data['name']:<20} {pp_per_power:>6.2f} PP/pwr ({data['pc']}PP / {total_power}pwr)")

print()
print("=" * 80)
print("CARRIER ANALYSIS")
print("=" * 80)
print()

cv_cost = 120
cx_cost = 200
fs_cost = 20

print(f"CV (Carrier): {cv_cost}PP = {cv_cost // fs_cost}x Fighter cost")
print(f"CX (Super Carrier): {cx_cost}PP = {cx_cost // fs_cost}x Fighter cost")
print()
print("Proposed change: CV 120PP → 80PP")
print(f"  80PP = {80 // fs_cost}x Fighter cost (more balanced)")
print(f"  Creates strategic choice: 1 carrier OR 4 fighters")
