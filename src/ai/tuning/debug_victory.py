#!/usr/bin/env python3
"""
Debug Victory Scoring
Investigate why victory analysis shows almost no wins
"""

import polars as pl
from pathlib import Path
import sys

def main():
    diagnostics_dir = Path("balance_results/diagnostics")
    csv_files = sorted(diagnostics_dir.glob("game_*.csv"))

    if not csv_files:
        print("❌ No diagnostic CSV files found")
        sys.exit(1)

    print(f"📊 Analyzing {len(csv_files)} games...\n")

    # Read all CSV files
    dfs = []
    for csv_file in csv_files:
        try:
            df = pl.read_csv(csv_file)
            # Add game_id from filename
            game_num = int(csv_file.stem.split("_")[1])
            df = df.with_columns(pl.lit(game_num).alias("game_id"))
            dfs.append(df)
        except Exception as e:
            print(f"⚠ Skipping {csv_file.name}: {e}")

    combined = pl.concat(dfs)

    print("=" * 70)
    print("VICTORY SCORING DEBUG")
    print("=" * 70)

    # Get final turn data
    max_turn = combined.select(pl.col("turn").max()).item()
    print(f"\nMax turn in dataset: {max_turn}")

    final_turn = combined.filter(pl.col("turn") == max_turn)

    print(f"Total rows in final turn: {len(final_turn)}")
    print(f"Total games: {len(csv_files)}")
    print(f"Expected rows: {len(csv_files) * 4} (4 houses per game)")

    # Check for game_id uniqueness
    unique_games = final_turn.select(pl.col("game_id").n_unique()).item()
    print(f"Unique game IDs in final turn: {unique_games}")

    # Sample some games to see prestige distribution
    print("\n" + "=" * 70)
    print("SAMPLE GAMES - Final Turn Prestige by House")
    print("=" * 70)

    sample_games = sorted(final_turn.select("game_id").unique().to_series().to_list())[:10]

    for game_id in sample_games:
        game_data = final_turn.filter(pl.col("game_id") == game_id).sort("prestige", descending=True)
        print(f"\nGame {game_id}:")
        for row in game_data.iter_rows(named=True):
            winner_mark = "🏆" if row["prestige"] == game_data.select(pl.col("prestige").max()).item() else "  "
            print(f"  {winner_mark} House {row['house']:>2s} ({row['strategy']:15s}): {row['prestige']:6.1f} prestige")

    # Check for ties
    print("\n" + "=" * 70)
    print("TIE ANALYSIS")
    print("=" * 70)

    # Count ties per game (simpler approach)
    max_prestige_per_game = (final_turn
        .group_by("game_id")
        .agg(pl.col("prestige").max().alias("max_prestige"))
    )

    final_with_max = final_turn.join(max_prestige_per_game, on="game_id")
    final_with_max = final_with_max.with_columns(
        (pl.col("prestige") == pl.col("max_prestige")).alias("is_winner")
    )

    # Count winners per game
    winners_per_game = (final_with_max
        .group_by("game_id")
        .agg(pl.col("is_winner").sum().alias("num_winners"))
    )

    tie_counts = winners_per_game.group_by("num_winners").len().sort("num_winners")

    print("\nWinner distribution:")
    for row in tie_counts.iter_rows(named=True):
        print(f"  {int(row['num_winners'])} house(s) tied for win: {row['len']} games ({row['len']/len(csv_files)*100:.1f}%)")

    # Calculate correct victories per game
    print("\n" + "=" * 70)
    print("CORRECT VICTORY CALCULATION")
    print("=" * 70)

    # Find max prestige per game
    max_prestige_per_game = (final_turn
        .group_by("game_id")
        .agg(pl.col("prestige").max().alias("max_prestige"))
    )

    # Join and mark winners
    final_with_winners = final_turn.join(max_prestige_per_game, on="game_id")
    final_with_winners = final_with_winners.with_columns(
        (pl.col("prestige") == pl.col("max_prestige")).alias("is_winner")
    )

    # Count wins by strategy
    victories = (final_with_winners
        .group_by("strategy")
        .agg([
            pl.len().alias("total_games"),
            pl.col("is_winner").sum().alias("wins"),
        ])
        .sort("wins", descending=True)
    )

    print("\nWins by strategy (correct calculation):")
    for row in victories.iter_rows(named=True):
        win_rate = (row['wins'] / row['total_games'] * 100) if row['total_games'] > 0 else 0
        print(f"  {row['strategy']:20s}  Games: {row['total_games']:3d}  Wins: {row['wins']:3d}  Win Rate: {win_rate:5.1f}%")

    # Check prestige variance
    print("\n" + "=" * 70)
    print("PRESTIGE STATISTICS")
    print("=" * 70)

    prestige_stats = final_turn.select([
        pl.col("prestige").min().alias("min"),
        pl.col("prestige").max().alias("max"),
        pl.col("prestige").mean().alias("mean"),
        pl.col("prestige").std().alias("std"),
    ])

    for row in prestige_stats.iter_rows(named=True):
        print(f"  Min:  {row['min']:6.1f}")
        print(f"  Max:  {row['max']:6.1f}")
        print(f"  Mean: {row['mean']:6.1f}")
        print(f"  Std:  {row['std']:6.1f}")
        print(f"  CoV:  {row['std']/row['mean']*100:5.1f}% (coefficient of variation)")

    print("\n" + "=" * 70)
    print("✅ Debug complete!")
    print("=" * 70)

if __name__ == "__main__":
    main()
