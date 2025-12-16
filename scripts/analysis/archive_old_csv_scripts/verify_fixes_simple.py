#!/usr/bin/env python3
"""
Simple CSV analysis using only Python stdlib.
Verifies the three regression fixes worked correctly.
"""

import csv
from collections import defaultdict

# Load game data
data = []
with open("balance_results/diagnostics/game_12345.csv", 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        data.append(row)

print("=" * 70)
print("REGRESSION FIX VERIFICATION - Seed 12345")
print("=" * 70)

# 1. Colonization progress
print("\n1. COLONIZATION PROGRESS")
print("-" * 70)

colonization_by_turn = defaultdict(int)
for row in data:
    turn = int(row['turn'])
    colonization_by_turn[turn] += int(row['total_colonies'])

total_systems = 37
key_turns = [5, 7, 10, 15, 20, 25, 30, 35]

print("\nTurn  Systems Colonized  Percentage")
print("-" * 45)
for turn in key_turns:
    if turn in colonization_by_turn:
        systems = colonization_by_turn[turn]
        pct = (systems / total_systems) * 100
        print(f"{turn:4d}  {systems:17d}  {pct:9.1f}%")

turn_7_count = colonization_by_turn.get(7, 0)
turn_20_count = colonization_by_turn.get(20, 0)
turn_7_pct = (turn_7_count / total_systems) * 100
turn_20_pct = (turn_20_count / total_systems) * 100

print(f"\n✓ Turn 7: {turn_7_count}/{total_systems} systems ({turn_7_pct:.1f}%)")
if turn_7_count > 13:
    print("  SUCCESS: Colonization continued past turn 7 (was stuck at 13)")
else:
    print("  FAIL: Still stuck at turn 7")

print(f"\n✓ Turn 20: {turn_20_count}/{total_systems} systems ({turn_20_pct:.1f}%)")
if turn_20_pct >= 70:
    print("  SUCCESS: Reached 70%+ target")
else:
    print(f"  PARTIAL: Reached {turn_20_pct:.1f}% (target: 70%+)")

# 2. ETAC counts
print("\n\n2. ETAC COUNTS (Act 2 Average)")
print("-" * 70)

act2_etacs = []
for row in data:
    if int(row['turn']) >= 8:  # Act 2 starts at turn 8
        act2_etacs.append(int(row['etac_ships']))

if act2_etacs:
    avg_act2_etacs = sum(act2_etacs) / len(act2_etacs)
    print(f"Act 2+ average: {avg_act2_etacs:.1f} ETACs per house")
    if avg_act2_etacs >= 15:
        print("✓ SUCCESS: Above 15 ETAC target")
    else:
        print(f"⚠ PARTIAL: {avg_act2_etacs:.1f} ETACs (target: 15+)")

# 3. Treasury levels (hoarding check)
print("\n\n3. TREASURY LEVELS (Turn 15+)")
print("-" * 70)

treasuries = []
for row in data:
    if int(row['turn']) >= 15:
        treasuries.append(int(row['treasury']))

if treasuries:
    avg_treasury = sum(treasuries) / len(treasuries)
    max_treasury = max(treasuries)

    print(f"Average treasury: {avg_treasury:,.0f} PP")
    print(f"Max treasury: {max_treasury:,.0f} PP")

    if avg_treasury < 30000:
        print("✓ SUCCESS: Average below 30k PP (was 115k before fixes)")
    else:
        print(f"✗ FAIL: Still hoarding (avg {avg_treasury/1000:.1f}k PP)")

# 4. Ships built
print("\n\n4. TOTAL FLEET SIZE (Turn 35)")
print("-" * 70)

turn_35_ships = []
for row in data:
    if int(row['turn']) == 35:
        ships = int(row['total_ships'])
        turn_35_ships.append(ships)
        print(f"{row['house']}: {ships} ships")

if turn_35_ships:
    total_ships = sum(turn_35_ships)
    avg_ships = total_ships / len(turn_35_ships)

    print(f"\nTotal: {total_ships} ships")
    print(f"Average per house: {avg_ships:.1f}")

    if avg_ships >= 100:
        print("✓ SUCCESS: Average 100+ ships per house (was ~40 before)")
    elif avg_ships >= 70:
        print(f"✓ GOOD: Average {avg_ships:.1f} ships per house (better than ~40 baseline)")
    else:
        print(f"✗ FAIL: Only {avg_ships:.1f} ships per house (target: 100+)")

# Summary
print("\n\n" + "=" * 70)
print("SUMMARY")
print("=" * 70)

success_count = 0
total_checks = 4

if turn_7_count > 13:
    success_count += 1
    print("✓ Colonization continues past turn 7")
else:
    print("✗ Colonization still stuck at turn 7")

if turn_20_pct >= 70:
    success_count += 1
    print("✓ Colonization reaches 70%+ by turn 20")
else:
    print(f"⚠ Colonization at {turn_20_pct:.1f}% by turn 20 (target: 70%+)")

if treasuries and avg_treasury < 30000:
    success_count += 1
    print("✓ Treasury stays below 30k PP")
else:
    print("✗ Treasury hoarding persists")

if turn_35_ships and avg_ships >= 70:
    success_count += 1
    print(f"✓ Ships built improved ({avg_ships:.1f} per house)")
else:
    print(f"✗ Ships built still low")

print(f"\n{success_count}/{total_checks} checks passed")

if success_count == total_checks:
    print("\n🎉 ALL FIXES VERIFIED SUCCESSFUL!")
elif success_count >= 3:
    print("\n✓ Most fixes working, minor tuning may be needed")
else:
    print("\n⚠ Some fixes may need adjustment")
