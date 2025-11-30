#!/usr/bin/env python3
"""
Analyze when a clear winner emerges in a 4-player game
Identifies the turn when the winner's lead becomes statistically significant
Uses polars for efficient data analysis
"""

import sys
from pathlib import Path
import polars as pl

def analyze_winner_emergence(df):
    """Determine when winner becomes clear"""
    houses = ['house-corrino', 'house-atreides', 'house-harkonnen', 'house-ordos']

    print("=" * 80)
    print("WINNER EMERGENCE ANALYSIS")
    print("=" * 80)
    print()

    # Get prestige by turn and house
    prestige_df = df.select(['turn', 'house', 'prestige']).sort('turn')

    # Pivot to wide format for easier comparison
    prestige_wide = prestige_df.pivot(
        values='prestige',
        index='turn',
        columns='house'
    ).sort('turn')

    print("PRESTIGE PROGRESSION:")
    print("-" * 80)
    print(f"{'Turn':>4} | {'Corrino':>8} | {'Atreides':>8} | {'Harkonnen':>8} | {'Ordos':>8} | {'Leader':>10} | Lead")
    print("-" * 80)

    winner_emergence_turn = None
    consecutive_leads = {house: 0 for house in houses}

    for row in prestige_wide.iter_rows(named=True):
        turn = row['turn']

        # Get prestige scores
        scores = {house: row.get(house, 0) for house in houses}

        # Find leader
        leader = max(scores, key=scores.get)
        lead_value = scores[leader]
        sorted_scores = sorted(scores.values(), reverse=True)
        second_value = sorted_scores[1] if len(sorted_scores) > 1 else 0
        lead_margin = lead_value - second_value
        lead_pct = (lead_margin / second_value * 100) if second_value > 0 else 0

        # Display row
        print(f"{turn:4d} | {scores['house-corrino']:8.0f} | " +
              f"{scores['house-atreides']:8.0f} | " +
              f"{scores['house-harkonnen']:8.0f} | " +
              f"{scores['house-ordos']:8.0f} | " +
              f"{leader.replace('house-', '').capitalize():>10s} | +{lead_pct:5.1f}%")

        # Track consecutive leads
        consecutive_leads[leader] += 1
        for house in houses:
            if house != leader:
                consecutive_leads[house] = 0

        # Winner becomes "clear" when they have:
        # 1. 15%+ lead over second place AND
        # 2. Led for 3+ consecutive turns
        if (winner_emergence_turn is None and
            lead_pct >= 15.0 and
            consecutive_leads[leader] >= 3):
            winner_emergence_turn = turn

    print("-" * 80)
    print()

    if winner_emergence_turn:
        print(f"WINNER BECAME CLEAR: Turn {winner_emergence_turn}")
        print(f"  (15%+ lead sustained for 3+ turns)")
    else:
        print("WINNER NOT YET CLEAR: No house achieved decisive lead")

    print()
    return winner_emergence_turn, prestige_wide

def analyze_key_metrics(df, emergence_turn, prestige_wide):
    """Analyze key metrics at winner emergence point"""
    if not emergence_turn:
        return

    print("=" * 80)
    print(f"KEY METRICS AT WINNER EMERGENCE (Turn {emergence_turn}):")
    print("=" * 80)
    print()

    # Get data for emergence turn
    turn_data = df.filter(pl.col('turn') == emergence_turn)

    metrics_to_analyze = [
        ('total_colonies', 'Colonies'),
        ('total_population', 'Population'),
        ('total_production_capacity', 'Production Capacity'),
        ('total_ships', 'Total Ships'),
        ('total_squadrons', 'Squadrons'),
        ('total_military_power', 'Military Power'),
        ('research_el_level', 'EL Tech'),
        ('research_sl_level', 'SL Tech'),
        ('research_cst_level', 'CST Tech'),
        ('line_squadrons', 'Line Squadrons (Capitals)'),
        ('screen_squadrons', 'Screen Squadrons (Escorts)'),
        ('total_shipyards', 'Shipyards'),
        ('total_spaceports', 'Spaceports'),
        ('total_dock_capacity', 'Total Dock Capacity'),
        ('dock_utilization', 'Dock Utilization %'),
    ]

    for metric_key, metric_name in metrics_to_analyze:
        if metric_key not in turn_data.columns:
            continue

        print(f"{metric_name}:")
        metric_data = turn_data.select(['house', metric_key]).sort('house')

        for row in metric_data.iter_rows(named=True):
            house_name = row['house'].replace('house-', '').capitalize()
            value = row[metric_key]
            print(f"  {house_name:>10s}: {value:8.0f}")

        # Find leader
        leader_row = metric_data.sort(metric_key, descending=True).row(0, named=True)
        leader_name = leader_row['house'].replace('house-', '').capitalize()
        print(f"  {'Leader':>10s}: {leader_name}")
        print()

