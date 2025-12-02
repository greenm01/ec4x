#!/usr/bin/env python3
"""
Analyze diagnostic metrics from batch simulation runs
Identifies red-flag patterns per Grok gap analysis
Uses only Python stdlib (no pandas dependency)
"""

import csv
import sys
from pathlib import Path
from typing import Dict, List
from collections import defaultdict

def load_all_diagnostics(diagnostics_dir: Path) -> List[Dict]:
    """Load all diagnostic CSV files and combine into list of dicts."""
    csv_files = list(diagnostics_dir.glob("game_*.csv"))

    if not csv_files:
        print(f"ERROR: No diagnostic CSV files found in {diagnostics_dir}")
        return []

    print(f"Loading {len(csv_files)} diagnostic files...")

    all_rows = []
    for csv_file in csv_files:
        try:
            # Extract game seed from filename (e.g., game_12346.csv -> 12346)
            game_seed = int(csv_file.stem.split('_')[1])

            with open(csv_file, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    row['game_seed'] = game_seed
                    # Convert numeric fields
                    for key in row:
                        if key not in ['house', 'clk_no_raiders']:
                            try:
                                row[key] = int(row[key])
                            except (ValueError, KeyError):
                                pass
                    # Convert boolean
                    row['clk_no_raiders'] = row['clk_no_raiders'].lower() == 'true'
                    all_rows.append(row)
        except Exception as e:
            print(f"  WARNING: Failed to load {csv_file}: {e}")

    if not all_rows:
        print("ERROR: No valid CSV files loaded")
        return []

    print(f"  Loaded {len(all_rows)} total rows ({len(csv_files)} games)")
    if all_rows:
        max_turn = max(row['turn'] for row in all_rows)
        print(f"  Turns per game: {max_turn}")

    return all_rows

def analyze_red_flags(data: List[Dict]) -> Dict[str, float]:
    """Calculate red-flag metrics per Grok gap analysis."""

    if not data:
        return {}

    metrics = {}
    total_rows = len(data)

    # CRITICAL: Capacity violations
    capacity_violations = sum(1 for row in data if row['capacity_violations'] > 0)
    metrics['capacity_violation_rate'] = (capacity_violations / total_rows * 100) if total_rows > 0 else 0

    # CRITICAL: Espionage missions
    total_spy = sum(row['spy_planet'] for row in data)
    total_hack = sum(row['hack_starbase'] for row in data)

    # Count games with at least one espionage mission
    games_with_esp = set()
    for row in data:
        if row['spy_planet'] > 0 or row['hack_starbase'] > 0:
            games_with_esp.add(row['game_seed'])

    unique_games = len(set(row['game_seed'] for row in data))
    metrics['games_with_espionage_pct'] = (len(games_with_esp) / unique_games * 100) if unique_games > 0 else 0
    metrics['total_spy_missions'] = total_spy
    metrics['total_hack_missions'] = total_hack

    # HIGH: Idle carriers
    carrier_rows = [row for row in data if row['total_carriers'] > 0]
    if carrier_rows:
        idle_rates = [row['idle_carriers'] / row['total_carriers'] for row in carrier_rows]
        metrics['avg_idle_carrier_rate'] = (sum(idle_rates) / len(idle_rates) * 100) if idle_rates else 0
        high_idle = sum(1 for rate in idle_rates if rate > 0.2)
        metrics['high_idle_games_pct'] = (high_idle / len(carrier_rows) * 100) if carrier_rows else 0
    else:
        metrics['avg_idle_carrier_rate'] = 0
        metrics['high_idle_games_pct'] = 0

    # HIGH: ELI mesh coverage
    invasion_rows = [row for row in data if row['total_invasions'] > 0]
    if invasion_rows:
        no_eli_rates = [row['invasions_no_eli'] / row['total_invasions'] for row in invasion_rows]
        metrics['avg_invasions_without_eli'] = (sum(no_eli_rates) / len(no_eli_rates) * 100) if no_eli_rates else 0
    else:
        metrics['avg_invasions_without_eli'] = 0

    # HIGH: Raider ambush success
    raider_rows = [row for row in data if row['raider_attempts'] > 0]
    if raider_rows:
        success_rates = [row['raider_success'] / row['raider_attempts'] for row in raider_rows]
        metrics['avg_raider_success_rate'] = (sum(success_rates) / len(success_rates) * 100) if success_rates else 0
    else:
        metrics['avg_raider_success_rate'] = 0

    # MEDIUM: CLK research without Raiders
    clk_no_raiders = sum(1 for row in data if row['clk_no_raiders'])
    metrics['clk_no_raiders_rate'] = (clk_no_raiders / total_rows * 100) if total_rows > 0 else 0

    # MEDIUM: Undefended colonies
    colony_rows = [row for row in data if row['total_colonies'] > 0]
    if colony_rows:
        undef_rates = [row['undefended_colonies'] / row['total_colonies'] for row in colony_rows]
        metrics['avg_undefended_rate'] = (sum(undef_rates) / len(undef_rates) * 100) if undef_rates else 0
    else:
        metrics['avg_undefended_rate'] = 0

    # MEDIUM: Mothballed fleet usage
    # Get final turn data
    final_turns = defaultdict(int)
    for row in data:
        if row['turn'] > final_turns[row['game_seed']]:
            final_turns[row['game_seed']] = row['turn']

    final_turn_rows = [row for row in data if row['turn'] == final_turns[row['game_seed']]]
    if final_turn_rows:
        games_with_mothball = sum(1 for row in final_turn_rows if row['mothball_used'] > 0)
        metrics['games_with_mothballing_pct'] = (games_with_mothball / len(final_turn_rows) * 100) if final_turn_rows else 0
    else:
        metrics['games_with_mothballing_pct'] = 0

    # Economy: Zero-spend turns
    chronic_zero = sum(1 for row in data if row['zero_spend_turns'] > 5)
    metrics['chronic_zero_spend_rate'] = (chronic_zero / total_rows * 100) if total_rows > 0 else 0

    return metrics

def print_analysis_report(metrics: Dict[str, float]):
    """Print formatted analysis report with red-flag thresholds."""

    print("\n" + "=" * 70)
    print("DIAGNOSTIC ANALYSIS REPORT")
    print("=" * 70)

    print("\n🚨 CRITICAL RED FLAGS")
    print("-" * 70)

    # Capacity violations
    cv_rate = metrics['capacity_violation_rate']
    cv_status = "❌ FAIL" if cv_rate > 2 else "✅ PASS"
    print(f"Capacity violations: {cv_rate:.1f}% {cv_status}")
    print(f"  Target: < 2% (any active violations after grace period)")

    # Espionage missions
    esp_rate = metrics['games_with_espionage_pct']
    esp_status = "❌ FAIL" if esp_rate < 80 else "✅ PASS"
    print(f"Games with espionage: {esp_rate:.1f}% {esp_status}")
    print(f"  Target: > 80% (SpyPlanet + HackStarbase missions)")
    print(f"  Total spy missions: {metrics['total_spy_missions']:.0f}")
    print(f"  Total hack missions: {metrics['total_hack_missions']:.0f}")

    print("\n⚠️  HIGH PRIORITY")
    print("-" * 70)

    # Idle carriers
    idle_rate = metrics['avg_idle_carrier_rate']
    idle_status = "❌ FAIL" if idle_rate > 20 else "✅ PASS"
    print(f"Avg idle carrier rate: {idle_rate:.1f}% {idle_status}")
    print(f"  Target: < 20% (carriers with 0 fighters)")
    print(f"  Games with >20% idle: {metrics['high_idle_games_pct']:.1f}%")

    # ELI mesh coverage
    eli_rate = metrics['avg_invasions_without_eli']
    eli_status = "❌ FAIL" if eli_rate > 50 else "✅ PASS"
    print(f"Invasions without ELI mesh: {eli_rate:.1f}% {eli_status}")
    print(f"  Target: < 50% (invasions with <3 scouts)")

    # Raider success
    raider_rate = metrics['avg_raider_success_rate']
    raider_status = "❌ FAIL" if raider_rate < 35 else "✅ PASS"
    print(f"Raider ambush success: {raider_rate:.1f}% {raider_status}")
    print(f"  Target: > 35% (when CLK > ELI)")

    print("\n📊 MEDIUM PRIORITY")
    print("-" * 70)

    # CLK without Raiders
    clk_rate = metrics['clk_no_raiders_rate']
    print(f"CLK researched but no Raiders: {clk_rate:.1f}%")
    print(f"  Target: < 10% (inefficient research)")

    # Undefended colonies
    undef_rate = metrics['avg_undefended_rate']
    print(f"Avg undefended colonies: {undef_rate:.1f}%")
    print(f"  Target: < 30% (no fleet or starbase defense)")

    # Mothballing
    mothball_rate = metrics['games_with_mothballing_pct']
    mothball_status = "❌ FAIL" if mothball_rate < 70 else "✅ PASS"
    print(f"Games with mothballing: {mothball_rate:.1f}% {mothball_status}")
    print(f"  Target: > 70% (late-game efficiency)")

    # Zero-spend
    zero_rate = metrics['chronic_zero_spend_rate']
    print(f"Chronic zero-spend (>5 turns): {zero_rate:.1f}%")
    print(f"  Target: < 5% (resource hoarding)")

    print("\n" + "=" * 70)

def main():
    diagnostics_dir = Path("balance_results/diagnostics")

    if not diagnostics_dir.exists():
        print(f"ERROR: Diagnostics directory not found: {diagnostics_dir}")
        print("Please run diagnostic games first with run_diagnostic_batch.py")
        return 1

    # Load all diagnostic data
    data = load_all_diagnostics(diagnostics_dir)

    if not data:
        return 1

    # Calculate red-flag metrics
    metrics = analyze_red_flags(data)

    # Print analysis report
    print_analysis_report(metrics)

    return 0

if __name__ == "__main__":
    sys.exit(main())
