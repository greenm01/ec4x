#!/usr/bin/env python3
"""
Single Game Detailed Analysis Tool

Generates comprehensive tables and metrics for a single game simulation
to diagnose AI behavior, unit production, combat losses, and strategic patterns.

Usage:
    python3 analyze_single_game.py <game_seed>
    python3 analyze_single_game.py 2000  # Analyze game_2000.csv
"""

import sys
import csv
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Tuple

def load_game_data(game_seed: str) -> List[Dict]:
    """Load diagnostic CSV for a specific game."""
    csv_path = Path(f"balance_results/diagnostics/game_{game_seed}.csv")

    if not csv_path.exists():
        print(f"❌ Error: Game file not found: {csv_path}")
        sys.exit(1)

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        return list(reader)

def get_final_turn_data(data: List[Dict]) -> Dict[str, Dict]:
    """Extract final turn data for each house."""
    max_turn = max(int(row['turn']) for row in data)
    final_data = {}

    for row in data:
        if int(row['turn']) == max_turn:
            house = row['house']
            final_data[house] = row

    return final_data

def get_cumulative_stats(data: List[Dict]) -> Dict[str, Dict]:
    """Calculate cumulative statistics over entire game."""
    stats = defaultdict(lambda: {
        'ships_lost': 0,
        'fighters_lost': 0,
        'colonies_lost': 0,
        'colonies_gained': 0,
        'ships_built': 0,
        'fighters_built': 0
    })

    for row in data:
        house = row['house']
        stats[house]['ships_lost'] += int(row.get('ships_lost', 0))
        stats[house]['fighters_lost'] += int(row.get('fighters_lost', 0))
        stats[house]['colonies_lost'] += int(row.get('colonies_lost', 0))
        stats[house]['colonies_gained'] += int(row.get('colonies_gained', 0))
        # Fighters built = fighters gained (since fighters_gained tracks production)
        stats[house]['fighters_built'] += int(row.get('fighters_gained', 0))

    return dict(stats)

def print_final_fleet_composition(final_data: Dict[str, Dict]):
    """Print detailed fleet composition table by ship type."""
    print("\n" + "="*100)
    print("FINAL FLEET COMPOSITION (Turn 45)")
    print("="*100)

    ship_types = [
        ('destroyer_ships', 'Destroyers'),
        ('cruiser_ships', 'Cruisers'),
        ('light_cruiser_ships', 'Lt Cruisers'),
        ('heavy_cruiser_ships', 'Hv Cruisers'),
        ('battlecruiser_ships', 'Battlecruisers'),
        ('battleship_ships', 'Battleships'),
        ('dreadnought_ships', 'Dreadnoughts'),
        ('super_dreadnought_ships', 'Super Dreads'),
        ('carrier_ships', 'Carriers'),
        ('super_carrier_ships', 'Super Carriers'),
        ('starbase_ships', 'Starbases'),
        ('total_fighters', 'Fighters'),
        ('total_ships', 'TOTAL SHIPS')
    ]

    # Header
    houses = sorted(final_data.keys())
    print(f"{'Ship Type':<20}", end='')
    for house in houses:
        short_name = house.replace('house-', '')
        print(f"{short_name:>12}", end='')
    print(f"{'  TOTAL':>12}")
    print("-" * 100)

    # Rows
    for col, label in ship_types:
        if label == 'TOTAL SHIPS':
            print("-" * 100)
        print(f"{label:<20}", end='')
        row_total = 0
        for house in houses:
            count = int(final_data[house].get(col, 0))
            row_total += count
            if count > 0:
                print(f"{count:>12}", end='')
            else:
                print(f"{'—':>12}", end='')
        print(f"{row_total:>12}")