def analyze_metric_trends(df, prestige_wide):
    """Analyze how key metrics evolved over time"""
    print("=" * 80)
    print("METRIC TREND ANALYSIS")
    print("=" * 80)
    print()

    # Get winner from final turn
    final_turn = prestige_wide['turn'].max()
    final_row = prestige_wide.filter(pl.col('turn') == final_turn).row(0, named=True)
    houses = ['house-corrino', 'house-atreides', 'house-harkonnen', 'house-ordos']
    winner = max(houses, key=lambda h: final_row.get(h, 0))

    print(f"Winner: {winner.replace('house-', '').capitalize()}")
    print()

    # Analyze when winner took the lead in each category
    metrics = [
        ('total_colonies', 'Colonies'),
        ('total_military_power', 'Military Power'),
        ('total_production_capacity', 'Production'),
        ('research_el_level', 'EL Tech'),
    ]

    for metric_key, metric_name in metrics:
        if metric_key not in df.columns:
            continue

        # Get metric by turn
        metric_df = df.select(['turn', 'house', metric_key]).sort('turn')
        metric_wide = metric_df.pivot(
            values=metric_key,
            index='turn',
            columns='house'
        ).sort('turn')

        # Find first turn where winner took lead
        first_lead = None
        for row in metric_wide.iter_rows(named=True):
            turn = row['turn']
            scores = {house: row.get(house, 0) for house in houses}
            leader = max(scores, key=scores.get)
            if leader == winner:
                first_lead = turn
                break

        if first_lead:
            print(f"{metric_name}: {winner.replace('house-', '').capitalize()} " +
                  f"took lead on turn {first_lead}")
        else:
            print(f"{metric_name}: {winner.replace('house-', '').capitalize()} " +
                  f"never led")

    print()

def analyze_final_outcome(df):
    """Analyze final game state"""
    final_turn = df['turn'].max()
    final_data = df.filter(pl.col('turn') == final_turn).sort('prestige', descending=True)

    print("=" * 80)
    print(f"FINAL OUTCOME (Turn {final_turn}):")
    print("=" * 80)
    print()

    for rank, row in enumerate(final_data.iter_rows(named=True), 1):
        house_name = row['house'].replace('house-', '').capitalize()
        prestige = row['prestige']
        status = "WINNER" if rank == 1 else f"#{rank}"
        print(f"{status:>8s}: {house_name:>10s} = {prestige:8.0f} prestige")

        # Show key stats
        print(f"           Colonies: {row.get('total_colonies', 0):.0f}, " +
              f"Population: {row.get('total_population', 0):.0f}, " +
              f"Ships: {row.get('total_ships', 0):.0f}, " +
              f"Military: {row.get('total_military_power', 0):.0f}")

    print()

def main():
    csv_path = Path("balance_results/diagnostics/game_12345.csv")

    if not csv_path.exists():
        print(f"Error: CSV file not found: {csv_path}")
        sys.exit(1)

    print(f"Loading game data from {csv_path}...")
    df = pl.read_csv(csv_path)
    print(f"Loaded {df['turn'].n_unique()} turns, {df.height} total rows")
    print()

    emergence_turn, prestige_wide = analyze_winner_emergence(df)
    print()
    analyze_key_metrics(df, emergence_turn, prestige_wide)
    print()
    analyze_metric_trends(df, prestige_wide)
    print()
    analyze_final_outcome(df)

if __name__ == "__main__":
    main()
