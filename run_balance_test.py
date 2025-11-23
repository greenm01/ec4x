#!/usr/bin/env python3
"""
Simple balance test runner for EC4X M3+ features
Runs multiple games with different strategy matchups

VICTORY CONDITIONS (config/prestige.toml):
1. Elimination Victory: Be the last house standing
2. Prestige Victory: Highest prestige at turn limit (or reach 5000)

PRESTIGE GAINS (config/prestige.toml):
Economic:
- Colony established (+5), max population (+3), IU milestones (+1 to +5)
- Tech advancement (+2), terraform planet (+5)
- Low tax rates (+1 to +3 per colony for 0-30% tax)

Military:
- Invade planet (+10), system capture (+10), eliminate house (+3)
- Fleet victory (+3), force retreat (+2), destroy starbase (+5)
- Destroy squadron (+1 per ship)

Espionage:
- Scout missions (+1 to +2), successful operations (+1 to +5)

Diplomacy:
- Form non-aggression pact (+5), attack dishonored house (+1)

PRESTIGE LOSSES (config/prestige.toml):
- Lose planet (-10), lose starbase (-5)
- Pact violation (-10), repeat violation (-10 additional)
- Failed espionage (-2), scout destroyed (-3)
- Being espionage victim (-1 to -7 depending on operation)
- High tax rates (-1 to -11 per turn for 51-100% tax)
- Maintenance shortfall (-5 turn 1, increasing by -2 each turn)
- Blockaded colonies (-2 per colony per turn)
- Espionage over-investment (-1 per 1% over 5% threshold)

The genetic algorithm evolves AI personalities based on win rate and prestige
performance, since those directly determine victory.
"""

import subprocess
import json
import sys
import shutil
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

    # Clean up old balance results to prevent junk accumulation
    balance_results_dir = Path("/home/niltempus/dev/ec4x/balance_results")
    if balance_results_dir.exists():
        print(f"\nCleaning up old balance results from {balance_results_dir}...")
        shutil.rmtree(balance_results_dir)
        print("✓ Old results removed")

    print()

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
