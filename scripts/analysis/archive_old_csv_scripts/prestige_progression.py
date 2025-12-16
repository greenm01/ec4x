#!/usr/bin/env python3
"""Analyze prestige progression for a single game

Usage:
    python3 scripts/analysis/prestige_progression.py <game_seed>

Example:
    python3 scripts/analysis/prestige_progression.py 99999
"""

import polars as pl
from pathlib import Path
import sys

def main():
    if len(sys.argv) < 2:
        print("Error: Game seed required", file=sys.stderr)
        print("Usage: python3 scripts/analysis/prestige_progression.py <game_seed>", file=sys.stderr)
        sys.exit(1)

    game_seed = sys.argv[1]
    csv_path = Path(f"balance_results/diagnostics/game_{game_seed}.csv")

    if not csv_path.exists():
        print(f"Error: {csv_path} not found", file=sys.stderr)
        sys.exit(1)

    try:
        df = pl.read_csv(str(csv_path))
    except Exception as e:
        print(f"Error loading CSV: {e}", file=sys.stderr)
        sys.exit(1)

    print("=" * 80)
    print(f"PRESTIGE PROGRESSION ANALYSIS - Game {game_seed}")
    print("=" * 80)
    print()

    # Get prestige progression for each house
    prestige_data = df.select(["turn", "house", "strategy", "prestige", "rank"])

    print("=== Prestige Over Time ===")
    print()

    # Show every 5 turns
    max_turn = df["turn"].max()
    display_turns = list(range(1, max_turn + 1, 5))
    if max_turn not in display_turns:
        display_turns.append(max_turn)

    print("Turn | House          | Strategy   | Prestige | Rank")
    print("-----|----------------|------------|----------|------")

    for turn in display_turns:
        turn_data = prestige_data.filter(pl.col("turn") == turn).sort("prestige", descending=True)
        for row in turn_data.iter_rows(named=True):
            house = row['house'].replace('house-', '')
            strategy = row['strategy']
            prestige = row['prestige']
            rank = row.get('rank', '?')
            print(f"{turn:4} | {house:14s} | {strategy:10s} | {prestige:8} | {rank:4}")
        if turn < display_turns[-1]:
            print("     |                |            |          |")

    print()

    # Show final standings
    final_turn = df["turn"].max()
    final_data = df.filter(pl.col("turn") == final_turn).sort("prestige", descending=True)

    print("=== Final Standings ===")
    print()
    print("Rank | House          | Strategy   | Prestige")
    print("-----|----------------|------------|----------")

    for idx, row in enumerate(final_data.iter_rows(named=True), 1):
        house = row['house'].replace('house-', '')
        strategy = row['strategy']
        prestige = row['prestige']
        print(f"{idx:4} | {house:14s} | {strategy:10s} | {prestige:8}")

    print()

    # Show prestige gain/loss by house
    first_turn = df.filter(pl.col("turn") == 1)
    last_turn = df.filter(pl.col("turn") == final_turn)

    print("=== Prestige Change ===")
    print()
    print("House          | Start | End   | Change")
    print("---------------|-------|-------|--------")

    for house in df["house"].unique():
        start = first_turn.filter(pl.col("house") == house)["prestige"][0]
        end = last_turn.filter(pl.col("house") == house)["prestige"][0]
        change = end - start
        change_str = f"+{change}" if change > 0 else str(change)
        house_short = house.replace('house-', '')
        print(f"{house_short:14s} | {start:5} | {end:5} | {change_str:>7}")

    print()
    print("=" * 80)

if __name__ == "__main__":
    main()
