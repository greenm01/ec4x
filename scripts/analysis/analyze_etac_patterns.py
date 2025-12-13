#!/usr/bin/env python3
"""
Analyze ETAC colonization patterns to diagnose low colonization rate.

Checks:
1. Are ETACs being destroyed? (combat losses)
2. Are ETACs colonizing nearby systems or traveling too far?
3. Are AutoColonize standing orders working?

Usage:
  python3 scripts/analysis/analyze_etac_patterns.py --seed 99999
"""

import csv
import argparse
from collections import defaultdict

# Parse arguments
parser = argparse.ArgumentParser(description='Analyze ETAC colonization patterns')
parser.add_argument('--seed', type=int, default=99999, help='Game seed to analyze')
args = parser.parse_args()

csv_file = f"balance_results/diagnostics/game_{args.seed}.csv"

# Load game data
try:
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
except FileNotFoundError:
    print(f"ERROR: File not found: {csv_file}")
    print("Make sure you've run: ./bin/run_simulation -s {args.seed} -t 15")
    exit(1)

print("=" * 80)
print(f"ETAC COLONIZATION PATTERN ANALYSIS - Game {args.seed}")
print("=" * 80)

print("\n=== ETAC Status by House (Turns 1-15) ===\n")

houses = {}
for row in rows:
    turn = int(row['turn'])
    house = row['house']

    if house not in houses:
        houses[house] = []

    houses[house].append({
        'turn': turn,
        'etacs': int(row['etac_ships']),
        'ships_lost': int(row['ships_lost']),
        'colonies': int(row['total_colonies']),
        'colonized': int(row['colonies_gained_via_colonization']),
        'total_ships': int(row['total_ships'])
    })

for house in sorted(houses.keys()):
    print(f"\n{house}:")
    data = houses[house]

    for d in data[:30]:  # First 15 turns
        colonized_this_turn = d['colonized']
        marker = " ← COLONIZED!" if colonized_this_turn > 0 else ""
        print(f"  Turn {d['turn']:2d}: {d['etacs']} ETACs, "
              f"{d['colonies']} colonies (+{colonized_this_turn}), "
              f"{d['ships_lost']} ships lost, "
              f"{d['total_ships']} total ships{marker}")

print("\n\n=== Summary Statistics (Turn 15) ===\n")
for house in sorted(houses.keys()):
    data = houses[house]
    final = data[29] if len(data) > 29 else data[-1]  # Turn 15 or last turn

    total_colonized = sum(d['colonized'] for d in data[:30])
    total_etac_losses = 0  # Calculate ETAC-specific losses if possible

    print(f"{house}:")
    print(f"  Final ETACs: {final['etacs']}")
    print(f"  Total colonies: {final['colonies']}")
    print(f"  Systems colonized: {total_colonized}")
    print(f"  Total ship losses: {final['ships_lost']}")
    print(f"  Colonization rate: {total_colonized / 30:.2f} systems/turn")

total_systems = int(rows[0]['total_systems_on_map'])
total_colonized = sum(houses[h][29]['colonies'] if len(houses[h]) > 29 else houses[h][-1]['colonies']
                     for h in houses.keys())
uncolonized = total_systems - total_colonized

print(f"\n=== Map Status (Turn 15) ===")
print(f"Total systems: {total_systems}")
print(f"Colonized: {total_colonized}")
print(f"Uncolonized: {uncolonized} ({uncolonized/total_systems*100:.1f}%)")

print("\n" + "=" * 80)
print("\n⚠️  DIAGNOSIS:")
if uncolonized > 25:
    print("  - CRITICAL: Very low colonization rate!")
    print("  - ETACs exist but aren't colonizing effectively")
    print("  - Likely issues:")
    print("    1. AutoColonize not activating (empty ETACs not reloading)")
    print("    2. ETACs traveling too far (getting destroyed)")
    print("    3. Target selection too aggressive (distant systems)")
print("\n" + "=" * 80)
