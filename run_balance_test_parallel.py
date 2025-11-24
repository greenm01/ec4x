#!/usr/bin/env python3
"""
Parallel balance test runner for EC4X
Runs multiple game simulations in parallel for maximum CPU utilization

Usage:
    python3 run_balance_test_parallel.py [num_parallel] [games_per_run]

Examples:
    python3 run_balance_test_parallel.py 4 25    # 4 parallel runs of 25 games = 100 total
    python3 run_balance_test_parallel.py 8 10    # 8 parallel runs of 10 games = 80 total
    python3 run_balance_test_parallel.py 10 50   # 10 parallel runs of 50 games = 500 total
"""

import subprocess
import sys
import json
import multiprocessing as mp
from pathlib import Path
from collections import defaultdict
from datetime import datetime
import time

# Configuration
DEFAULT_PARALLEL = 4
DEFAULT_GAMES = 25
TURNS_PER_GAME = 100
STRATEGIES = ["Aggressive", "Economic", "Balanced", "Turtle"]

def run_single_game(seed):
    """Run a single game simulation with given seed"""
    cmd = ["./tests/balance/run_simulation", str(TURNS_PER_GAME), str(seed)]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd="/home/niltempus/dev/ec4x")

    if result.returncode != 0:
        return None

    # Parse final rankings from output
    lines = result.stdout.split('\n')
    rankings = {}
    parsing_rankings = False

    for line in lines:
        if "Final Rankings:" in line:
            parsing_rankings = True
            continue
        if parsing_rankings and line.strip() and line.strip()[0].isdigit():
            parts = line.split(":")
            if len(parts) >= 2:
                house = parts[0].split(".")[1].strip()
                prestige_str = parts[1].strip().split()[0]
                try:
                    prestige = int(prestige_str)
                    rankings[house] = prestige
                except ValueError:
                    continue
            if len(rankings) == 4:
                break

    return rankings if len(rankings) == 4 else None

def run_game_batch(batch_id, games_per_batch, start_seed):
    """Run a batch of games in this worker process"""
    print(f"Batch {batch_id}: Starting {games_per_batch} games (seeds {start_seed}-{start_seed+games_per_batch-1})")

    results = []
    for i in range(games_per_batch):
        seed = start_seed + i
        rankings = run_single_game(seed)
        if rankings:
            results.append(rankings)

        # Progress update every 10 games
        if (i + 1) % 10 == 0:
            print(f"Batch {batch_id}: Completed {i+1}/{games_per_batch} games")

    print(f"Batch {batch_id}: Completed all {games_per_batch} games")
    return results

def aggregate_results(all_results):
    """Aggregate results from all parallel runs"""
    win_counts = defaultdict(int)
    prestige_totals = defaultdict(int)
    collapse_counts = defaultdict(int)
    games_played = len(all_results)

    for rankings in all_results:
        # Winner is highest prestige
        winner = max(rankings, key=rankings.get)
        win_counts[winner] += 1

        for house, prestige in rankings.items():
            prestige_totals[house] += prestige
            if prestige < 0:
                collapse_counts[house] += 1

    return {
        'games_played': games_played,
        'win_counts': dict(win_counts),
        'prestige_totals': dict(prestige_totals),
        'collapse_counts': dict(collapse_counts)
    }

def print_summary(stats):
    """Print comprehensive summary statistics"""
    games = stats['games_played']

    print("\n" + "="*70)
    print("PARALLEL BALANCE TEST SUMMARY")
    print("="*70)
    print(f"Total Games: {games}")
    print(f"Strategies: {', '.join(STRATEGIES)}")
    print("="*70)

    # Sort by average prestige
    houses = list(stats['prestige_totals'].keys())
    houses.sort(key=lambda h: stats['prestige_totals'][h] / games, reverse=True)

    print("\nSTRATEGY PERFORMANCE:")
    print("-" * 70)
    print(f"{'House':<20} {'Avg Prestige':<15} {'Win Rate':<15} {'Collapses'}")
    print("-" * 70)

    for house in houses:
        avg_prestige = stats['prestige_totals'][house] / games
        win_count = stats['win_counts'].get(house, 0)
        win_rate = (win_count / games * 100) if games > 0 else 0
        collapses = stats['collapse_counts'].get(house, 0)
        collapse_rate = (collapses / games * 100) if games > 0 else 0

        print(f"{house:<20} {avg_prestige:>7.1f}        {win_count:>2} ({win_rate:>5.1f}%)    {collapses:>2} ({collapse_rate:>4.1f}%)")

    print("="*70)

    # Strategy mapping
    strategy_map = {
        'house-ordos': 'Aggressive',
        'house-atreides': 'Economic',
        'house-corrino': 'Balanced',
        'house-harkonnen': 'Turtle'
    }

    print("\nSTRATEGY ANALYSIS:")
    print("-" * 70)
    for house in houses:
        strategy = strategy_map.get(house, 'Unknown')
        avg_prestige = stats['prestige_totals'][house] / games
        win_count = stats['win_counts'].get(house, 0)
        collapses = stats['collapse_counts'].get(house, 0)

        status = "✅" if collapses == 0 else "⚠️"
        dominance = ""
        if win_count / games > 0.35:
            dominance = " (DOMINANT)"
        elif win_count / games < 0.15:
            dominance = " (WEAK)"

        print(f"{status} {strategy:<12} {house:<20} {avg_prestige:>6.1f} avg{dominance}")

    print("="*70)

def main():
    # Parse command line arguments
    num_parallel = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PARALLEL
    games_per_run = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_GAMES

    total_games = num_parallel * games_per_run

    print("="*70)
    print("EC4X PARALLEL BALANCE TEST")
    print("="*70)
    print(f"Parallel workers: {num_parallel}")
    print(f"Games per worker: {games_per_run}")
    print(f"Total games: {total_games}")
    print(f"Strategies: {', '.join(STRATEGIES)}")
    print("="*70)
    print()

    start_time = time.time()

    # Create work batches with unique seeds
    base_seed = 2000  # Start from 2000 to avoid conflicts with sequential tests
    batches = []
    for i in range(num_parallel):
        batch_id = i + 1
        start_seed = base_seed + (i * games_per_run)
        batches.append((batch_id, games_per_run, start_seed))

    # Run batches in parallel using multiprocessing
    print(f"Starting {num_parallel} parallel workers...\n")
    with mp.Pool(processes=num_parallel) as pool:
        batch_results = pool.starmap(run_game_batch, batches)

    # Flatten results from all batches
    all_results = []
    for batch in batch_results:
        all_results.extend(batch)

    elapsed_time = time.time() - start_time

    print(f"\n{'='*70}")
    print(f"All workers completed in {elapsed_time:.1f} seconds")
    print(f"Average time per game: {elapsed_time / len(all_results):.2f} seconds")
    print(f"{'='*70}")

    # Aggregate and print results
    stats = aggregate_results(all_results)
    print_summary(stats)

    # Save detailed results to JSON
    output_dir = Path("balance_results")
    output_dir.mkdir(exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = output_dir / f"parallel_test_{timestamp}.json"

    output_data = {
        'metadata': {
            'timestamp': timestamp,
            'num_parallel': num_parallel,
            'games_per_worker': games_per_run,
            'total_games': total_games,
            'elapsed_seconds': elapsed_time,
            'strategies': STRATEGIES
        },
        'statistics': stats,
        'raw_results': all_results
    }

    with open(output_file, 'w') as f:
        json.dump(output_data, f, indent=2)

    print(f"\nDetailed results saved to: {output_file}")

if __name__ == "__main__":
    main()
