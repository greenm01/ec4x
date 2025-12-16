#!/usr/bin/env python3.11
"""
Single Game Detailed Analysis Tool

Generates comprehensive tables and metrics for a single game simulation
to diagnose AI behavior, unit production, combat losses, and strategic patterns.

Usage:
    python3.11 analyze_single_game.py <game_seed>
    python3.11 analyze_single_game.py -s 12345
    python3.11 analyze_single_game.py 2000  # Analyze game_2000.db
"""

import sys
import argparse
import sqlite3
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Tuple, Optional

def load_game_data_sqlite(game_seed: str) -> Tuple[List[Dict], sqlite3.Connection]:
    """Load diagnostic data from SQLite database."""
    db_path = Path(f"balance_results/diagnostics/game_{game_seed}.db")

    if not db_path.exists():
        print(f"❌ Error: Game database not found: {db_path}")
        sys.exit(1)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("SELECT * FROM diagnostics ORDER BY turn, house_id")
    rows = cursor.fetchall()

    # Convert to list of dicts for compatibility
    data = []
    for row in rows:
        data.append(dict(row))

    return data, conn

def get_etac_timeline(conn: sqlite3.Connection) -> List[Dict]:
    """Get turn-by-turn ETAC counts from fleet_tracking."""
    cursor = conn.cursor()

    try:
        cursor.execute("""
            SELECT
                turn,
                SUM(etac_count) as concurrent_etacs,
                (SELECT SUM(total_colonies) FROM diagnostics WHERE diagnostics.turn = fleet_tracking.turn) as total_colonies,
                (SELECT MAX(total_systems_on_map) FROM diagnostics WHERE diagnostics.turn = fleet_tracking.turn) as total_systems
            FROM fleet_tracking
            WHERE etac_count > 0
            GROUP BY turn
            ORDER BY turn
        """)

        timeline = []
        for row in cursor.fetchall():
            timeline.append({
                'turn': row[0],
                'concurrent_etacs': row[1],
                'total_colonies': row[2],
                'total_systems': row[3],
                'colonization_pct': (row[2] / row[3] * 100) if row[3] else 0
            })
        return timeline
    except sqlite3.OperationalError:
        # No fleet_tracking table
        return []

def get_final_turn_data(data: List[Dict]) -> Dict[str, Dict]:
    """Extract final turn data for each house."""
    max_turn = max(int(row['turn']) for row in data)
    final_data = {}

    for row in data:
        if int(row['turn']) == max_turn:
            house = row['house_id']
            final_data[house] = row

    return final_data

def get_cumulative_stats(data: List[Dict]) -> Dict[str, Dict]:
    """Calculate cumulative statistics over entire game."""
    stats = defaultdict(lambda: {
        'ships_lost': 0,
        'fighters_lost': 0,
        'colonies_lost': 0,
        'colonies_gained': 0,
        'colonies_gained_act1': 0,  # Act 1 = mostly colonization
        'colonies_gained_act2plus': 0,  # Act 2+ = includes conquests
        'invasions_won': 0,
        'etac_construction_events': 0,  # Total ETAC builds across all turns
        'fighters_built': 0,
        'ship_type_losses': defaultdict(int)
    })

    ship_types = [
        'destroyer_ships', 'cruiser_ships', 'light_cruiser_ships', 'heavy_cruiser_ships',
        'battlecruiser_ships', 'battleship_ships', 'dreadnought_ships', 'super_dreadnought_ships',
        'carrier_ships', 'super_carrier_ships', 'etac_ships', 'troop_transport_ships',
        'scout_ships', 'corvette_ships', 'frigate_ships', 'raider_ships', 'planet_breaker_ships'
    ]

    prev_counts = defaultdict(lambda: defaultdict(int))

    for row in data:
        house = row['house_id']
        turn = int(row['turn'])
        act = int(row.get('act', 1))

        stats[house]['ships_lost'] += int(row.get('ships_lost', 0))
        stats[house]['fighters_lost'] += int(row.get('fighters_lost', 0))
        stats[house]['colonies_lost'] += int(row.get('colonies_lost', 0))

        colonies_gained_this_turn = int(row.get('colonies_gained', 0))
        stats[house]['colonies_gained'] += colonies_gained_this_turn

        # Separate Act 1 (colonization) from Act 2+ (conquest)
        if act == 1:
            stats[house]['colonies_gained_act1'] += colonies_gained_this_turn
        else:
            stats[house]['colonies_gained_act2plus'] += colonies_gained_this_turn

        stats[house]['invasions_won'] += int(row.get('invasions_won', 0))
        stats[house]['fighters_built'] += int(row.get('fighters_gained', 0))

        # Sum ETAC construction events (etac_ships field shows builds that turn)
        etac_builds = int(row.get('etac_ships', 0))
        if etac_builds > 0:
            stats[house]['etac_construction_events'] += etac_builds

        # Track per-ship-type losses
        for ship_type in ship_types:
            current = int(row.get(ship_type, 0))
            previous = prev_counts[house][ship_type]

            if current < previous and int(row.get('ships_lost', 0)) > 0:
                decrease = previous - current
                stats[house]['ship_type_losses'][ship_type] += decrease

            prev_counts[house][ship_type] = current

    return dict(stats)

