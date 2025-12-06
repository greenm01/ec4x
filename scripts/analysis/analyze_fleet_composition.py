#!/usr/bin/env python3
"""
Fleet Composition Analysis Script

Analyzes ship type distribution across strategies from balance test diagnostics.
Shows detailed fleet composition breakdown and strategic patterns.

Usage:
    python3 scripts/analysis/analyze_fleet_composition.py [--games-dir DIR]

Options:
    --games-dir DIR    Path to diagnostics directory (default: balance_results/diagnostics)
"""

import polars as pl
import glob
import argparse
from pathlib import Path


def load_diagnostics(diagnostics_dir: str) -> pl.DataFrame:
    """Load all diagnostic CSV files from directory."""
    csv_files = sorted(glob.glob(f"{diagnostics_dir}/game_*.csv"))
    if not csv_files:
        raise FileNotFoundError(f"No diagnostic files found in {diagnostics_dir}")

    print(f"Loading {len(csv_files)} diagnostic files from {diagnostics_dir}...\n")

    dfs = []
    for csv_file in csv_files:
        df = pl.read_csv(csv_file)
        dfs.append(df)

    return pl.concat(dfs)


def print_strategy_breakdown(df: pl.DataFrame, strategy: str):
    """Print detailed fleet composition for a single strategy."""
    strat_data = df.filter(pl.col('strategy') == strategy)

    if len(strat_data) == 0:
        return

    ship_cols = {
        'fighter_ships': 'Fighters',
        'scout_ships': 'Scouts',
        'destroyer_ships': 'Destroyers',
        'light_cruiser_ships': 'Lt Cruisers',
        'heavy_cruiser_ships': 'Hv Cruisers',
        'battlecruiser_ships': 'Bt Cruisers',
        'battleship_ships': 'Battleships',
        'dreadnought_ships': 'Dreadnoughts',
        'super_dreadnought_ships': 'Super DNs',
        'carrier_ships': 'Carriers',
        'super_carrier_ships': 'Super CVs',
        'raider_ships': 'Raiders',
        'etac_ships': 'ETACs',
        'troop_transport_ships': 'Transports',
        'total_ships': 'TOTAL'
    }

    print(f"\n{'='*60}")
    print(f"{strategy.upper()} STRATEGY (avg over {len(strat_data)} games)")
    print(f"{'='*60}")

    has_ships = False
    for col, label in ship_cols.items():
        if col not in strat_data.columns:
            continue

        avg_val = strat_data[col].mean()

        if col == 'total_ships':
            print(f"\n{label:20s}: {avg_val:7.2f}")
        elif avg_val >= 0.05:  # Only show if average >= 0.05 ships
            print(f"  {label:20s}: {avg_val:7.2f}")
            has_ships = True

    if not has_ships:
        print("  (No significant ship types)")


def print_comparison_table(df: pl.DataFrame):
    """Print side-by-side comparison table of all strategies."""
    print("\n\n=== FLEET COMPARISON TABLE ===\n")

    ship_cols = {
        'scout_ships': 'Scouts',
        'destroyer_ships': 'Destroyers',
        'light_cruiser_ships': 'Lt Cruisers',
        'heavy_cruiser_ships': 'Hv Cruisers',
        'battlecruiser_ships': 'Bt Cruisers',
        'battleship_ships': 'Battleships',
        'dreadnought_ships': 'Dreadnoughts',
        'super_dreadnought_ships': 'Super DNs',
        'carrier_ships': 'Carriers',
        'super_carrier_ships': 'Super CVs',
        'raider_ships': 'Raiders',
        'etac_ships': 'ETACs',
        'troop_transport_ships': 'Transports',
        'total_ships': 'TOTAL'
    }

    # Build comparison data
    comparison_data = []
    for strategy in ['Aggressive', 'Balanced', 'Economic', 'Turtle']:
        strat_data = df.filter(pl.col('strategy') == strategy)
        if len(strat_data) == 0:
            continue

        row = {'Strategy': strategy}
        for col in ship_cols.keys():
            if col in strat_data.columns:
                row[col] = round(strat_data[col].mean(), 2)

        comparison_data.append(row)

    # Print header
    headers = ['Strategy', 'Scouts', 'Destroyers', 'Lt Cru', 'Hv Cru',
               'Bt Cru', 'B-ships', 'DNs', 'Super DNs', 'Carriers', 'ETACs', 'Transports', 'TOTAL']
    col_keys = ['Strategy', 'scout_ships', 'destroyer_ships', 'light_cruiser_ships',
                'heavy_cruiser_ships', 'battlecruiser_ships', 'battleship_ships',
                'dreadnought_ships', 'super_dreadnought_ships', 'carrier_ships',
                'etac_ships', 'troop_transport_ships', 'total_ships']

    print(f"{'Strategy':<12}", end='')
    for h in headers[1:]:
        print(f"{h:>10}", end='')
    print()
    print('-' * (12 + 10 * len(headers[1:])))

    # Print rows
    for row in comparison_data:
        print(f"{row['Strategy']:<12}", end='')
        for key in col_keys[1:]:
            val = row.get(key, 0.0)
            if val >= 0.05:
                print(f"{val:>10.2f}", end='')
            else:
                print(f"{'—':>10}", end='')
        print()


