#!/usr/bin/env python3
"""
Analyze 4-act game progression across multiple test runs.

Validates that the game follows the intended dramatic arc:
- Act 1 (Turn 7):  Land Grab - Rapid expansion, 5-8 colonies
- Act 2 (Turn 15): Rising Tensions - Consolidation, 10-15 colonies, first conflicts
- Act 3 (Turn 25): Total War - Major conflicts, clear leaders
- Act 4 (Turn 30): Endgame - Victory conditions met or imminent

Expected metrics per act are defined in BALANCE_TESTING_METHODOLOGY.md
"""

import csv
import sys
from pathlib import Path
from collections import defaultdict
from dataclasses import dataclass
from typing import Dict, List

@dataclass
class ActMetrics:
    """Expected metrics for each act"""
    turn: int
    name: str
    min_colonies: int
    max_colonies: int
    min_prestige: int
    max_prestige: int
    military_expected: bool
    conflicts_expected: bool

# 4-Act structure from BALANCE_TESTING_METHODOLOGY.md
ACT_DEFINITIONS = [
    ActMetrics(7, "Act 1: Land Grab", 5, 8, 50, 150, False, False),
    ActMetrics(15, "Act 2: Rising Tensions", 10, 15, 150, 500, True, True),
    ActMetrics(25, "Act 3: Total War", 15, 25, 500, 1500, True, True),
    ActMetrics(30, "Act 4: Endgame", 20, 30, 1000, 3000, True, True),
]

def analyze_game_file(filepath: Path) -> Dict:
    """Analyze a single game CSV file for 4-act progression"""
    results = {
        'houses': defaultdict(lambda: defaultdict(dict)),
        'turns_analyzed': []
    }

    with open(filepath) as f:
        reader = csv.DictReader(f)
        for row in reader:
            turn = int(row['turn'])
            house = row['house']

            # Store metrics for act analysis turns
            if turn in [7, 15, 25, 30]:
                results['houses'][house][turn] = {
                    'colonies': int(row['total_colonies']),
                    'treasury': int(row['treasury']),
                    'production': int(row['production']),
                    'scouts': int(row['scout_count']),
                    'fighters': int(row['total_fighters']),
                    'space_total': int(row['space_total']),
                    'invasions': int(row['total_invasions']),
                    'espionage': int(row['total_espionage']),
                }
                if turn not in results['turns_analyzed']:
                    results['turns_analyzed'].append(turn)

    return results

def validate_act(house_data: Dict, act: ActMetrics) -> Dict:
    """Validate if house meets act expectations"""
    if act.turn not in house_data:
        return {'status': 'missing', 'issues': [f"No data for turn {act.turn}"]}

    data = house_data[act.turn]
    issues = []
    warnings = []

    # Colony count validation
    colonies = data['colonies']
    if colonies < act.min_colonies:
        issues.append(f"Colonies: {colonies} (expected {act.min_colonies}-{act.max_colonies})")
    elif colonies > act.max_colonies:
        warnings.append(f"Colonies: {colonies} exceeds expected {act.max_colonies}")

    # Military validation
    if act.military_expected:
        if data['fighters'] == 0 and data['scouts'] == 0:
            issues.append(f"No military built (fighters: {data['fighters']}, scouts: {data['scouts']})")

    # Conflict validation
    if act.conflicts_expected:
        if data['space_total'] == 0 and data['invasions'] == 0:
            warnings.append(f"No conflicts recorded (space: {data['space_total']}, invasions: {data['invasions']})")

    status = 'fail' if issues else ('warn' if warnings else 'pass')
    return {'status': status, 'issues': issues, 'warnings': warnings, 'data': data}

def main():
    diagnostics_dir = Path('balance_results/diagnostics')

    if not diagnostics_dir.exists():
        print(f"Error: {diagnostics_dir} not found")
        return 1

    # Find all game CSV files
    game_files = sorted(diagnostics_dir.glob('game_*.csv'))

    if not game_files:
        print(f"Error: No game files found in {diagnostics_dir}")
        return 1

    print("=" * 80)
    print("EC4X 4-Act Progression Analysis")
    print("=" * 80)
    print(f"Analyzing {len(game_files)} games\n")

    # Aggregate results
    all_results = []
    for game_file in game_files:
        all_results.append(analyze_game_file(game_file))

    # Analyze each act
    for act in ACT_DEFINITIONS:
        print(f"\n{'=' * 80}")
        print(f"{act.name} (Turn {act.turn})")
        print(f"Expected: {act.min_colonies}-{act.max_colonies} colonies")
        print('=' * 80)

        # Collect stats across all games
        house_results = defaultdict(lambda: {'pass': 0, 'warn': 0, 'fail': 0, 'missing': 0})
        house_colonies = defaultdict(list)

        for game_result in all_results:
            for house, turns in game_result['houses'].items():
                validation = validate_act(turns, act)
                house_results[house][validation['status']] += 1

                if validation['status'] != 'missing' and 'data' in validation:
                    house_colonies[house].append(validation['data']['colonies'])

        # Print summary table
        print(f"\n{'House':<20} {'Pass':<8} {'Warn':<8} {'Fail':<8} {'Avg Colonies':<15}")
        print('-' * 80)

        for house in sorted(house_results.keys()):
            stats = house_results[house]
            avg_colonies = sum(house_colonies[house]) / len(house_colonies[house]) if house_colonies[house] else 0

            total = sum(stats.values())
            pass_pct = (stats['pass'] / total * 100) if total > 0 else 0

            status_icon = '✓' if pass_pct >= 75 else ('⚠' if pass_pct >= 50 else '✗')

            print(f"{house:<20} {stats['pass']:<8} {stats['warn']:<8} {stats['fail']:<8} {avg_colonies:<15.1f} {status_icon}")

        # Overall act status
        total_pass = sum(h['pass'] for h in house_results.values())
        total_tests = sum(sum(h.values()) for h in house_results.values())
        overall_pct = (total_pass / total_tests * 100) if total_tests > 0 else 0

        print(f"\nOverall Success Rate: {overall_pct:.1f}% ({total_pass}/{total_tests})")

        if overall_pct >= 75:
            print(f"Status: ✓ {act.name} is BALANCED")
        elif overall_pct >= 50:
            print(f"Status: ⚠ {act.name} needs TUNING")
        else:
            print(f"Status: ✗ {act.name} is BROKEN")

    print("\n" + "=" * 80)
    print("Analysis Complete")
    print("=" * 80)

    return 0

if __name__ == '__main__':
    sys.exit(main())
