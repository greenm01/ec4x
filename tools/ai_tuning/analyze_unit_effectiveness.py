#!/usr/bin/env python3
"""
Comprehensive unit cost effectiveness analysis from diagnostic CSV files.
Analyzes which units are being built, their frequency, and correlation with success.
"""

import csv
import sys
from pathlib import Path
from collections import defaultdict
from statistics import mean, stdev

# Unit costs from config/ships.toml and other configs
UNIT_COSTS = {
    # Ships
    'fighter_ships': 20,
    'corvette_ships': 20,
    'frigate_ships': 30,
    'destroyer_ships': 40,
    'light_cruiser_ships': 60,
    'heavy_cruiser_ships': 80,
    'battlecruiser_ships': 100,
    'battleship_ships': 150,
    'dreadnought_ships': 200,
    'super_dreadnought_ships': 250,
    'carrier_ships': 80,  # After balance fix
    'super_carrier_ships': 200,
    'scout_ships': 50,
    'raider_ships': 150,
    'starbase_ships': 300,
    'etac_ships': 25,
    'troop_transport_ships': 25,
    'planet_breaker_ships': 400,

    # Ground units
    'planetary_shield_units': 500,
    'ground_battery_units': 100,
    'army_units': 15,
    'marine_division_units': 30,
}

# Official power ratings (AS + DS from reference.md)
UNIT_POWER = {
    'fighter_ships': 7,   # 4 AS + 3 DS
    'corvette_ships': 5,  # 2 AS + 3 DS
    'frigate_ships': 7,   # 3 AS + 4 DS
    'destroyer_ships': 11, # 5 AS + 6 DS
    'light_cruiser_ships': 17,  # 8 AS + 9 DS
    'heavy_cruiser_ships': 25,  # 12 AS + 13 DS
    'battlecruiser_ships': 34,  # 16 AS + 18 DS
    'battleship_ships': 45,     # 20 AS + 25 DS
    'dreadnought_ships': 58,    # 28 AS + 30 DS
    'super_dreadnought_ships': 75,  # 35 AS + 40 DS
    'carrier_ships': 23,  # 5 AS + 18 DS
    'super_carrier_ships': 33,  # 8 AS + 25 DS
    'scout_ships': 3,     # 1 AS + 2 DS
    'raider_ships': 22,   # 12 AS + 10 DS
    'starbase_ships': 95, # 45 AS + 50 DS
}