def print_capital_ship_analysis(df: pl.DataFrame):
    """Analyze capital ship distribution and investment."""
    print("\n\n=== CAPITAL SHIP ANALYSIS ===\n")

    capital_cols = [
        'heavy_cruiser_ships',
        'battlecruiser_ships',
        'battleship_ships',
        'dreadnought_ships',
        'super_dreadnought_ships',
        'carrier_ships',
        'super_carrier_ships'
    ]

    print(f"{'Strategy':<12} {'Total Cap':>12} {'HvCru':>8} {'BtCru':>8} {'BShip':>8} {'DN':>8} {'SuperDN':>8} {'CV':>8}")
    print('-' * 80)

    for strategy in ['Aggressive', 'Balanced', 'Economic', 'Turtle']:
        strat_data = df.filter(pl.col('strategy') == strategy)
        if len(strat_data) == 0:
            continue

        # Calculate total capital ships
        total_capital = 0
        ship_counts = {}
        for col in capital_cols:
            if col in strat_data.columns:
                val = strat_data[col].mean()
                total_capital += val
                ship_counts[col] = val
            else:
                ship_counts[col] = 0.0

        print(f"{strategy:<12} {total_capital:>12.2f}", end='')
        for col in ['heavy_cruiser_ships', 'battlecruiser_ships', 'battleship_ships',
                    'dreadnought_ships', 'super_dreadnought_ships', 'carrier_ships']:
            val = ship_counts.get(col, 0.0)
            if val >= 0.05:
                print(f"{val:>8.2f}", end='')
            else:
                print(f"{'—':>8}", end='')
        print()

    print("\nKey Insights:")
    print("  - Capital ships = Heavy Cruiser through Super Dreadnought + Carriers")
    print("  - Excludes: Fighters, Scouts, Destroyers, Light Cruisers, Raiders")


def print_role_based_analysis(df: pl.DataFrame):
    """Analyze fleet composition by ship role classification."""
    print("\n\n=== SHIP ROLE ANALYSIS ===\n")

    # Ship role classifications
    escort_cols = ['scout_ships', 'destroyer_ships', 'light_cruiser_ships']  # Corvette/Frigate missing from diagnostics
    capital_cols = ['heavy_cruiser_ships', 'battlecruiser_ships', 'battleship_ships',
                   'dreadnought_ships', 'super_dreadnought_ships', 'carrier_ships',
                   'super_carrier_ships', 'raider_ships']
    auxiliary_cols = ['etac_ships', 'troop_transport_ships']
    fighter_cols = ['fighter_ships']
    # Special weapons (planet-breakers, starbases) not tracked in current diagnostics

    print(f"{'Strategy':<12} {'Escorts':>9} {'Capitals':>10} {'Aux':>6} {'Fighters':>9} {'Total':>7}")
    print('-' * 65)

    strategies = ['Aggressive', 'Balanced', 'Economic', 'Turtle']
    for strategy in strategies:
        strat_data = df.filter(pl.col('strategy') == strategy)
        if len(strat_data) == 0:
            continue

        escorts = sum(strat_data[col].mean() for col in escort_cols if col in strat_data.columns)
        capitals = sum(strat_data[col].mean() for col in capital_cols if col in strat_data.columns)
        auxiliary = sum(strat_data[col].mean() for col in auxiliary_cols if col in strat_data.columns)
        fighters = sum(strat_data[col].mean() for col in fighter_cols if col in strat_data.columns)
        total = strat_data['total_ships'].mean() if 'total_ships' in strat_data.columns else 0.0

        print(f"{strategy:<12} {escorts:>9.1f} {capitals:>10.1f} {auxiliary:>6.1f} {fighters:>9.1f} {total:>7.1f}")

    print("\nShip Role Classifications:")
    print("  - Escort:        Combat ships with CR < 7 (Scouts, Destroyers, Light Cruisers)")
    print("  - Capital:       Flagship ships with CR >= 7 (Heavy Cruiser+, Carriers, Raiders)")
    print("  - Auxiliary:     Non-combat support (ETACs, Troop Transports)")
    print("  - Fighter:       Embarked strike craft (per-colony capacity)")
    print("  - SpecialWeapon: Not tracked in diagnostics (Planet-Breakers, Starbases)")


