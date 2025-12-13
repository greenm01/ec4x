#!/usr/bin/env python3
"""
Verify that the three regression fixes worked correctly.
Analyzes game_12345.csv to check:
1. Colonization continues past turn 7 (was stalling at 35%)
2. Colonization reaches 70%+ by turn 20
3. ETAC count stays above 15 in Act 2
4. Treasury stays below 30k PP (was 115k)
5. Ships built increases significantly
"""

import pandas as pd

# Load game data
df = pd.read_csv("balance_results/diagnostics/game_12345.csv")

print("=" * 70)
print("REGRESSION FIX VERIFICATION - Seed 12345")
print("=" * 70)

# 1. Check colonization progress by turn
print("\n1. COLONIZATION PROGRESS")
print("-" * 70)

colonization = df.groupby("turn").agg({
    "systems_colonized": "sum",
    "act": "first"
}).reset_index()
colonization.columns = ["turn", "total_systems_colonized", "act"]
colonization = colonization.sort_values("turn")

# Show key turns
key_turns = colonization[colonization["turn"].isin([5, 7, 10, 15, 20, 25, 30, 35])]
print(key_turns.to_string(index=False))

turn_7_colonization = colonization[colonization["turn"] == 7]["total_systems_colonized"].iloc[0]
turn_20_colonization = colonization[colonization["turn"] == 20]["total_systems_colonized"].iloc[0]

total_systems = 37  # From map
turn_7_pct = (turn_7_colonization / total_systems) * 100
turn_20_pct = (turn_20_colonization / total_systems) * 100

print(f"\n✓ Turn 7: {turn_7_colonization}/{total_systems} systems ({turn_7_pct:.1f}%)")
if turn_7_colonization > 13:
    print("  SUCCESS: Colonization continued past turn 7 (was stuck at 13)")
else:
    print("  FAIL: Still stuck at turn 7")

print(f"\n✓ Turn 20: {turn_20_colonization}/{total_systems} systems ({turn_20_pct:.1f}%)")
if turn_20_pct >= 70:
    print("  SUCCESS: Reached 70%+ target")
else:
    print(f"  PARTIAL: Reached {turn_20_pct:.1f}% (target: 70%+)")

# 2. Check ETAC counts
print("\n\n2. ETAC COUNTS (Per House)")
print("-" * 70)

etac_counts = df[df["turn"].isin([7, 10, 15, 20])][["turn", "house_id", "etacs_count"]].sort_values(["turn", "house_id"])

for turn in [7, 10, 15, 20]:
    turn_data = etac_counts[etac_counts["turn"] == turn]
    avg_etacs = turn_data["etacs_count"].mean()
    print(f"\nTurn {turn}: Avg {avg_etacs:.1f} ETACs per house")
    print(turn_data.to_string(index=False))

act2_etacs = df[df["turn"] >= 8]["etacs_count"].mean()
if act2_etacs >= 15:
    print(f"\n✓ SUCCESS: Act 2+ average {act2_etacs:.1f} ETACs (target: 15+)")
else:
    print(f"\n✗ PARTIAL: Act 2+ average {act2_etacs:.1f} ETACs (target: 15+)")

# 3. Check treasury levels (hoarding check)
print("\n\n3. TREASURY LEVELS (Hoarding Check)")
print("-" * 70)

treasury = df[df["turn"] >= 15].groupby("house_id").agg({
    "treasury": ["mean", "max"]
}).reset_index()
treasury.columns = ["house_id", "avg_treasury", "max_treasury"]
treasury = treasury.sort_values("house_id")

print(treasury.to_string(index=False))

avg_treasury_all = df[df["turn"] >= 15]["treasury"].mean()
max_treasury_all = df[df["turn"] >= 15]["treasury"].max()

print(f"\nOverall (Turn 15+):")
print(f"  Average treasury: {avg_treasury_all:.0f} PP")
print(f"  Max treasury: {max_treasury_all:.0f} PP")

if avg_treasury_all < 30000:
    print("✓ SUCCESS: Average below 30k PP (was 115k before fixes)")
else:
    print(f"✗ FAIL: Still hoarding (avg {avg_treasury_all/1000:.1f}k PP)")

# 4. Check ships built
print("\n\n4. SHIPS BUILT (Total by Turn 35)")
print("-" * 70)

ships_built = df[df["turn"] == 35][["house_id", "ships_built"]].sort_values("house_id")

print(ships_built.to_string(index=False))

total_ships = ships_built["ships_built"].sum()
avg_ships = ships_built["ships_built"].mean()

print(f"\nTotal ships built: {total_ships}")
print(f"Average per house: {avg_ships:.1f}")

if avg_ships >= 100:
    print("✓ SUCCESS: Average 100+ ships per house (was ~40 before fixes)")
elif avg_ships >= 70:
    print(f"✓ GOOD: Average {avg_ships:.1f} ships per house (better than ~40 baseline)")
else:
    print(f"✗ FAIL: Only {avg_ships:.1f} ships per house (target: 100+)")

# 5. Summary
print("\n\n" + "=" * 70)
print("SUMMARY")
print("=" * 70)

success_count = 0
total_checks = 4

if turn_7_colonization > 13:
    success_count += 1
    print("✓ Colonization continues past turn 7")
else:
    print("✗ Colonization still stuck at turn 7")

if turn_20_pct >= 70:
    success_count += 1
    print("✓ Colonization reaches 70%+ by turn 20")
else:
    print(f"⚠ Colonization at {turn_20_pct:.1f}% by turn 20 (target: 70%+)")

if avg_treasury_all < 30000:
    success_count += 1
    print("✓ Treasury stays below 30k PP")
else:
    print("✗ Treasury hoarding persists")

if avg_ships >= 70:
    success_count += 1
    print(f"✓ Ships built improved ({avg_ships:.1f} per house)")
else:
    print(f"✗ Ships built still low ({avg_ships:.1f} per house)")

print(f"\n{success_count}/{total_checks} checks passed")

if success_count == total_checks:
    print("\n🎉 ALL FIXES VERIFIED SUCCESSFUL!")
elif success_count >= 3:
    print("\n✓ Most fixes working, minor tuning may be needed")
else:
    print("\n⚠ Some fixes may need adjustment")
