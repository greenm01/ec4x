#!/usr/bin/env python3
"""
RBA Performance Analysis
Analyzes diagnostic CSVs to show key metrics and AI strategy performance
"""

import polars as pl
from pathlib import Path
import sys

def main():
    diagnostics_dir = Path("balance_results/diagnostics")
    csv_files = sorted(diagnostics_dir.glob("game_*.csv"))

    if not csv_files:
        print("❌ No diagnostic CSV files found in balance_results/diagnostics/")
        print("   Run 'nimble testBalanceQuick' or 'nimble balanceDiagnostic' first")
        sys.exit(1)

    print(f"📊 Analyzing {len(csv_files)} games...\n")

    # Read all CSV files
    dfs = []
    for csv_file in csv_files:
        try:
            df = pl.read_csv(csv_file)
            dfs.append(df)
        except Exception as e:
            print(f"⚠ Skipping {csv_file.name}: {e}")

    if not dfs:
        print("❌ No valid CSV files could be read")
        sys.exit(1)

    # Combine all dataframes
    combined = pl.concat(dfs)

    # Get final turn data for each house in each game
    max_turn = combined.select(pl.col("turn").max()).item()
    final_turn = combined.filter(pl.col("turn") == max_turn)

    print("=" * 70)
    print(f"RBA PERFORMANCE SUMMARY ({len(csv_files)} Games, Turn {max_turn})")
    print("=" * 70)

    # ===================================================================
    # SECTION 1: Overall Strategy Performance
    # ===================================================================
    print("\n📈 STRATEGY PERFORMANCE\n")

    # Calculate total ships as sum of all ship types
    ship_cols = [
        "fighter_ships", "corvette_ships", "frigate_ships", "scout_ships", "raider_ships",
        "destroyer_ships", "cruiser_ships", "light_cruiser_ships", "heavy_cruiser_ships",
        "battlecruiser_ships", "battleship_ships", "dreadnought_ships", "super_dreadnought_ships",
        "carrier_ships", "super_carrier_ships", "starbase_ships", "etac_ships",
        "troop_transport_ships", "planet_breaker_ships"
    ]

    final_turn_with_total = final_turn.with_columns(
        pl.sum_horizontal([pl.col(c) for c in ship_cols]).alias("total_ships")
    )

    strategy_stats = (final_turn_with_total
        .group_by("strategy")
        .agg([
            pl.len().alias("count"),
            pl.col("prestige").mean().alias("avg_prestige"),
            pl.col("prestige").std().alias("std_prestige"),
            pl.col("treasury").mean().alias("avg_treasury"),
            pl.col("total_colonies").mean().alias("avg_colonies"),
            pl.col("total_ships").mean().alias("avg_ships"),
        ])
        .sort("avg_prestige", descending=True)
    )

    for row in strategy_stats.iter_rows(named=True):
        print(f"  {row['strategy']:20s}  "
              f"Prestige: {row['avg_prestige']:6.1f} (±{row['std_prestige']:4.1f})  "
              f"Treasury: {row['avg_treasury']:5.0f}  "
              f"Colonies: {row['avg_colonies']:4.1f}  "
              f"Ships: {row['avg_ships']:5.1f}")

    # ===================================================================
    # SECTION 2: Economic Activity
    # ===================================================================
    print("\n💰 ECONOMIC ACTIVITY\n")
    econ_stats = (final_turn
        .group_by("strategy")
        .agg([
            pl.col("production").mean().alias("avg_production"),
            pl.col("total_iu").mean().alias("avg_industrial_units"),
            pl.col("total_pu").mean().alias("avg_population_units"),
            pl.col("gco").mean().alias("avg_gco"),  # Gross Colony Output
        ])
        .sort("avg_production", descending=True)
    )

    for row in econ_stats.iter_rows(named=True):
        print(f"  {row['strategy']:20s}  "
              f"Production: {row['avg_production']:5.1f}  "
              f"IU: {row['avg_industrial_units']:5.1f}  "
              f"PU: {row['avg_population_units']:5.1f}  "
              f"GCO: {row['avg_gco']:5.1f}")

    # ===================================================================
    # SECTION 3: Military Strength
    # ===================================================================
    print("\n⚔️  MILITARY STRENGTH\n")

    # Define ship categories
    capital_ships = ["destroyer_ships", "cruiser_ships", "light_cruiser_ships", "heavy_cruiser_ships",
                     "battlecruiser_ships", "battleship_ships", "dreadnought_ships", "super_dreadnought_ships"]
    escort_ships = ["corvette_ships", "frigate_ships"]

    # Calculate aggregates
    final_turn_military = final_turn.with_columns([
        pl.sum_horizontal([pl.col(c) for c in capital_ships]).alias("total_capitals"),
        pl.sum_horizontal([pl.col(c) for c in escort_ships]).alias("total_escorts"),
    ])

    military_stats = (final_turn_military
        .group_by("strategy")
        .agg([
            pl.col("total_fighters").mean().alias("avg_fighters"),
            pl.col("total_capitals").mean().alias("avg_capitals"),
            pl.col("total_escorts").mean().alias("avg_escorts"),
            pl.col("scout_ships").mean().alias("avg_scouts"),
        ])
        .sort("avg_capitals", descending=True)
    )

    for row in military_stats.iter_rows(named=True):
        print(f"  {row['strategy']:20s}  "
              f"Fighters: {row['avg_fighters']:4.1f}  "
              f"Capitals: {row['avg_capitals']:4.1f}  "
              f"Escorts: {row['avg_escorts']:4.1f}  "
              f"Scouts: {row['avg_scouts']:4.1f}")

    # ===================================================================
    # SECTION 4: Research Progress
    # ===================================================================
    print("\n🔬 RESEARCH PROGRESS\n")
    research_stats = (final_turn
        .group_by("strategy")
        .agg([
            pl.col("tech_el").mean().alias("avg_eco"),  # EL = Economic Level
            pl.col("tech_sl").mean().alias("avg_sci"),  # SL = Science Level
            pl.col("tech_wep").mean().alias("avg_wpn"),  # WEP = Weapons
            pl.col("tech_cst").mean().alias("avg_cst"),  # CST = Construction
        ])
        .sort("avg_sci", descending=True)
    )

    for row in research_stats.iter_rows(named=True):
        print(f"  {row['strategy']:20s}  "
              f"Eco: {row['avg_eco']:3.1f}  "
              f"Sci: {row['avg_sci']:3.1f}  "
              f"Wpn: {row['avg_wpn']:3.1f}  "
              f"Cst: {row['avg_cst']:3.1f}")

    # ===================================================================
    # SECTION 5: Espionage Activity
    # ===================================================================
    print("\n🕵️  ESPIONAGE ACTIVITY\n")
    espionage_stats = (combined  # Use all turns, not just final turn
        .group_by("strategy")
        .agg([
            pl.col("espionage_success").sum().alias("total_success"),
            pl.col("espionage_failure").sum().alias("total_failure"),
            pl.col("ebp_spent").mean().alias("avg_ebp"),  # Espionage Budget Points
            pl.col("cip_spent").mean().alias("avg_cip"),  # Counter-Intelligence Points
        ])
        .sort("total_success", descending=True)
    )

    for row in espionage_stats.iter_rows(named=True):
        total_missions = row['total_success'] + row['total_failure']
        success_rate = (row['total_success'] / total_missions * 100) if total_missions > 0 else 0
        print(f"  {row['strategy']:20s}  "
              f"Success: {row['total_success']:4.0f}  "
              f"Failure: {row['total_failure']:4.0f}  "
              f"Rate: {success_rate:4.1f}%  "
              f"EBP: {row['avg_ebp']:4.1f}  "
              f"CIP: {row['avg_cip']:4.1f}")

    # ===================================================================
    # SECTION 6: AI Behavior Patterns
    # ===================================================================
    print("\n🤖 AI BEHAVIOR PATTERNS\n")
    behavior_stats = (combined  # Use all turns
        .group_by("strategy")
        .agg([
            pl.col("total_orders").sum().alias("total_orders"),
            pl.col("invalid_orders").sum().alias("total_rejected"),
            pl.col("active_pacts").mean().alias("avg_pacts"),
        ])
    )

    for row in behavior_stats.iter_rows(named=True):
        reject_rate = (row['total_rejected'] / row['total_orders'] * 100) if row['total_orders'] > 0 else 0
        print(f"  {row['strategy']:20s}  "
              f"Orders: {row['total_orders']:5.0f}  "
              f"Rejected: {row['total_rejected']:3.0f} ({reject_rate:4.1f}%)  "
              f"Avg Pacts: {row['avg_pacts']:4.1f}")

    # ===================================================================
    # SECTION 7: Victory Analysis
    # ===================================================================
    print("\n🏆 VICTORY ANALYSIS\n")

    # Calculate wins: count how many times this strategy had the highest prestige
    # Need to add game_id from CSV filename to properly group by game
    # For now, we'll use a workaround: assume each game has unique turn+house combinations
    # and group by combinations of turn values to identify separate games

    # Better approach: Add game_id when reading CSVs
    # Read all CSV files again with game_id
    dfs_with_id = []
    for csv_file in csv_files:
        try:
            df = pl.read_csv(csv_file)
            game_num = int(csv_file.stem.split("_")[1])
            df = df.with_columns(pl.lit(game_num).alias("game_id"))
            dfs_with_id.append(df)
        except Exception as e:
            pass

    if dfs_with_id:
        combined_with_id = pl.concat(dfs_with_id)
        final_turn_with_id = combined_with_id.filter(pl.col("turn") == max_turn)

        # Find max prestige per game
        max_prestige_per_game = (final_turn_with_id
            .group_by("game_id")
            .agg(pl.col("prestige").max().alias("max_prestige"))
        )

        # Join and mark winners
        final_with_max = final_turn_with_id.join(max_prestige_per_game, on="game_id")
        final_with_max = final_with_max.with_columns(
            (pl.col("prestige") == pl.col("max_prestige")).alias("is_winner")
        )

        victories = (final_with_max
            .group_by("strategy")
            .agg([
                pl.len().alias("games"),
                pl.col("is_winner").sum().alias("wins"),
            ])
            .sort("wins", descending=True)
        )
    else:
        # Fallback if game_id extraction fails
        victories = final_turn.group_by("strategy").agg([
            pl.len().alias("games"),
            pl.lit(0).alias("wins"),
        ])

    for row in victories.iter_rows(named=True):
        win_rate = (row['wins'] / row['games'] * 100) if row['games'] > 0 else 0
        print(f"  {row['strategy']:20s}  Games: {row['games']:3d}  Wins: {row['wins']:3d}  Win Rate: {win_rate:5.1f}%")

    print("\n" + "=" * 70)
    print("✅ Analysis complete!")
    print("=" * 70)

if __name__ == "__main__":
    main()