def print_ground_forces(final_data: Dict[str, Dict]):
    """Print ground forces composition table."""
    print("\n" + "="*100)
    print("GROUND FORCES (Turn 45)")
    print("="*100)

    ground_types = [
        ('army_units', 'Armies'),
        ('marine_units', 'Marines'),
        ('ground_batteries', 'Ground Batteries')
    ]

    houses = sorted(final_data.keys())

    # Header
    print(f"{'Unit Type':<30}", end='')
    for house in houses:
        print(f"{house.replace('house-', ''):>12}", end='')
    print(f"{'TOTAL':>12}")
    print("-" * 100)

    # Print each ground unit type
    for col_name, display_name in ground_types:
        print(f"{display_name:<30}", end='')
        row_total = 0
        for house in houses:
            count = int(final_data[house].get(col_name, 0))
            row_total += count
            if count > 0:
                print(f"{count:>12}", end='')
            else:
                print(f"{'—':>12}", end='')
        print(f"{row_total:>12}")

    # Print totals row
    print("-" * 100)
    print(f"{'TOTAL GROUND UNITS':<30}", end='')
    for house in houses:
        total = (int(final_data[house].get('army_units', 0)) +
                 int(final_data[house].get('marine_units', 0)) +
                 int(final_data[house].get('ground_batteries', 0)))
        print(f"{total:>12}", end='')

    grand_total = sum(
        int(final_data[house].get('army_units', 0)) +
        int(final_data[house].get('marine_units', 0)) +
        int(final_data[house].get('ground_batteries', 0))
        for house in houses
    )
    print(f"{grand_total:>12}")

def print_combat_losses(cumulative: Dict[str, Dict], final_data: Dict[str, Dict]):
    """Print combat losses table."""
    print("\n" + "="*100)
    print("COMBAT LOSSES (Cumulative)")
    print("="*100)

    houses = sorted(cumulative.keys())
    print(f"{'House':<20}{'Ships Lost':>15}{'Fighters Lost':>15}{'Total Losses':>15}{'Survival %':>15}")
    print("-" * 100)

    for house in houses:
        ships_lost = cumulative[house]['ships_lost']
        fighters_lost = cumulative[house]['fighters_lost']
        total_lost = ships_lost + fighters_lost

        # Calculate survival rate (final units / (final + lost))
        final_ships = int(final_data[house].get('total_ships', 0))
        final_fighters = int(final_data[house].get('total_fighters', 0))
        total_final = final_ships + final_fighters
        total_ever = total_final + total_lost
        survival_pct = (total_final / total_ever * 100) if total_ever > 0 else 0

        short_name = house.replace('house-', '')
        print(f"{short_name:<20}{ships_lost:>15}{fighters_lost:>15}{total_lost:>15}{survival_pct:>14.1f}%")

def print_production_summary(cumulative: Dict[str, Dict], final_data: Dict[str, Dict]):
    """Print production summary."""
    print("\n" + "="*100)
    print("PRODUCTION SUMMARY")
    print("="*100)

    houses = sorted(cumulative.keys())
    print(f"{'House':<20}{'Fighters Built':>15}{'Ships Built*':>15}{'Total Built':>15}{'Build Rate':>15}")
    print("-" * 100)

    for house in houses:
        fighters_built = cumulative[house]['fighters_built']
        # Ships built = final ships + ships lost (rough estimate)
        final_ships = int(final_data[house].get('total_ships', 0))
        ships_lost = cumulative[house]['ships_lost']
        ships_built = final_ships + ships_lost

        total_built = ships_built + fighters_built
        build_rate = total_built / 45.0  # Units per turn

        short_name = house.replace('house-', '')
        print(f"{short_name:<20}{fighters_built:>15}{ships_built:>15}{total_built:>15}{build_rate:>14.2f}/t")

    print("\n* Ships Built = Final Ships + Ships Lost (includes combat replacements)")

def print_territorial_control(cumulative: Dict[str, Dict], final_data: Dict[str, Dict]):
    """Print territorial control and colony changes."""
    print("\n" + "="*100)
    print("TERRITORIAL CONTROL")
    print("="*100)

    houses = sorted(cumulative.keys())
    print(f"{'House':<20}{'Final Colonies':>15}{'Captured':>12}{'Lost':>12}{'Net Change':>12}")
    print("-" * 100)

    for house in houses:
        final_colonies = int(final_data[house].get('total_colonies', 0))
        captured = cumulative[house]['colonies_gained']
        lost = cumulative[house]['colonies_lost']
        net = captured - lost

        short_name = house.replace('house-', '')
        net_str = f"+{net}" if net > 0 else str(net)
        print(f"{short_name:<20}{final_colonies:>15}{captured:>12}{lost:>12}{net_str:>12}")