def print_etac_analysis(timeline: List[Dict], cumulative: Dict[str, Dict], data: List[Dict]):
    """Print detailed ETAC construction and utilization analysis."""
    print("\n" + "="*100)
    print("ETAC CONSTRUCTION & COLONIZATION TIMELINE")
    print("="*100)

    if not timeline:
        print("⚠️  No fleet_tracking data available - using diagnostics only")
        print("\nNote: etac_ships in diagnostics shows construction events, not concurrent count")
        return

    print(f"\n{'Turn':<6} {'Concurrent ETACs':<18} {'Colonies':<12} {'Colonization %':<16} {'Status':<20}")
    print("-" * 100)

    peak_etacs = 0
    peak_turn = 0
    threshold_80_turn = None
    threshold_90_turn = None

    for entry in timeline:
        turn = entry['turn']
        concurrent = entry['concurrent_etacs']
        colonies = entry['total_colonies']
        pct = entry['colonization_pct']

        if concurrent > peak_etacs:
            peak_etacs = concurrent
            peak_turn = turn

        status = ""
        if pct >= 80 and threshold_80_turn is None:
            threshold_80_turn = turn
            status = "← 80% threshold"
        if pct >= 90 and threshold_90_turn is None:
            threshold_90_turn = turn
            status = "← 90% reached"
        if pct >= 100:
            status = "← 100% complete"

        colony_str = f"{colonies}/{entry['total_systems']}"
        print(f"{turn:<6} {concurrent:<18} {colony_str:<12} {pct:<15.1f}% {status:<20}")

    # Summary statistics
    print("\n" + "="*100)
    print("ETAC CONSTRUCTION SUMMARY")
    print("="*100)

    print(f"\n{'Metric':<40} {'Value':<30}")
    print("-" * 100)
    print(f"{'Peak Concurrent ETACs':<40} {peak_etacs} (turn {peak_turn})")

    if threshold_80_turn:
        print(f"{'80% Colonization Reached':<40} Turn {threshold_80_turn}")
    if threshold_90_turn:
        print(f"{'90% Colonization Reached':<40} Turn {threshold_90_turn}")

    # Total construction events by house
    print(f"\n{'House':<20} {'Construction Events':<20} {'Cost (PP)':<15}")
    print("-" * 70)

    total_construction = 0
    for house in sorted(cumulative.keys()):
        construction = cumulative[house]['etac_construction_events']
        cost = construction * 25  # ETAC cost
        total_construction += construction
        short_name = house.replace('house-', '')
        print(f"{short_name:<20} {construction:<20} {cost:<15}")

    print("-" * 70)
    print(f"{'TOTAL':<20} {total_construction:<20} {total_construction * 25:<15}")

    print(f"\n{'IMPORTANT DISTINCTION':^100}")
    print("-" * 100)
    print(f"  Concurrent ETACs: Ships actively in fleets (peak: {peak_etacs})")
    print(f"  Construction Events: Cumulative builds across all turns (total: {total_construction})")
    print(f"  ")
    print(f"  Construction events > concurrent because:")
    print(f"    - ETACs colonize systems and disappear")
    print(f"    - Some ETACs are salvaged after 100% colonization")
    print(f"    - New ETACs built to replace used ones")

