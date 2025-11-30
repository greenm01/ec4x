#!/usr/bin/env python3
"""
Debug Fighter Production
Investigate why fighters are never built across all games
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
            game_num = int(csv_file.stem.split("_")[1])
            df = df.with_columns(pl.lit(game_num).alias("game_id"))
            dfs.append(df)
        except Exception as e:
            print(f"⚠ Skipping {csv_file.name}: {e}")

    combined = pl.concat(dfs)

    print("=" * 70)
    print("FIGHTER PRODUCTION DEBUG")
    print("=" * 70)

    # Check fighter counts across all turns
    fighter_stats = combined.group_by("turn").agg([
        pl.col("fighter_ships").sum().alias("total_fighters"),
        pl.col("fighter_ships").max().alias("max_fighters_single_house"),
        pl.col("fighter_ships").mean().alias("avg_fighters"),
    ]).sort("turn")

    print("\n📊 Fighter Ships by Turn:")
    for row in fighter_stats.iter_rows(named=True):
        print(f"  Turn {row['turn']}: Total={row['total_fighters']:4.0f}  Max={row['max_fighters_single_house']:4.0f}  Avg={row['avg_fighters']:4.1f}")

    # Check carrier counts
    print("\n" + "=" * 70)
    print("CARRIER ANALYSIS")
    print("=" * 70)

    final_turn = combined.filter(pl.col("turn") == combined.select(pl.col("turn").max()).item())

    carrier_stats = final_turn.group_by("strategy").agg([
        pl.col("carrier_ships").mean().alias("avg_carriers"),
        pl.col("super_carrier_ships").mean().alias("avg_super_carriers"),
        pl.col("carrier_ships").sum().alias("total_carriers"),
        pl.col("super_carrier_ships").sum().alias("total_super_carriers"),
    ]).sort("avg_carriers", descending=True)

    print("\nCarriers by Strategy:")
    for row in carrier_stats.iter_rows(named=True):
        print(f"  {row['strategy']:20s}  Carriers: {row['avg_carriers']:4.1f} (total: {row['total_carriers']:3.0f})  " +
              f"Super: {row['avg_super_carriers']:4.1f} (total: {row['total_super_carriers']:3.0f})")

    # Check starbase counts (needed for colony-based fighter capacity)
    print("\n" + "=" * 70)
    print("STARBASE ANALYSIS")
    print("=" * 70)

    starbase_stats = final_turn.group_by("strategy").agg([
        pl.col("starbase_ships").mean().alias("avg_starbases"),
        pl.col("starbase_ships").sum().alias("total_starbases"),
    ]).sort("avg_starbases", descending=True)

    print("\nStarbases by Strategy:")
    for row in starbase_stats.iter_rows(named=True):
        print(f"  {row['strategy']:20s}  Avg: {row['avg_starbases']:4.1f}  Total: {row['total_starbases']:3.0f}")

    # Check tech levels (CST 3+ needed for carriers)
    print("\n" + "=" * 70)
    print("TECH LEVEL ANALYSIS")
    print("=" * 70)

    tech_stats = final_turn.group_by("strategy").agg([
        pl.col("tech_cst").mean().alias("avg_cst"),
        pl.col("tech_cst").min().alias("min_cst"),
        pl.col("tech_cst").max().alias("max_cst"),
    ]).sort("avg_cst", descending=True)

    print("\nCST (Construction) Tech by Strategy:")
    for row in tech_stats.iter_rows(named=True):
        print(f"  {row['strategy']:20s}  Avg: {row['avg_cst']:3.1f}  Min: {row['min_cst']:3.1f}  Max: {row['max_cst']:3.1f}")

    print("\n⚠️  CST 3+ required for Carriers")
    print("⚠️  CST 5+ required for Super Carriers")

    # Check budget allocation
    print("\n" + "=" * 70)
    print("BUDGET ANALYSIS")
    print("=" * 70)

    # Check if special units budget is being spent
    if "special_units_budget" in combined.columns:
        budget_stats = final_turn.group_by("strategy").agg([
            pl.col("special_units_budget").mean().alias("avg_budget"),
            pl.col("special_units_spent").mean().alias("avg_spent"),
        ])

        print("\nSpecial Units Budget by Strategy:")
        for row in budget_stats.iter_rows(named=True):
            print(f"  {row['strategy']:20s}  Budget: {row['avg_budget']:5.1f}PP  Spent: {row['avg_spent']:5.1f}PP")
    else:
        print("⚠️  special_units_budget column not found in CSV")

    # Check for any fighter-related columns
    print("\n" + "=" * 70)
    print("FIGHTER-RELATED COLUMNS")
    print("=" * 70)

    fighter_cols = [col for col in combined.columns if "fighter" in col.lower()]
    print(f"\nFound {len(fighter_cols)} fighter-related columns:")
    for col in fighter_cols:
        total = combined.select(pl.col(col).sum()).item()
        print(f"  {col}: {total}")

    # Sample a single game to show detailed progression
    print("\n" + "=" * 70)
    print("SAMPLE GAME PROGRESSION (Game 11604)")
    print("=" * 70)

    sample_game = combined.filter(pl.col("game_id") == 11604).sort("turn", "house")
    if len(sample_game) > 0:
        print("\nTurn-by-turn progression:")
        for turn in range(1, 9):
            turn_data = sample_game.filter(pl.col("turn") == turn)
            print(f"\n  Turn {turn}:")
            for row in turn_data.iter_rows(named=True):
                print(f"    {row['house']:>20s} ({row['strategy']:15s}): " +
                      f"Starbases={row['starbase_ships']:2.0f} Carriers={row['carrier_ships']:2.0f} " +
                      f"SuperCarriers={row['super_carrier_ships']:2.0f} Fighters={row['fighter_ships']:2.0f} CST={row['tech_cst']:3.1f}")

    print("\n" + "=" * 70)
    print("✅ Debug complete!")
    print("=" * 70)

    # Hypothesis summary
    print("\n📝 HYPOTHESIS CHECK:")
    print("  1. No carriers built → Fighters have no hangar space")
    print("  2. No starbases built → Fighters have no colony capacity")
    print("  3. Low CST tech → Can't unlock carriers (CST 3+)")
    print("  4. Budget not allocated → No PP for special units")

if __name__ == "__main__":
    main()
