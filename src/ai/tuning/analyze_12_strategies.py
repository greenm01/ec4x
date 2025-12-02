#!/usr/bin/env python3
"""
Comprehensive analysis of all 12 AI strategies from diagnostic CSV files.
Focuses on unit cost effectiveness, tech tree scaling, and balance issues.
"""

import csv
import sys
from pathlib import Path
from collections import defaultdict
from statistics import mean, stdev

# Map house names to strategies (from balance_test_config.nim)
STRATEGY_MAP = {
    'house-corrino': 'Economic',
    'house-vernius': 'Balanced',
    'house-moritani': 'Turtle',
    'house-richese': 'Aggressive',
    'house-ginaz': 'Economic',  # Rotation repeats
    'house-ecaz': 'Balanced',
    'house-tleilax': 'Turtle',
    'house-ixian': 'Aggressive',
    'house-bene-gesserit': 'Economic',
    'house-atreides': 'Balanced',
    'house-harkonnen': 'Turtle',
    'house-ordos': 'Aggressive',
}

def analyze_diagnostics():
    """Analyze all diagnostic CSV files for 12-strategy balance testing."""
    diag_dir = Path("balance_results/diagnostics")
    csv_files = list(diag_dir.glob("*.csv"))

    if not csv_files:
        print("❌ No diagnostic CSV files found!")
        sys.exit(1)

    print(f"📊 Analyzing {len(csv_files)} games with 12-player setup...")
    print()

    # Collect data by strategy
    strategy_data = defaultdict(lambda: {
        'prestige': [],
        'colonies': [],
        'fighters': [],
        'capitals': [],
        'escorts': [],
        'scouts': [],
        'eco_level': [],
        'sci_level': [],
        'wpn_level': [],
        'cst_level': [],
        'treasury': [],
        'production': [],
        'wins': 0,
        'games': 0
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
                house = row['house']
                strategy = STRATEGY_MAP.get(house, 'Unknown')

                if strategy == 'Unknown':
                    continue

                data = strategy_data[strategy]
                data['games'] += 1

                if house == winner_house:
                    data['wins'] += 1

                # Collect metrics
                data['prestige'].append(float(row.get('prestige', 0)))
                data['colonies'].append(int(row.get('total_colonies', 0)))
                data['fighters'].append(int(row.get('total_fighters', 0)))

                # Calculate capitals (BC+BB+DN+SD)
                capitals = (int(row.get('battlecruiser_ships', 0)) +
                           int(row.get('battleship_ships', 0)) +
                           int(row.get('dreadnought_ships', 0)) +
                           int(row.get('super_dreadnought_ships', 0)))
                data['capitals'].append(capitals)

                # Calculate escorts (DD+CA+CL)
                escorts = (int(row.get('destroyer_ships', 0)) +
                          int(row.get('heavy_cruiser_ships', 0)) +
                          int(row.get('light_cruiser_ships', 0)))
                data['escorts'].append(escorts)

                data['scouts'].append(int(row.get('scout_ships', 0)))
                data['eco_level'].append(int(row.get('tech_el', 0)))
                data['sci_level'].append(int(row.get('tech_sl', 0)))
                data['wpn_level'].append(int(row.get('tech_wep', 0)))
                data['cst_level'].append(int(row.get('tech_cst', 0)))
                data['treasury'].append(int(row.get('treasury', 0)))
                data['production'].append(int(row.get('production', 0)))

    # Print results
    print("=" * 100)
    print("12-STRATEGY BALANCE ANALYSIS")
    print("=" * 100)
    print()

    # Sort strategies by average prestige
    strategies = sorted(strategy_data.keys(),
                       key=lambda s: mean(strategy_data[s]['prestige']) if strategy_data[s]['prestige'] else 0,
                       reverse=True)

    print("📈 STRATEGY PERFORMANCE (sorted by prestige)")
    print("-" * 100)
    print(f"{'Strategy':<20} {'Games':>6} {'Win%':>7} {'Prestige':>12} {'Colonies':>9} {'Treasury':>10}")
    print("-" * 100)

    for strategy in strategies:
        data = strategy_data[strategy]
        if not data['prestige']:
            continue

        avg_prestige = mean(data['prestige'])
        std_prestige = stdev(data['prestige']) if len(data['prestige']) > 1 else 0
        win_rate = (data['wins'] / data['games'] * 100) if data['games'] > 0 else 0
        avg_colonies = mean(data['colonies'])
        avg_treasury = mean(data['treasury'])

        print(f"{strategy:<20} {data['games']:>6} {win_rate:>6.1f}% {avg_prestige:>7.1f} ±{std_prestige:>3.0f} "
              f"{avg_colonies:>9.1f} {avg_treasury:>10.0f}")

    print()
    print("⚔️  MILITARY COMPOSITION")
    print("-" * 100)
    print(f"{'Strategy':<20} {'Fighters':>9} {'Capitals':>9} {'Escorts':>8} {'Scouts':>7} {'Total':>7}")
    print("-" * 100)

    for strategy in strategies:
        data = strategy_data[strategy]
        if not data['fighters']:
            continue

        avg_fighters = mean(data['fighters'])
        avg_capitals = mean(data['capitals'])
        avg_escorts = mean(data['escorts'])
        avg_scouts = mean(data['scouts'])
        total = avg_fighters + avg_capitals + avg_escorts + avg_scouts

        print(f"{strategy:<20} {avg_fighters:>9.1f} {avg_capitals:>9.1f} {avg_escorts:>8.1f} "
              f"{avg_scouts:>7.1f} {total:>7.1f}")

    print()
    print("🔬 TECHNOLOGY PROGRESSION")
    print("-" * 100)
    print(f"{'Strategy':<20} {'ECO':>5} {'SCI':>5} {'WPN':>5} {'CST':>5} {'Total':>6}")
    print("-" * 100)

    for strategy in strategies:
        data = strategy_data[strategy]
        if not data['eco_level']:
            continue

        avg_eco = mean(data['eco_level'])
        avg_sci = mean(data['sci_level'])
        avg_wpn = mean(data['wpn_level'])
        avg_cst = mean(data['cst_level'])
        total_tech = avg_eco + avg_sci + avg_wpn + avg_cst

        print(f"{strategy:<20} {avg_eco:>5.1f} {avg_sci:>5.1f} {avg_wpn:>5.1f} "
              f"{avg_cst:>5.1f} {total_tech:>6.1f}")

    print()
    print("💡 KEY FINDINGS")
    print("-" * 100)

    # Fighter adoption analysis
    print("\n🚀 Fighter Adoption (post-budget fix):")
    fighter_users = [(s, mean(strategy_data[s]['fighters']))
                     for s in strategies if strategy_data[s]['fighters']]
    fighter_users.sort(key=lambda x: x[1], reverse=True)

    for strategy, avg_fighters in fighter_users[:5]:
        print(f"  {strategy:<20} {avg_fighters:>5.1f} fighters")

    # Tech scaling patterns
    print("\n📚 Tech Scaling Leaders:")
    tech_leaders = [(s, mean(strategy_data[s]['sci_level']) if strategy_data[s]['sci_level'] else 0)
                    for s in strategies]
    tech_leaders.sort(key=lambda x: x[1], reverse=True)

    for strategy, avg_sci in tech_leaders[:5]:
        avg_cst = mean(strategy_data[strategy]['cst_level']) if strategy_data[strategy]['cst_level'] else 0
        print(f"  {strategy:<20} SCI:{avg_sci:.1f}  CST:{avg_cst:.1f}")

    # Balance issues
    print("\n⚖️  Balance Concerns:")
    win_rates = [(s, (strategy_data[s]['wins'] / strategy_data[s]['games'] * 100)
                     if strategy_data[s]['games'] > 0 else 0)
                 for s in strategies if strategy_data[s]['games'] > 0]
    win_rates.sort(key=lambda x: x[1], reverse=True)

    top_strategy, top_rate = win_rates[0]
    if top_rate > 40:
        print(f"  ⚠️  {top_strategy} dominates with {top_rate:.1f}% win rate")

    bottom_strategy, bottom_rate = win_rates[-1]
    if bottom_rate < 5:
        print(f"  ⚠️  {bottom_strategy} underperforms with {bottom_rate:.1f}% win rate")

    # Check if any strategies are missing
    expected_strategies = {'Economic', 'Balanced', 'Turtle', 'Aggressive',
                          'Espionage', 'Diplomatic', 'Expansionist', 'TechRush',
                          'Raider', 'MilitaryIndustrial', 'Opportunistic', 'Isolationist'}
    found_strategies = set(strategies)
    missing = expected_strategies - found_strategies

    if missing:
        print(f"\n  ℹ️  Strategies not found in data: {', '.join(sorted(missing))}")
        print(f"     (May be using same 4 strategies repeated across 12 players)")

    print()
    print("=" * 100)
    print(f"✅ Analysis complete! ({len(csv_files)} games, {sum(d['games'] for d in strategy_data.values())} samples)")
    print("=" * 100)

if __name__ == "__main__":
    analyze_diagnostics()