def print_economy_and_prestige(final_data: Dict[str, Dict]):
    """Print economy and prestige summary."""
    print("\n" + "="*100)
    print("FINAL ECONOMY & PRESTIGE")
    print("="*100)

    houses = sorted(final_data.keys())
    print(f"{'House':<20}{'Prestige':>12}{'Treasury':>12}{'Production':>12}{'Colonies':>10}{'PP/Colony':>12}")
    print("-" * 100)

    results = []
    for house in houses:
        prestige = int(final_data[house].get('prestige', 0))
        treasury = int(final_data[house].get('treasury', 0))
        production = int(final_data[house].get('production', 0))
        colonies = int(final_data[house].get('total_colonies', 0))
        pp_per_colony = production / colonies if colonies > 0 else 0

        short_name = house.replace('house-', '')
        results.append((prestige, house, short_name, treasury, production, colonies, pp_per_colony))

    # Sort by prestige (highest first)
    results.sort(reverse=True)

    for i, (prestige, house, short_name, treasury, production, colonies, pp_per_colony) in enumerate(results):
        rank = "👑" if i == 0 else f"#{i+1}"
        print(f"{rank:>2} {short_name:<17}{prestige:>12}{treasury:>12}{production:>12}{colonies:>10}{pp_per_colony:>11.1f}")

def detect_red_flags(data: List[Dict], cumulative: Dict[str, Dict], final_data: Dict[str, Dict]):
    """Detect and report anomalies and red flags."""
    print("\n" + "="*100)
    print("RED FLAGS & ANOMALIES")
    print("="*100)

    flags = []

    for house in final_data.keys():
        short_name = house.replace('house-', '')
        final = final_data[house]

        # Check 1: Low ship production
        ships_built = int(final.get('total_ships', 0)) + cumulative[house]['ships_lost']
        if ships_built < 15:
            flags.append(('🚨 LOW PRODUCTION', f"{short_name}: Only {ships_built} ships built in 45 turns"))

        # Check 2: High treasury hoarding
        treasury = int(final.get('treasury', 0))
        if treasury > 5000:
            flags.append(('💰 HOARDING', f"{short_name}: {treasury} PP unspent (excessive saving)"))

        # Check 3: Heavy combat losses
        ships_lost = cumulative[house]['ships_lost']
        if ships_lost > 20:
            flags.append(('💥 HEAVY LOSSES', f"{short_name}: Lost {ships_lost} ships to combat"))

        # Check 4: No capital ships
        capitals = sum(int(final.get(col, 0)) for col in [
            'battlecruiser_ships', 'battleship_ships', 'dreadnought_ships',
            'super_dreadnought_ships', 'carrier_ships', 'super_carrier_ships'
        ])
        if capitals == 0:
            flags.append(('⚠️  NO CAPITALS', f"{short_name}: No capital ships by Turn 45"))

        # Check 5: Undefended colonies
        undefended = int(final.get('undefended_colonies', 0))
        if undefended > 0:
            flags.append(('🛡️  VULNERABLE', f"{short_name}: {undefended} undefended colonies"))

        # Check 6: Lost more colonies than gained
        net_colonies = cumulative[house]['colonies_gained'] - cumulative[house]['colonies_lost']
        if net_colonies < -1:
            flags.append(('🌍 LOSING GROUND', f"{short_name}: Net {net_colonies} colonies (losing territory)"))

    if not flags:
        print("✅ No major red flags detected!")
    else:
        # Print as table
        print(f"{'Flag':<20}{'Description':<80}")
        print("-" * 100)
        for flag_type, description in flags:
            print(f"{flag_type:<20}{description:<80}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_single_game.py <game_seed>")
        print("Example: python3 analyze_single_game.py 2000")
        sys.exit(1)

    game_seed = sys.argv[1]

    print(f"\n{'='*100}")
    print(f"DETAILED GAME ANALYSIS - Seed {game_seed}")
    print(f"{'='*100}")

    # Load data
    data = load_game_data(game_seed)
    final_data = get_final_turn_data(data)
    cumulative = get_cumulative_stats(data)

    # Print all tables
    print_final_fleet_composition(final_data)
    print_ground_forces(final_data)
    print_combat_losses(cumulative, final_data)
    print_production_summary(cumulative, final_data)
    print_territorial_control(cumulative, final_data)
    print_economy_and_prestige(final_data)
    detect_red_flags(data, cumulative, final_data)

    print("\n" + "="*100)
    print("END OF ANALYSIS")
    print("="*100 + "\n")

if __name__ == "__main__":
    main()
