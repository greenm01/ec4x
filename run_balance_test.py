#!/usr/bin/env python3
"""
Simple balance test runner for EC4X M3+ features
Runs multiple games with different strategy matchups

VICTORY CONDITIONS (per victory.md):
1. Elimination Victory: Be the last house standing (all others eliminated)
2. Prestige Victory: Have highest prestige at turn limit (default 200 turns)

Prestige is gained by:
- Controlling colonies (+1 per turn per colony)
- Having high population
- Technological advancement
- Diplomatic relations
- Military strength

Prestige is lost by:
- Treaty violations
- Losing colonies
- Being diplomatically isolated
- Failed invasions

The genetic algorithm evolves AI personalities based on win rate and prestige
performance, since those directly determine victory.
"""

import subprocess
import json
import sys
from pathlib import Path
from collections import defaultdict

# Configuration
NUM_GAMES = 10
TURNS_PER_GAME = 100
STRATEGIES = ["Aggressive", "Economic", "Balanced", "Turtle"]

def run_game(game_num):
    """Run a single game simulation"""
    print(f"\n{'='*70}")
    print(f"Running Game {game_num}/{NUM_GAMES}")
    print(f"{'='*70}")

    cmd = ["./tests/balance/run_simulation", str(TURNS_PER_GAME)]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd="/home/niltempus/dev/ec4x")

    if result.returncode != 0:
        print(f"Game {game_num} failed!")
        print(result.stderr)
        return None

    # Parse final rankings from output
    lines = result.stdout.split('\n')
    rankings = {}
    parsing_rankings = False

    for line in lines:
        if "Final Rankings:" in line:
            parsing_rankings = True
            continue
        if parsing_rankings and line.strip().startswith(str(len(rankings) + 1) + "."):
            parts = line.split(":")
            if len(parts) >= 2:
                house = parts[0].split(".")[1].strip()
                prestige_str = parts[1].strip().split()[0]
                prestige = int(prestige_str)
                rankings[house] = prestige
            if len(rankings) == 4:
                break

    return rankings

def main():
    print("="*70)
    print("EC4X M3+ Balance Test")
    print("="*70)
    print(f"Running {NUM_GAMES} games with {TURNS_PER_GAME} turns each")
    print(f"Strategies: {', '.join(STRATEGIES)}")
    print("="*70)

    # Track results
    win_counts = defaultdict(int)
    prestige_totals = defaultdict(int)
    games_played = 0

    for game_num in range(1, NUM_GAMES + 1):
        rankings = run_game(game_num)

        if rankings:
            games_played += 1
            # Winner is first in rankings (highest prestige)
            winner = max(rankings, key=rankings.get)
            win_counts[winner] += 1

            for house, prestige in rankings.items():
                prestige_totals[house] += prestige

            print(f"\nGame {game_num} Results:")
            for i, (house, prestige) in enumerate(sorted(rankings.items(), key=lambda x: x[1], reverse=True), 1):
                print(f"  {i}. {house}: {prestige} prestige")

    # Print summary
    print("\n" + "="*70)
    print("BALANCE TEST SUMMARY")
    print("="*70)
    print(f"Games Completed: {games_played}/{NUM_GAMES}\n")

    print("Win Counts:")
    for house in sorted(win_counts, key=win_counts.get, reverse=True):
        pct = (win_counts[house] / games_played * 100) if games_played > 0 else 0
        print(f"  {house:20} {win_counts[house]:2} wins ({pct:5.1f}%)")

    print("\nAverage Prestige:")
    for house in sorted(prestige_totals, key=prestige_totals.get, reverse=True):
        avg = prestige_totals[house] / games_played if games_played > 0 else 0
        print(f"  {house:20} {avg:6.1f}")

    print("="*70)

if __name__ == "__main__":
    main()
