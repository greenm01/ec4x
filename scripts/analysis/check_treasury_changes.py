#!/usr/bin/env python3
"""Check if treasuries are decreasing (maintenance being charged)"""

import csv

# Load game data
rows = []
with open("balance_results/diagnostics/game_99999.csv", "r") as f:
    reader = csv.DictReader(f)
    for row in reader:
        turn = int(row["turn"])
        if turn >= 1 and turn <= 15:
            rows.append(row)

# Group by house
houses = {}
for row in rows:
    house = row["house"]
    if house not in houses:
        houses[house] = []
    houses[house].append(row)

print("=" * 80)
print("TREASURY CHANGES (Looking for maintenance deductions)")
print("=" * 80)

for house, data in sorted(houses.items()):
    print(f"\n{house}:")
    print(f"  Turn | Treasury | Production | Change | Expected Change (Prod - Maint)")
    print(f"  -----|----------|------------|--------|--------------------------------")

    for i, row in enumerate(data):
        turn = int(row["turn"])
        treasury = int(row["treasury"])
        production = int(row["production"])

        if i > 0:
            prev_treasury = int(data[i-1]["treasury"])
            change = treasury - prev_treasury

            # Expected change = production income (we don't know maintenance)
            # But we can see if treasury is going down despite production
            print(f"  {turn:4} | {treasury:8} | {production:10} | {change:6} | ???")
        else:
            print(f"  {turn:4} | {treasury:8} | {production:10} |      - | (start)")

print("\n" + "=" * 80)
print("If maintenance is being charged, treasury changes should be:")
print("  new_treasury = old_treasury + production - maintenance - construction")
print("If all changes equal production, maintenance might not be charging!")
print("=" * 80)
