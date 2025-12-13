#!/usr/bin/env python3
"""
Check colonization progress and Act transitions from simulation CSV (no dependencies)
"""

import csv
import sys
from collections import defaultdict

# Get seed from command line argument
if len(sys.argv) < 2:
    print("Usage: python3 check_colonization_simple.py <seed>")
    print("Example: python3 check_colonization_simple.py 99999")
    sys.exit(1)

seed = sys.argv[1]
csv_path = f"balance_results/diagnostics/game_{seed}.csv"

print(f"Analyzing game with seed: {seed}")
print()

# Load the game CSV
data = []
try:
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append(row)
except FileNotFoundError:
    print(f"Error: Could not find {csv_path}")
    print(f"Make sure you've run: ./bin/run_simulation -s {seed}")
    sys.exit(1)

# Group by turn
turns = defaultdict(lambda: {'colonies': 0, 'etacs': 0, 'treasury': 0, 'act': '', 'houses': []})

for row in data:
    turn = int(row['turn'])
    turns[turn]['colonies'] += int(row['total_colonies'])
    turns[turn]['etacs'] += int(row['etac_ships'])
    turns[turn]['treasury'] += int(row['treasury'])
    turns[turn]['act'] = row['act']
    turns[turn]['houses'].append({
        'house': row['house'],
        'colonies': int(row['total_colonies']),
        'etacs': int(row['etac_ships']),
        'treasury': int(row['treasury'])
    })

print("=" * 80)
print("COLONIZATION PROGRESS BY TURN")
print("=" * 80)

for turn in sorted(turns.keys()):
    t = turns[turn]
    print(f"Turn {turn:2d}: {t['colonies']:2d}/37 systems colonized | "
          f"{t['etacs']:2d} ETACs active | Treasury: {t['treasury']:6d} PP | Act: {t['act']}")

print()
print("=" * 80)
print("PER-HOUSE COLONIZATION (Final Turn)")
print("=" * 80)

final_turn = max(turns.keys())
for house_data in turns[final_turn]['houses']:
    print(f"{house_data['house']:20s}: {house_data['colonies']} colonies | "
          f"{house_data['etacs']} ETACs | {house_data['treasury']:6d} PP")

print()
print("=" * 80)
print("ETAC PRODUCTION SUMMARY")
print("=" * 80)
print("Turn | Total ETACs | Max per House")
print("-----|-------------|---------------")

for turn in sorted(turns.keys()):
    total = turns[turn]['etacs']
    max_per_house = max([h['etacs'] for h in turns[turn]['houses']])
    print(f" {turn:2d}  |     {total:2d}      |      {max_per_house:2d}")

print()
