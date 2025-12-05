#!/usr/bin/env python3
"""
Parallel balance test runner for EC4X
Runs multiple game simulations in parallel for maximum CPU utilization

Usage:
    python3 run_balance_test_parallel.py [--workers N] [--games N] [--turns N]

Examples:
    python3 run_balance_test_parallel.py --workers 4 --games 100 --turns 7    # Phase 2A: Act 1
    python3 run_balance_test_parallel.py --workers 8 --games 200 --turns 15   # Phase 2B: Act 2
    python3 run_balance_test_parallel.py --workers 8 --games 200 --turns 25   # Phase 2C: Act 3
    python3 run_balance_test_parallel.py --workers 8 --games 200 --turns 30   # Phase 2D: Full game
"""

import argparse
import json
import multiprocessing as mp
import subprocess
import sys
import time
from collections import defaultdict
from datetime import datetime
from pathlib import Path

# Configuration defaults
DEFAULT_WORKERS = 8
DEFAULT_GAMES = 200
DEFAULT_TURNS = 100
STRATEGIES = ["Aggressive", "Economic", "Balanced", "Turtle"]

# Filepaths
SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent  # since script is in scripts/


def run_single_game(seed, turns_per_game, map_rings=3, num_players=4):
    """Run a single game simulation with given seed"""
    output_file = f"balance_results/game_{seed}.json"
    cmd = [
        "./bin/run_simulation",
        "--turns", str(turns_per_game),
        "--seed", str(seed),
        "--map-rings", str(map_rings),
        "--players", str(num_players),
        "--output", output_file
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(PROJECT_ROOT))

    if result.returncode != 0:
        print(f"[ERROR] Game {seed} failed with return code {result.returncode}")
        if result.stderr:
            print(f"[ERROR] stderr: {result.stderr[:500]}")
        if result.stdout:
            print(f"[ERROR] stdout: {result.stdout[-500:]}")
        return None

    # Parse final rankings from JSON file (robust, not stdout parsing)
    try:
        json_path = PROJECT_ROOT / output_file
        with open(json_path, "r") as f:
            game_data = json.load(f)

        # Extract rankings from JSON outcome section
        rankings = {}
        if "outcome" in game_data and "final_rankings" in game_data["outcome"]:
            for ranking in game_data["outcome"]["final_rankings"]:
                house = ranking.get("house_id", "")
                prestige = ranking.get("final_prestige", 0)
                if house:
                    rankings[house] = prestige
        # Fallback: check top-level final_rankings (older format)
        elif "final_rankings" in game_data:
            for ranking in game_data["final_rankings"]:
                house = ranking.get("house_id", "")
                prestige = ranking.get("final_prestige", 0)
                if house:
                    rankings[house] = prestige

        return rankings if len(rankings) > 0 else None
    except Exception as e:
        # If JSON parsing fails, return None
        print(f"[ERROR] Game {seed} JSON parsing failed: {e}")
        return None


def run_game_batch(args):
    """Run a batch of games in this worker process"""
    batch_id, games_per_batch, start_seed, turns_per_game, map_rings, num_players = args
    print(
        f"Batch {batch_id}: Starting {games_per_batch} games (seeds {start_seed}-{start_seed + games_per_batch - 1})"
    )

    results = []
    for i in range(games_per_batch):
        seed = start_seed + i
        rankings = run_single_game(seed, turns_per_game, map_rings, num_players)
        if rankings:
            results.append(rankings)
            print(f"Batch {batch_id}: Game {seed} succeeded - {len(rankings)} houses")
        else:
            print(f"Batch {batch_id}: Game {seed} FAILED - no rankings")

        # Progress update every 10 games
        if (i + 1) % 10 == 0:
            print(f"Batch {batch_id}: Completed {i + 1}/{games_per_batch} games")

    print(f"Batch {batch_id}: Completed all {games_per_batch} games - {len(results)} successful")
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
        "games_played": games_played,
        "win_counts": dict(win_counts),
        "prestige_totals": dict(prestige_totals),
        "collapse_counts": dict(collapse_counts),
    }


