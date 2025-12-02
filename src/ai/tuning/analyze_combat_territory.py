#!/usr/bin/env python3
"""
Analyze combat activity and territory changes from diagnostic CSVs
Uses polars for fast DataFrame operations

Checks:
- Wars declared (enemy_count > 0)
- Combat engagements (total_combats)
- Planets changing hands
- Invasion attempts and successes
"""

import polars as pl
import sys
from pathlib import Path

def analyze_combat_and_territory(diagnostics_dir: Path):
    """Analyze all diagnostic CSVs for combat and territory metrics"""

    csv_files = sorted(diagnostics_dir.glob("game_*.csv"))

    if not csv_files:
        print(f"ERROR: No CSV files found in {diagnostics_dir}")
        return

    print(f"Loading {len(csv_files)} diagnostic files...")

    # Load all CSVs into a single DataFrame
    df = pl.concat([
        pl.read_csv(f).with_columns(
            pl.lit(int(f.stem.split('_')[1])).alias('game_seed')
        )
        for f in csv_files
    ])

    num_games = df['game_seed'].n_unique()
    max_turn = df['turn'].max()

    print(f"Loaded {len(df)} rows from {num_games} games ({max_turn} turns each)\n")

    # ========================================================================
    # WARS AND DIPLOMACY (4-Level System: Neutral, Ally, Hostile, Enemy)
    # ========================================================================
    print("="*70)
    print("DIPLOMATIC STATE (4-Level System)")
    print("="*70)

    # Total diplomatic states across all games
    total_ally = df['ally_count'].sum()
    total_hostile = df['hostile_count'].sum()
    total_enemy = df['enemy_count'].sum()
    total_neutral = df['neutral_count'].sum()

    print(f"Total diplomatic relationships across all games:")
    print(f"  Ally (pacts):         {total_ally:5d}")
    print(f"  Hostile (tensions):   {total_hostile:5d}")
    print(f"  Enemy (open war):     {total_enemy:5d}")
    print(f"  Neutral (default):    {total_neutral:5d}")

    # Games with various diplomatic states
    games_with_allies = df.filter(pl.col('ally_count') > 0)['game_seed'].n_unique()
    games_with_hostile = df.filter(pl.col('hostile_count') > 0)['game_seed'].n_unique()
    games_with_wars = df.filter(pl.col('enemy_count') > 0)['game_seed'].n_unique()

    print(f"\nGames with diplomatic activity:")
    print(f"  At least 1 alliance: {games_with_allies}/{num_games} ({games_with_allies/num_games*100:.1f}%)")
    print(f"  At least 1 hostile:  {games_with_hostile}/{num_games} ({games_with_hostile/num_games*100:.1f}%)")
    print(f"  At least 1 war:      {games_with_wars}/{num_games} ({games_with_wars/num_games*100:.1f}%)")

    # Diplomatic escalation by turn
    if games_with_wars > 0 or games_with_hostile > 0:
        diplo_by_turn = (df
            .group_by('turn')
            .agg([
                pl.col('ally_count').sum().alias('allies'),
                pl.col('hostile_count').sum().alias('hostile'),
                pl.col('enemy_count').sum().alias('enemies')
            ])
            .sort('turn')
        )

        print(f"\nDiplomatic state evolution by turn:")
        print(f"  Turn | Allies | Hostile | Enemies")
        print(f"  -----|--------|---------|--------")
        for row in diplo_by_turn.iter_rows(named=True):
            print(f"    {row['turn']:2d} |   {row['allies']:4d} |   {row['hostile']:5d} |  {row['enemies']:6d}")
    else:
        print("⚠️  NO WARS OR HOSTILE STATES - Diplomatic escalation may not be working!")

    # Detect escalation events from bilateral relations
    # Format: "houseId:state;houseId:state" where state = N/A/H/E
    print(f"\n{'='*70}")
    print("AUTO-ESCALATION DETECTION (from bilateral_relations)")
    print("="*70)

    # Filter to rows with bilateral relations data
    relations_df = df.filter(pl.col('bilateral_relations').str.len_chars() > 0)

    if len(relations_df) > 0:
        # Count state types across all bilateral relationships
        hostile_pairs = relations_df.filter(pl.col('bilateral_relations').str.contains(':H'))
        enemy_pairs = relations_df.filter(pl.col('bilateral_relations').str.contains(':E'))
        ally_pairs = relations_df.filter(pl.col('bilateral_relations').str.contains(':A'))

        print(f"Detected relationship changes:")
        print(f"  House-turns with Hostile relations: {len(hostile_pairs)}")
        print(f"  House-turns with Enemy relations:   {len(enemy_pairs)}")
        print(f"  House-turns with Ally relations:    {len(ally_pairs)}")

        # Show first few escalation examples
        if len(hostile_pairs) > 0:
            print(f"\nSample Hostile escalations:")
            sample_hostile = hostile_pairs.select(['turn', 'house', 'bilateral_relations']).head(3)
            for row in sample_hostile.iter_rows(named=True):
                print(f"  Turn {row['turn']}: {row['house']} - {row['bilateral_relations']}")

        if len(enemy_pairs) > 0:
            print(f"\nSample Enemy escalations:")
            sample_enemy = enemy_pairs.select(['turn', 'house', 'bilateral_relations']).head(3)
            for row in sample_enemy.iter_rows(named=True):
                print(f"  Turn {row['turn']}: {row['house']} - {row['bilateral_relations']}")
    else:
        print("⚠️  No bilateral relations data found in diagnostics")

    # ========================================================================
    # COMBAT ENGAGEMENTS
    # ========================================================================
    print(f"\n{'='*70}")
    print("COMBAT ENGAGEMENTS")
    print("="*70)

    total_combats = df['space_total'].sum()
    games_with_combat = df.filter(pl.col('space_total') > 0)['game_seed'].n_unique()

    print(f"Total combat engagements: {total_combats}")
    print(f"Games with combat: {games_with_combat}/{num_games} ({games_with_combat/num_games*100:.1f}%)")

    if total_combats > 0:
        avg_per_game = total_combats / num_games
        print(f"Average combats per game: {avg_per_game:.1f}")

        # Combat by turn
        combat_by_turn = (df
            .group_by('turn')
            .agg(pl.col('space_total').sum().alias('combats'))
            .sort('turn')
        )

        print(f"\nCombat by turn:")
        for row in combat_by_turn.filter(pl.col('combats') > 0).iter_rows(named=True):
            print(f"  Turn {row['turn']:2d}: {row['combats']:4d} combats")
    else:
        print("⚠️  NO COMBAT DETECTED - Zero combats across all games!")

    # ========================================================================
    # INVASIONS
    # ========================================================================
    print(f"\n{'='*70}")
    print("INVASION ACTIVITY")
    print("="*70)

    total_invasions = df['total_invasions'].sum()
    games_with_invasions = df.filter(pl.col('total_invasions') > 0)['game_seed'].n_unique()

    print(f"Total invasion attempts: {total_invasions}")
    print(f"Games with invasions: {games_with_invasions}/{num_games} ({games_with_invasions/num_games*100:.1f}%)")

    if total_invasions > 0:
        avg_per_game = total_invasions / num_games
        print(f"Average invasions per game: {avg_per_game:.1f}")
    else:
        print("⚠️  NO INVASIONS DETECTED")

    # ========================================================================
    # TERRITORY CHANGES (Colony Count Changes)
    # ========================================================================
    print(f"\n{'='*70}")
    print("TERRITORY CHANGES")
    print("="*70)

    # Calculate colony changes per house per game
    territory_changes = []

    for game in df['game_seed'].unique().sort():
        game_df = df.filter(pl.col('game_seed') == game).sort('turn')

        for house in game_df['house'].unique():
            house_df = game_df.filter(pl.col('house') == house)

            # Get colony counts across turns
            colonies = house_df['total_colonies'].to_list()

            # Count increases and decreases
            gains = sum(1 for i in range(1, len(colonies)) if colonies[i] > colonies[i-1])
            losses = sum(1 for i in range(1, len(colonies)) if colonies[i] < colonies[i-1])

            if gains > 0 or losses > 0:
                territory_changes.append({
                    'game': game,
                    'house': house,
                    'gains': gains,
                    'losses': losses,
                    'net': gains - losses
                })

    if territory_changes:
        territory_df = pl.DataFrame(territory_changes)

        total_gains = territory_df['gains'].sum()
        total_losses = territory_df['losses'].sum()

        print(f"Total territory gains: {total_gains}")
        print(f"Total territory losses: {total_losses}")
        print(f"Houses that gained territory: {len(territory_df.filter(pl.col('gains') > 0))}")
        print(f"Houses that lost territory: {len(territory_df.filter(pl.col('losses') > 0))}")

        # Summary by house
        print(f"\nTerritory changes by house:")
        summary = (territory_df
            .group_by('house')
            .agg([
                pl.col('gains').sum().alias('total_gains'),
                pl.col('losses').sum().alias('total_losses'),
                pl.col('net').sum().alias('net_change')
            ])
            .sort('total_gains', descending=True)
        )

        for row in summary.iter_rows(named=True):
            print(f"  {row['house']:20s}: +{row['total_gains']:2d} -{row['total_losses']:2d} (net: {row['net_change']:+3d})")
    else:
        print("⚠️  NO TERRITORY CHANGES DETECTED - Static map!")

    # ========================================================================
    # SUMMARY
    # ========================================================================
    print(f"\n{'='*70}")
    print("COMBAT SYSTEM HEALTH CHECK")
    print("="*70)

    checks = [
        ("Wars declared", games_with_wars > 0),
        ("Combat engagements", total_combats > 0),
        ("Invasions attempted", total_invasions > 0),
        ("Territory changed hands", len(territory_changes) > 0),
    ]

    for check_name, passed in checks:
        status = "✅" if passed else "❌"
        print(f"{status} {check_name}")

    all_passed = all(passed for _, passed in checks)

    if all_passed:
        print(f"\n{'='*70}")
        print("✅ COMBAT SYSTEM WORKING - Wars, combat, and territory changes detected!")
        print("="*70)
    else:
        print(f"\n{'='*70}")
        print("⚠️  WARNING: Some combat metrics are missing!")
        print("="*70)

if __name__ == "__main__":
    diagnostics_path = Path("balance_results/diagnostics")

    if len(sys.argv) > 1:
        diagnostics_path = Path(sys.argv[1])

    if not diagnostics_path.exists():
        print(f"ERROR: Directory not found: {diagnostics_path}")
        sys.exit(1)

    analyze_combat_and_territory(diagnostics_path)