def print_capacity_analysis(df: pl.DataFrame):
    """Analyze capital ship capacity limits and utilization."""
    print("\n\n=== CAPACITY LIMITS & UTILIZATION ===\n")

    # Capital ship columns (CR >= 7)
    capital_cols = ['heavy_cruiser_ships', 'battlecruiser_ships', 'battleship_ships',
                   'dreadnought_ships', 'super_dreadnought_ships', 'carrier_ships',
                   'super_carrier_ships', 'raider_ships']

    # Military squadron columns (excludes fighters and auxiliary)
    escort_cols = ['scout_ships', 'destroyer_ships', 'light_cruiser_ships']
    military_cols = capital_cols + escort_cols

    print(f"{'Strategy':<12} {'Total Lim':>10} {'Total Sq':>9} {'Cap Lim':>9} {'Capitals':>9} {'Cap %':>7} {'Tot %':>7} {'IU':>7}")
    print('-' * 85)

    strategies = ['Aggressive', 'Balanced', 'Economic', 'Turtle']
    for strategy in strategies:
        strat_data = df.filter(pl.col('strategy') == strategy)
        if len(strat_data) == 0:
            continue

        # Calculate actual capital ships from ship counts
        actual_capitals = sum(strat_data[col].mean() for col in capital_cols if col in strat_data.columns)

        # Calculate total military squadrons (excludes fighters and auxiliary)
        total_squadrons = sum(strat_data[col].mean() for col in military_cols if col in strat_data.columns)

        # Get total IU for capacity calculation
        total_iu = strat_data['total_iu'].mean() if 'total_iu' in strat_data.columns else 0.0

        # Calculate capacity limits (assuming 3 rings medium map, multiplier = 1.0)
        cap_limit = max(8, int(total_iu / 100) * 2)
        total_limit = max(20, int(total_iu / 50))

        cap_utilization = (actual_capitals / cap_limit * 100) if cap_limit > 0 else 0.0
        total_utilization = (total_squadrons / total_limit * 100) if total_limit > 0 else 0.0

        print(f"{strategy:<12} {total_limit:>10.0f} {total_squadrons:>9.1f} {cap_limit:>9.0f} {actual_capitals:>9.1f} {cap_utilization:>6.1f}% {total_utilization:>6.1f}% {total_iu:>7.0f}")

    print("\nCapacity Formulas (medium map, 1.0× multiplier):")
    print("  - Total Squadron Limit: max(20, floor(Total_IU ÷ 50))")
    print("  - Capital Squadron Limit: max(8, floor(Total_IU ÷ 100) × 2)")
    print("\nKey Insights:")
    print("  - Total limit includes ALL military squadrons (escorts + capitals)")
    print("  - Capital limit is SUBSET of total limit (not additive)")
    print("  - Fighters and auxiliary ships excluded from both limits")
    print("  - Capital violations → auto-scrap (50% salvage, no grace period)")
    print("  - Total violations → auto-disband (2-turn grace, removes weakest escorts first)")


def print_production_analysis(df: pl.DataFrame):
    """Analyze production capacity vs ship building rates."""
    print("\n\n=== PRODUCTION vs SHIP BUILDING ===\n")

    # Check if production columns exist
    if 'production' not in df.columns or 'total_colonies' not in df.columns:
        print("WARNING: Production data not available in diagnostics")
        return

    print(f"{'Strategy':<12} {'Production':>11} {'Colonies':>9} {'PP/Colony':>10} {'Treasury':>10} {'Ships':>7}")
    print('-' * 69)

    strategies = ['Aggressive', 'Balanced', 'Economic', 'Turtle']
    for strategy in strategies:
        strat_data = df.filter(pl.col('strategy') == strategy)
        if len(strat_data) == 0:
            continue

        production = strat_data['production'].mean()
        colonies = strat_data['total_colonies'].mean()
        treasury = strat_data['treasury'].mean()
        ships = strat_data['total_ships'].mean()

        pp_per_colony = production / colonies if colonies > 0 else 0.0

        print(f"{strategy:<12} {production:>11.1f} {colonies:>9.1f} {pp_per_colony:>10.1f} {treasury:>10.1f} {ships:>7.1f}")

    print("\nShip Costs (from config/ships.toml):")
    print("  - Destroyer:         40 PP")
    print("  - Carrier:           80 PP")
    print("  - Battleship:       150 PP")
    print("  - Dreadnought:      200 PP")
    print("  - Super Dreadnought: 250 PP")

    print("\nUtilization Analysis:")
    for strategy in strategies:
        strat_data = df.filter(pl.col('strategy') == strategy)
        if len(strat_data) == 0:
            continue

        production = strat_data['production'].mean()
        colonies = strat_data['total_colonies'].mean()

        # Assume average ship cost ~200 PP (mix of ship types)
        avg_ship_cost = 200
        potential_ships_per_turn = production / avg_ship_cost if avg_ship_cost > 0 else 0

        # Calculate actual ships built (need turn 0 data)
        # For now, estimate based on destroyer baseline
        potential_destroyers = production / 40

        print(f"  {strategy:12s}: Could build {potential_destroyers:4.1f} Destroyers/turn OR {potential_ships_per_turn:4.1f} avg ships/turn")


