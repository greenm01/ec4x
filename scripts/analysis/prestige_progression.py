#!/usr/bin/env python3
"""Analyze prestige progression to identify decline patterns"""

import polars as pl
from pathlib import Path

# Load all diagnostic data
diagnostic_dir = Path("balance_results/diagnostics")
df = pl.read_csv(f"{diagnostic_dir}/*.csv")

print("\n" + "=" * 70)
print("PRESTIGE PROGRESSION ANALYSIS")
print("=" * 70)

# Calculate average prestige by strategy and turn
prestige_by_turn = (
    df.group_by(['strategy', 'turn'])
    .agg([
        pl.col('prestige').mean().alias('avg_prestige'),
        pl.col('prestige').std().alias('std_prestige'),
        pl.col('prestige').min().alias('min_prestige'),
        pl.col('prestige').max().alias('max_prestige'),
        pl.col('prestige').count().alias('n_games')
    ])
    .sort(['strategy', 'turn'])
)

# Show key turns for each strategy
key_turns = [1, 5, 10, 15, 20, 25, 30, 31]
prestige_key = prestige_by_turn.filter(pl.col('turn').is_in(key_turns))

print("\n=== Prestige at Key Turns ===\n")
for strategy in ['Turtle', 'Economic', 'Balanced', 'Aggressive']:
    print(f"\n{strategy}:")
    strategy_data = prestige_key.filter(pl.col('strategy') == strategy)
    for row in strategy_data.iter_rows(named=True):
        print(f"  Turn {row['turn']:>2}: {row['avg_prestige']:>7.1f} (min: {row['min_prestige']}, max: {row['max_prestige']})")

# Calculate prestige growth rates
print("\n" + "=" * 70)
print("PRESTIGE GROWTH RATES")
print("=" * 70)

for strategy in ['Turtle', 'Economic', 'Balanced', 'Aggressive']:
    strategy_df = prestige_by_turn.filter(pl.col('strategy') == strategy).sort('turn')

    turns = strategy_df['turn'].to_list()
    prestiges = strategy_df['avg_prestige'].to_list()

    # Calculate deltas
    deltas = []
    for i in range(1, len(prestiges)):
        delta = prestiges[i] - prestiges[i-1]
        deltas.append((turns[i], delta))

    # Phase averages
    early = [d for t, d in deltas if 2 <= t <= 10]
    mid = [d for t, d in deltas if 11 <= t <= 20]
    late = [d for t, d in deltas if 21 <= t <= 31]

    print(f"\n{strategy}:")
    print(f"  Early game (T2-10):  {sum(early) / len(early):>6.1f} prestige/turn")
    print(f"  Mid game (T11-20):   {sum(mid) / len(mid):>6.1f} prestige/turn")
    print(f"  Late game (T21-31):  {sum(late) / len(late):>6.1f} prestige/turn")
    print(f"  Overall (T1-31):     {(prestiges[-1] - prestiges[0]) / 30:>6.1f} prestige/turn")

    # Check for decline
    negative_turns = [(t, d) for t, d in deltas if d < 0]
    if negative_turns:
        print(f"  ⚠️  DECLINE in {len(negative_turns)}/{len(deltas)} turns ({len(negative_turns)/len(deltas)*100:.1f}%)")
        # Show worst declines
        worst = sorted(negative_turns, key=lambda x: x[1])[:3]
        for turn, delta in worst:
            print(f"      Turn {turn}: {delta:+.1f}")
    else:
        print(f"  ✅ No turns with prestige decline")

# Analyze individual game trajectories
print("\n" + "=" * 70)
print("INDIVIDUAL GAME ANALYSIS")
print("=" * 70)

for strategy in ['Turtle', 'Economic', 'Balanced', 'Aggressive']:
    strategy_games = df.filter(pl.col('strategy') == strategy)

    # Find games with significant prestige loss
    games_with_decline = []

    for game_id in strategy_games['game_id'].unique():
        game_df = strategy_games.filter(pl.col('game_id') == game_id).sort('turn')
        prestiges = game_df['prestige'].to_list()

        # Check for any significant decline (>100 prestige drop)
        for i in range(1, len(prestiges)):
            if prestiges[i] < prestiges[i-1] - 100:
                games_with_decline.append((game_id, i, prestiges[i] - prestiges[i-1]))

        # Check final trajectory (last 10 turns)
        if len(prestiges) >= 10:
            last_10_delta = prestiges[-1] - prestiges[-10]
            if last_10_delta < 0:
                games_with_decline.append((game_id, 'last_10', last_10_delta))

    print(f"\n{strategy}:")
    if games_with_decline:
        print(f"  {len(set(g[0] for g in games_with_decline))} games with significant decline:")
        for game_id, turn, delta in games_with_decline[:5]:
            if turn == 'last_10':
                print(f"    Game {game_id}: Final 10 turns decline: {delta:+.0f}")
            else:
                print(f"    Game {game_id}, Turn {turn}: {delta:+.0f}")
    else:
        print(f"  ✅ No games with significant prestige decline")

print("\n" + "=" * 70)