def analyze_unit_effectiveness():
    """Analyze unit building patterns and effectiveness."""
    diag_dir = Path("balance_results/diagnostics")
    csv_files = list(diag_dir.glob("*.csv"))

    if not csv_files:
        print("❌ No diagnostic CSV files found!")
        sys.exit(1)

    print(f"📊 Analyzing unit effectiveness from {len(csv_files)} games...")
    print()

    # Collect data by strategy
    strategy_data = defaultdict(lambda: {
        'games': 0,
        'wins': 0,
        'prestige': [],
        'unit_counts': defaultdict(list),
        'winner_units': defaultdict(list),
        'loser_units': defaultdict(list),
    })

    # Process each game file
    for csv_file in csv_files:
        with open(csv_file, 'r') as f:
            reader = csv.DictReader(f)
            game_data = list(reader)

            if not game_data:
                continue

            # Get final turn data
            final_turn = max(game_data, key=lambda x: int(x.get('turn', 0)))
            turn_num = int(final_turn['turn'])

            # Process each house in the final turn
            houses_final = [row for row in game_data if int(row['turn']) == turn_num]

            # Find winner (highest prestige)
            winner = max(houses_final, key=lambda x: float(x.get('prestige', 0)))
            winner_house = winner['house']

            for row in houses_final:
                strategy = row['strategy']
                is_winner = (row['house'] == winner_house)

                data = strategy_data[strategy]
                data['games'] += 1
                data['prestige'].append(float(row.get('prestige', 0)))

                if is_winner:
                    data['wins'] += 1

                # Collect unit counts
                for unit_type in UNIT_COSTS.keys():
                    count = int(row.get(unit_type, 0))
                    data['unit_counts'][unit_type].append(count)

                    if is_winner:
                        data['winner_units'][unit_type].append(count)
                    else:
                        data['loser_units'][unit_type].append(count)

    # Print results
    print("=" * 120)
    print("UNIT EFFECTIVENESS ANALYSIS")
    print("=" * 120)
    print()

    # Calculate PP/power efficiency for each unit
    print("💰 UNIT COST EFFICIENCY (PP per Power Point)")
    print("-" * 120)
    print(f"{'Unit':<30} {'Cost (PP)':>12} {'Power':>8} {'PP/Pwr':>10} {'Efficiency Rank':>16}")
    print("-" * 120)

    combat_units = [(unit, UNIT_COSTS[unit], UNIT_POWER.get(unit, 0))
                    for unit in UNIT_COSTS.keys() if unit in UNIT_POWER]
    combat_units.sort(key=lambda x: x[1] / x[2] if x[2] > 0 else 999)

    for unit, cost, power in combat_units:
        if power > 0:
            efficiency = cost / power
            rank = "⭐ BEST" if efficiency < 3.0 else "✓ Good" if efficiency < 4.0 else "- Average"
            unit_name = unit.replace('_ships', '').replace('_', ' ').title()
            print(f"{unit_name:<30} {cost:>12} {power:>8} {efficiency:>10.2f} {rank:>16}")

    print()
    print("⚔️  UNIT BUILDING PATTERNS BY STRATEGY")
    print("-" * 120)

    # Sort strategies by win rate
    strategies = sorted(strategy_data.keys(),
                       key=lambda s: (strategy_data[s]['wins'] / strategy_data[s]['games'])
                       if strategy_data[s]['games'] > 0 else 0,
                       reverse=True)

    # For each strategy, show most-built units
    for strategy in strategies:
        data = strategy_data[strategy]
        if data['games'] == 0:
            continue

        win_rate = (data['wins'] / data['games'] * 100) if data['games'] > 0 else 0
        avg_prestige = mean(data['prestige']) if data['prestige'] else 0

        print(f"\n{strategy} Strategy (Win Rate: {win_rate:.1f}%, Avg Prestige: {avg_prestige:.0f})")
        print("-" * 120)

        # Calculate average units built
        unit_avgs = []
        for unit_type, counts in data['unit_counts'].items():
            if counts:
                avg_count = mean(counts)
                if avg_count > 0.1:  # Only show units that are actually built
                    total_cost = avg_count * UNIT_COSTS[unit_type]
                    unit_name = unit_type.replace('_ships', '').replace('_units', '').replace('_', ' ').title()
                    unit_avgs.append((unit_name, avg_count, UNIT_COSTS[unit_type], total_cost))

        # Sort by total PP invested
        unit_avgs.sort(key=lambda x: x[3], reverse=True)

        print(f"{'Unit':<30} {'Avg Count':>12} {'Unit Cost':>12} {'Total PP':>12}")
        print("-" * 120)
        for unit_name, avg_count, unit_cost, total_cost in unit_avgs[:15]:  # Top 15 units
            print(f"{unit_name:<30} {avg_count:>12.1f} {unit_cost:>12} {total_cost:>12.0f}")

    print()
    print("🏆 WINNER vs LOSER UNIT COMPOSITION")
    print("-" * 120)

    # Compare winners vs losers for key units
    key_units = ['fighter_ships', 'light_cruiser_ships', 'heavy_cruiser_ships', 'battlecruiser_ships',
                 'battleship_ships', 'carrier_ships', 'starbase_ships', 'scout_ships']

    print(f"{'Unit':<30} {'Winners Avg':>15} {'Losers Avg':>15} {'Difference':>15} {'Winner Advantage':>18}")
    print("-" * 120)

    for unit_type in key_units:
        winner_counts = []
        loser_counts = []

        for strategy in strategies:
            data = strategy_data[strategy]
            winner_counts.extend(data['winner_units'][unit_type])
            loser_counts.extend(data['loser_units'][unit_type])

        if winner_counts and loser_counts:
            winner_avg = mean(winner_counts)
            loser_avg = mean(loser_counts)
            diff = winner_avg - loser_avg
            advantage = ((winner_avg - loser_avg) / loser_avg * 100) if loser_avg > 0 else 0

            unit_name = unit_type.replace('_ships', '').replace('_', ' ').title()
            symbol = "✓" if diff > 0.5 else "-" if diff < -0.5 else "="
            print(f"{unit_name:<30} {winner_avg:>15.1f} {loser_avg:>15.1f} {diff:>15.1f} {symbol} {advantage:>15.1f}%")

    print()
    print("📈 KEY INSIGHTS")
    print("-" * 120)

    # Fighter adoption
    fighter_data = []
    for strategy in strategies:
        data = strategy_data[strategy]
        if data['unit_counts']['fighter_ships']:
            avg_fighters = mean(data['unit_counts']['fighter_ships'])
            fighter_data.append((strategy, avg_fighters))

    fighter_data.sort(key=lambda x: x[1], reverse=True)

    print("\n🚀 Fighter Adoption (20PP, 2.86 PP/pwr - most efficient):")
    for strategy, avg_fighters in fighter_data:
        if avg_fighters > 0.1:
            print(f"  {strategy:<20} {avg_fighters:>6.1f} fighters")

    # Capital ship preference
    print("\n🛡️  Capital Ship Composition:")
    for strategy in strategies:
        data = strategy_data[strategy]
        bc = mean(data['unit_counts']['battlecruiser_ships']) if data['unit_counts']['battlecruiser_ships'] else 0
        bb = mean(data['unit_counts']['battleship_ships']) if data['unit_counts']['battleship_ships'] else 0
        dn = mean(data['unit_counts']['dreadnought_ships']) if data['unit_counts']['dreadnought_ships'] else 0

        if bc + bb + dn > 0.1:
            print(f"  {strategy:<20} BC:{bc:>5.1f}  BB:{bb:>5.1f}  DN:{dn:>5.1f}")

    # Cost efficiency winners
    winner_units_all = defaultdict(list)
    for strategy in strategies:
        data = strategy_data[strategy]
        for unit_type, counts in data['winner_units'].items():
            winner_units_all[unit_type].extend(counts)

    print("\n💎 Most Common Units in Winning Armies:")
    unit_popularity = []
    for unit_type, counts in winner_units_all.items():
        if counts and unit_type in UNIT_COSTS:
            avg_count = mean(counts)
            if avg_count > 0.5:
                total_pp = avg_count * UNIT_COSTS[unit_type]
                unit_name = unit_type.replace('_ships', '').replace('_units', '').replace('_', ' ').title()
                unit_popularity.append((unit_name, avg_count, total_pp))

    unit_popularity.sort(key=lambda x: x[2], reverse=True)

    for unit_name, avg_count, total_pp in unit_popularity[:10]:
        print(f"  {unit_name:<30} {avg_count:>6.1f} units  ({total_pp:>7.0f} PP invested)")

    print()
    print("=" * 120)
    print(f"✅ Analysis complete! ({len(csv_files)} games)")
    print("=" * 120)

if __name__ == "__main__":
    analyze_unit_effectiveness()