def print_strategic_insights(df: pl.DataFrame):
    """Print high-level strategic insights."""
    print("\n\n=== STRATEGIC INSIGHTS ===\n")

    strategies = ['Aggressive', 'Balanced', 'Economic', 'Turtle']
    fleet_sizes = {}
    capital_counts = {}

    for strategy in strategies:
        strat_data = df.filter(pl.col('strategy') == strategy)
        if len(strat_data) == 0:
            continue

        fleet_sizes[strategy] = strat_data['total_ships'].mean()

        # Sum capital ships
        capital_cols = ['heavy_cruiser_ships', 'battlecruiser_ships', 'battleship_ships',
                       'dreadnought_ships', 'super_dreadnought_ships', 'carrier_ships', 'super_carrier_ships']
        total_cap = sum(strat_data[col].mean() for col in capital_cols if col in strat_data.columns)
        capital_counts[strategy] = total_cap

    # Find largest fleet
    max_fleet_strategy = max(fleet_sizes, key=fleet_sizes.get)
    max_fleet_size = fleet_sizes[max_fleet_strategy]

    # Calculate ratios
    print(f"1. Fleet Size Disparity:")
    for strategy in strategies:
        if strategy in fleet_sizes:
            size = fleet_sizes[strategy]
            ratio = max_fleet_size / size if size > 0 else 0
            print(f"   {strategy:12s}: {size:6.2f} ships ({ratio:4.2f}x vs {max_fleet_strategy})")

    print(f"\n2. Capital Ship Focus:")
    for strategy in strategies:
        if strategy in fleet_sizes and strategy in capital_counts:
            total = fleet_sizes[strategy]
            capitals = capital_counts[strategy]
            pct = (capitals / total * 100) if total > 0 else 0
            print(f"   {strategy:12s}: {capitals:5.2f} capitals / {total:5.2f} total ({pct:4.1f}%)")

    print(f"\n3. Standard Destroyer Count:")
    for strategy in strategies:
        strat_data = df.filter(pl.col('strategy') == strategy)
        if len(strat_data) > 0 and 'destroyer_ships' in strat_data.columns:
            destroyers = strat_data['destroyer_ships'].mean()
            print(f"   {strategy:12s}: {destroyers:5.2f} destroyers")

    print("\n4. Strategic Patterns:")
    print("   - All strategies maintain ~9 destroyers (starting fleet)")
    print("   - Super Dreadnoughts are universal endgame choice")

    if 'Aggressive' in fleet_sizes and 'Economic' in fleet_sizes:
        aggressive_size = fleet_sizes['Aggressive']
        economic_size = fleet_sizes['Economic']
        ratio = aggressive_size / economic_size if economic_size > 0 else 0
        print(f"   - Aggressive builds {ratio:.1f}x more ships than Economic")
        print(f"   - Suggests different resource allocation priorities")


def main():
    parser = argparse.ArgumentParser(
        description='Analyze fleet composition from balance test diagnostics'
    )
    parser.add_argument(
        '--games-dir',
        default='balance_results/diagnostics',
        help='Path to diagnostics directory (default: balance_results/diagnostics)'
    )

    args = parser.parse_args()

    # Load data
    df = load_diagnostics(args.games_dir)

    # Get final turn data
    final_turn = df['turn'].max()
    final_df = df.filter(pl.col('turn') == final_turn)

    print(f"=== Fleet Composition Analysis (Final Turn {final_turn}) ===\n")
    print(f"Analyzing {len(final_df)} house records from final turn")

    # Strategy-by-strategy breakdown
    for strategy in ['Aggressive', 'Balanced', 'Economic', 'Turtle']:
        print_strategy_breakdown(final_df, strategy)

    # Comparison table
    print_comparison_table(final_df)

    # Ship role analysis
    print_role_based_analysis(final_df)

    # Capital ship analysis
    print_capital_ship_analysis(final_df)

    # Capacity analysis
    print_capacity_analysis(final_df)

    # Production analysis
    print_production_analysis(final_df)

    # Strategic insights
    print_strategic_insights(final_df)

    print("\n" + "="*60)
    print("Analysis complete!")
    print("="*60)


if __name__ == '__main__':
    main()
