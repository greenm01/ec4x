#!/usr/bin/env python3
"""
Test 4-act structure across different map sizes and player counts
Tests small (4 players, 4 rings), medium (8 players, 8 rings), large (12 players, 12 rings)
"""

import json
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

# Test configurations: (numPlayers, mapRings, turnLimit, description)
TEST_CONFIGS = [
    (4, 4, 30, "Small Map (4 players, 4 rings)"),
    (8, 8, 50, "Medium Map (8 players, 8 rings)"),
    (12, 12, 80, "Large Map (12 players, 12 rings)"),
]

NUM_GAMES_PER_CONFIG = 3  # Run 3 games per configuration for quick test

# Filepaths
SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent  # since script is in scripts/


def run_simulation(num_players, turns, seed, map_rings):
    """Run a single simulation"""
    # Parameters: turns seed mapRings numPlayers
    cmd = [
        "./tests/balance/run_simulation",
        str(turns),
        str(seed),
        str(map_rings),
        str(num_players),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(PROJECT_ROOT))

    if result.returncode != 0:
        print(f"  Game failed!")
        print(result.stderr)
        return None

    # Parse results from JSON
    try:
        with open("balance_results/full_simulation.json", "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"  Failed to parse results: {e}")
        return None


def analyze_results(results, config_name):
    """Analyze a set of results for act structure"""
    print(f"\n{'=' * 70}")
    print(f"Analysis: {config_name}")
    print(f"{'=' * 70}")

    if not results:
        print("No valid results to analyze")
        return

    # Aggregate prestige progression across all games
    turn_prestige = defaultdict(list)

    for game in results:
        if "turn_snapshots" in game:
            for snapshot in game["turn_snapshots"]:
                turn = snapshot.get("turn", 0)
                for house_data in snapshot.get("houses", []):
                    prestige = house_data.get("prestige", 0)
                    turn_prestige[turn].append(prestige)

    # Calculate averages
    print("\nAverage Prestige Progression:")
    print(f"{'Turn':<8} {'Avg Prestige':<15} {'Max Prestige':<15} {'Act':<10}")
    print("-" * 60)

    for turn in sorted(turn_prestige.keys()):
        if turn_prestige[turn]:
            avg = sum(turn_prestige[turn]) / len(turn_prestige[turn])
            max_p = max(turn_prestige[turn])

            # Determine act based on turn
            total_turns = max(turn_prestige.keys())
            act = ""
            if turn <= total_turns * 0.25:
                act = "Act 1"
            elif turn <= total_turns * 0.5:
                act = "Act 2"
            elif turn <= total_turns * 0.75:
                act = "Act 3"
            else:
                act = "Act 4"

            if turn % 5 == 0 or turn == 1:  # Print every 5 turns
                print(f"{turn:<8} {avg:<15.1f} {max_p:<15.1f} {act:<10}")

    # Show final rankings
    print("\nFinal Rankings (average across games):")
    final_prestige = defaultdict(list)

    for game in results:
        if "final_rankings" in game:
            for ranking in game["final_rankings"]:
                house = ranking.get("house", "unknown")
                prestige = ranking.get("prestige", 0)
                final_prestige[house].append(prestige)

    avg_rankings = []
    for house, prestiges in final_prestige.items():
        avg = sum(prestiges) / len(prestiges)
        avg_rankings.append((house, avg))

    avg_rankings.sort(key=lambda x: x[1], reverse=True)

    for i, (house, avg_p) in enumerate(avg_rankings, 1):
        print(f"  {i}. {house}: {avg_p:.1f} prestige")


def main():
    print("=" * 70)
    print("EC4X Map Size Balance Test")
    print("Testing 4-act structure across different map sizes")
    print("=" * 70)

    all_results = {}

    for num_players, map_rings, turn_limit, description in TEST_CONFIGS:
        print(f"\n{'=' * 70}")
        print(f"Testing: {description}")
        print(f"  Players: {num_players}, Rings: {map_rings}, Turns: {turn_limit}")
        print(f"{'=' * 70}")

        config_results = []

        for game_num in range(1, NUM_GAMES_PER_CONFIG + 1):
            seed = 2000 + (map_rings * 100) + game_num
            print(f"\nRunning Game {game_num}/{NUM_GAMES_PER_CONFIG} (seed {seed})...")

            result = run_simulation(num_players, turn_limit, seed, map_rings)
            if result:
                config_results.append(result)
                print(f"  Game {game_num} completed successfully")
            else:
                print(f"  Game {game_num} failed")

        all_results[description] = config_results
        analyze_results(config_results, description)

    # Summary
    print("\n" + "=" * 70)
    print("TEST SUMMARY")
    print("=" * 70)

    for config_name, results in all_results.items():
        success_rate = (len(results) / NUM_GAMES_PER_CONFIG) * 100
        print(
            f"{config_name}: {len(results)}/{NUM_GAMES_PER_CONFIG} games ({success_rate:.0f}% success)"
        )


if __name__ == "__main__":
    main()
