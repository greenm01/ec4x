#!/usr/bin/env python3
"""Analyze diplomatic relations and dishonor mechanics for a single game

Usage:
    python3 scripts/analysis/diplomacy_analysis.py <game_seed>

Example:
    python3 scripts/analysis/diplomacy_analysis.py 99999
"""

import polars as pl
from pathlib import Path
import sys

def main():
    if len(sys.argv) < 2:
        print("Error: Game seed required", file=sys.stderr)
        print("Usage: python3 scripts/analysis/diplomacy_analysis.py <game_seed>", file=sys.stderr)
        sys.exit(1)

    game_seed = sys.argv[1]
    csv_path = Path(f"balance_results/diagnostics/game_{game_seed}.csv")

    if not csv_path.exists():
        print(f"Error: {csv_path} not found", file=sys.stderr)
        sys.exit(1)

    # Load the game data
    try:
        df = pl.read_csv(str(csv_path))
    except Exception as e:
        print(f"Error loading CSV: {e}", file=sys.stderr)
        sys.exit(1)

    # Check for required columns
    required_cols = ['turn', 'house', 'bilateral_relations']
    missing = [col for col in required_cols if col not in df.columns]
    if missing:
        print(f"Error: Missing required columns: {missing}", file=sys.stderr)
        print("This game may not have diplomatic tracking enabled", file=sys.stderr)
        sys.exit(1)

    print("=" * 80)
    print(f"DIPLOMATIC RELATIONS ANALYSIS - Game {game_seed}")
    print("=" * 80)
    print()

    # Get final turn data
    final_turn = df["turn"].max()
    final_data = df.filter(pl.col("turn") == final_turn)

    # Show final relations matrix (if we have the data)
    if "bilateral_relations" in df.columns:
        print(f"=== Final Diplomatic State (Turn {final_turn}) ===")
        print()
        relations = final_data.select(["house", "bilateral_relations"])
        for row in relations.iter_rows(named=True):
            print(f"{row['house']}: {row['bilateral_relations']}")
        print()

    # Show relation counts over time (if we have tracking columns)
    relation_cols = ['neutral_count', 'hostile_count', 'enemy_count', 'ally_count']
    if all(col in df.columns for col in relation_cols):
        print("=== Diplomatic Relations Over Time ===")
        print()
        print("Turn | House          | Neutral | Hostile | Enemy | Ally")
        print("-----|----------------|---------|---------|-------|------")

        for turn in [1, 5, 10, 15, 20, 25, 30]:
            if turn <= final_turn:
                turn_data = df.filter(pl.col("turn") == turn)
                for row in turn_data.iter_rows(named=True):
                    house = row['house'].replace('house-', '')
                    print(f"{turn:4} | {house:14s} | {row.get('neutral_count', 0):7} | "
                          f"{row.get('hostile_count', 0):7} | {row.get('enemy_count', 0):5} | "
                          f"{row.get('ally_count', 0):4}")
        print()

    # Show diplomatic actions (if tracked)
    action_cols = ['pact_formations', 'pact_breaks', 'hostility_declarations', 'war_declarations']
    if all(col in df.columns for col in action_cols):
        print("=== Diplomatic Actions Summary ===")
        print()
        actions = (
            df.group_by("house")
            .agg([
                pl.col("pact_formations").sum().alias("pacts_formed"),
                pl.col("pact_breaks").sum().alias("pacts_broken"),
                pl.col("hostility_declarations").sum().alias("hostilities"),
                pl.col("war_declarations").sum().alias("wars")
            ])
            .sort("wars", descending=True)
        )

        print("House          | Pacts Formed | Pacts Broken | Hostilities | Wars")
        print("---------------|--------------|--------------|-------------|------")
        for row in actions.iter_rows(named=True):
            house = row['house'].replace('house-', '')
            print(f"{house:14s} | {row['pacts_formed']:12} | {row['pacts_broken']:12} | "
                  f"{row['hostilities']:11} | {row['wars']:4}")
        print()

    # Show dishonor tracking (if available)
    if 'dishonor_score' in df.columns:
        print("=== Dishonor Progression ===")
        print()
        dishonor_progression = df.select(["turn", "house", "dishonor_score"])
        print(dishonor_progression.filter(pl.col("dishonor_score") > 0))
        print()

    print("=" * 80)

if __name__ == "__main__":
    main()