def print_summary(stats):
    """Print comprehensive summary statistics"""
    games = stats["games_played"]

    print("\n" + "=" * 70)
    print("PARALLEL BALANCE TEST SUMMARY")
    print("=" * 70)
    print(f"Total Games: {games}")
    print(f"Strategies: {', '.join(STRATEGIES)}")
    print("=" * 70)

    # Sort by average prestige
    houses = list(stats["prestige_totals"].keys())
    houses.sort(key=lambda h: stats["prestige_totals"][h] / games, reverse=True)

    print("\nSTRATEGY PERFORMANCE:")
    print("-" * 70)
    print(f"{'House':<20} {'Avg Prestige':<15} {'Win Rate':<15} {'Collapses'}")
    print("-" * 70)

    for house in houses:
        avg_prestige = stats["prestige_totals"][house] / games
        win_count = stats["win_counts"].get(house, 0)
        win_rate = (win_count / games * 100) if games > 0 else 0
        collapses = stats["collapse_counts"].get(house, 0)
        collapse_rate = (collapses / games * 100) if games > 0 else 0

        print(
            f"{house:<20} {avg_prestige:>7.1f}        {win_count:>2} ({win_rate:>5.1f}%)    {collapses:>2} ({collapse_rate:>4.1f}%)"
        )

    print("=" * 70)

    # Strategy mapping
    strategy_map = {
        "house-ordos": "Aggressive",
        "house-atreides": "Economic",
        "house-corrino": "Balanced",
        "house-harkonnen": "Turtle",
    }

    print("\nSTRATEGY ANALYSIS:")
    print("-" * 70)
    for house in houses:
        strategy = strategy_map.get(house, "Unknown")
        avg_prestige = stats["prestige_totals"][house] / games
        win_count = stats["win_counts"].get(house, 0)
        collapses = stats["collapse_counts"].get(house, 0)

        status = "✅" if collapses == 0 else "⚠️"
        dominance = ""
        if win_count / games > 0.35:
            dominance = " (DOMINANT)"
        elif win_count / games < 0.15:
            dominance = " (WEAK)"

        print(
            f"{status} {strategy:<12} {house:<20} {avg_prestige:>6.1f} avg{dominance}"
        )

    print("=" * 70)


def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(description="EC4X Parallel Balance Test Runner")
    parser.add_argument(
        "--workers",
        type=int,
        default=DEFAULT_WORKERS,
        help=f"Number of parallel workers (default: {DEFAULT_WORKERS})",
    )
    parser.add_argument(
        "--games",
        type=int,
        default=DEFAULT_GAMES,
        help=f"Total number of games to run (default: {DEFAULT_GAMES})",
    )
    parser.add_argument(
        "--turns",
        type=int,
        default=DEFAULT_TURNS,
        help=f"Number of turns per game (default: {DEFAULT_TURNS})",
    )
    parser.add_argument(
        "--rings",
        type=int,
        default=3,
        help="Number of hex rings for map size (default: 3, small=3, medium=4, large=5)",
    )
    parser.add_argument(
        "--players", type=int, default=4, help="Number of players (default: 4)"
    )
    args = parser.parse_args()

    num_parallel = args.workers
    total_games = args.games
    turns_per_game = args.turns
    map_rings = args.rings
    num_players = args.players
    games_per_worker = total_games // num_parallel

    print("=" * 70)
    print("EC4X PARALLEL BALANCE TEST")
    print("=" * 70)
    print(f"Parallel workers: {num_parallel}")
    print(f"Games per worker: {games_per_worker}")
    print(f"Total games: {total_games}")
    print(f"Turns per game: {turns_per_game}")
    print(f"Strategies: {', '.join(STRATEGIES)}")
    print("=" * 70)
    print()

    start_time = time.time()

    # Create work batches with unique seeds
    base_seed = 2000  # Start from 2000 to avoid conflicts with sequential tests
    batches = []
    for i in range(num_parallel):
        batch_id = i + 1
        start_seed = base_seed + (i * games_per_worker)
        batches.append(
            (
                batch_id,
                games_per_worker,
                start_seed,
                turns_per_game,
                map_rings,
                num_players,
            )
        )

    # Run batches in parallel using multiprocessing
    print(f"Starting {num_parallel} parallel workers...\n")
    with mp.Pool(processes=num_parallel) as pool:
        batch_results = pool.map(run_game_batch, batches)

    # Flatten results from all batches
    all_results = []
    for batch in batch_results:
        all_results.extend(batch)

    elapsed_time = time.time() - start_time

    print(f"\n{'=' * 70}")
    print(f"All workers completed in {elapsed_time:.1f} seconds")
    if len(all_results) > 0:
        print(f"Average time per game: {elapsed_time / len(all_results):.2f} seconds")
    print(f"{'=' * 70}")

    # Aggregate and print results
    stats = aggregate_results(all_results)
    print_summary(stats)

    # Save detailed results to JSON
    output_dir = Path("balance_results")
    output_dir.mkdir(exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = output_dir / f"parallel_test_{timestamp}.json"

    output_data = {
        "metadata": {
            "timestamp": timestamp,
            "num_parallel": num_parallel,
            "games_per_worker": games_per_worker,
            "total_games": total_games,
            "turns_per_game": turns_per_game,
            "elapsed_seconds": elapsed_time,
            "strategies": STRATEGIES,
        },
        "statistics": stats,
        "raw_results": all_results,
    }

    with open(output_file, "w") as f:
        json.dump(output_data, f, indent=2)

    print(f"\nDetailed results saved to: {output_file}")


if __name__ == "__main__":
    main()