def print_final_fleet_composition(final_data: Dict[str, Dict], cumulative: Dict[str, Dict], max_turn: int):
    """Print detailed fleet composition table by ship type."""
    print("\n" + "="*100)
    print(f"FINAL FLEET COMPOSITION (Turn {max_turn})")
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
        ('total_fighters', 'Fighters'),
        ('etac_ships', 'ETACs (concurrent)'),
        ('troop_transport_ships', 'Transports'),
        ('scout_ships', 'Scouts'),
        ('corvette_ships', 'Corvettes'),
        ('frigate_ships', 'Frigates'),
        ('raider_ships', 'Raiders'),
        ('planet_breaker_ships', 'Planet Breakers'),
        ('total_ships', 'TOTAL SHIPS')
    ]

    houses = sorted(final_data.keys())
    print(f"{'Ship Type':<22}", end='')
    for house in houses:
        short_name = house.replace('house-', '')
        print(f"{short_name:>15}", end='')
    print(f"{'TOTAL':>15}")
    print("-" * 100)

    for col, label in ship_types:
        if label == 'TOTAL SHIPS':
            print("-" * 100)
        print(f"{label:<22}", end='')
        row_total = 0
        for house in houses:
            count = int(final_data[house].get(col, 0))
            row_total += count
            if count > 0:
                print(f"{count:>15}", end='')
            else:
                print(f"{'—':>15}", end='')
        print(f"{row_total:>15}")

def print_territorial_control(cumulative: Dict[str, Dict], final_data: Dict[str, Dict], data: List[Dict]):
    """Print territorial control and colony changes."""
    print("\n" + "="*100)
    print("TERRITORIAL CONTROL")
    print("="*100)

    total_systems_on_map = int(data[0].get('total_systems_on_map', 0))
    total_colonized = sum(int(final_data[house].get('total_colonies', 0)) for house in final_data.keys())

    print(f"Total Systems on Map: {total_systems_on_map}")
    print(f"Total Currently Colonized: {total_colonized}")
    print(f"Uncolonized Systems: {total_systems_on_map - total_colonized}")
    print(f"Colonization: {total_colonized/total_systems_on_map*100:.1f}%")
    print()

    houses = sorted(cumulative.keys())
    print(f"{'House':<20}{'Final':>8}{'Act 1':>10}{'Act 2+':>10}{'Invasions':>12}{'Lost':>8}{'Net':>8}")
    print("-" * 100)

    for house in houses:
        final_colonies = int(final_data[house].get('total_colonies', 0))
        act1_gains = cumulative[house]['colonies_gained_act1']
        act2plus_gains = cumulative[house]['colonies_gained_act2plus']
        invasions = cumulative[house]['invasions_won']
        lost = cumulative[house]['colonies_lost']
        net = (act1_gains + act2plus_gains) - lost

        short_name = house.replace('house-', '')
        net_str = f"+{net}" if net > 0 else str(net)
        print(f"{short_name:<20}{final_colonies:>8}{act1_gains:>10}{act2plus_gains:>10}{invasions:>12}{lost:>8}{net_str:>8}")

    print("\nNote: Act 1 = Land Grab (ETACs), Act 2+ = Rising Tensions+ (conquests), Invasions = won invasions")

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

    results.sort(reverse=True)

    for i, (prestige, house, short_name, treasury, production, colonies, pp_per_colony) in enumerate(results):
        rank = "👑" if i == 0 else f"#{i+1}"
        print(f"{rank:>2} {short_name:<17}{prestige:>12}{treasury:>12}{production:>12}{colonies:>10}{pp_per_colony:>11.1f}")

def main():
    parser = argparse.ArgumentParser(
        description="Detailed game analysis tool for EC4X simulations"
    )
    parser.add_argument(
        "game_seed",
        nargs="?",
        help="Game seed to analyze (e.g., 12345)"
    )
    parser.add_argument(
        "-s", "--seed",
        dest="seed_flag",
        help="Game seed to analyze (alternative to positional arg)"
    )

    args = parser.parse_args()

    # Use -s flag if provided, otherwise use positional argument
    game_seed = args.seed_flag if args.seed_flag else args.game_seed

    if not game_seed:
        parser.print_help()
        sys.exit(1)

    print(f"\n{'='*100}")
    print(f"DETAILED GAME ANALYSIS - Seed {game_seed}")
    print(f"{'='*100}")

    # Load data from SQLite
    data, conn = load_game_data_sqlite(game_seed)
    final_data = get_final_turn_data(data)
    cumulative = get_cumulative_stats(data)
    timeline = get_etac_timeline(conn)
    max_turn = max(int(row['turn']) for row in data)

    # Print all tables
    print_etac_analysis(timeline, cumulative, data)
    print_final_fleet_composition(final_data, cumulative, max_turn)
    print_territorial_control(cumulative, final_data, data)
    print_economy_and_prestige(final_data)

    conn.close()

    print("\n" + "="*100)
    print("END OF ANALYSIS")
    print("="*100 + "\n")

if __name__ == "__main__":
    main()
