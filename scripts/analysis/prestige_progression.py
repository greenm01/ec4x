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

# Show key turns for each strategy (dynamic based on actual game length)
max_turn = df['turn'].max()
key_turns = [1, max_turn//6, max_turn//3, max_turn//2,
             2*max_turn//3, 5*max_turn//6, max_turn]
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

    # Phase averages (dynamic based on actual game length)
    if not turns:
        continue
    game_max_turn = max(turns)
    early_end = game_max_turn // 3
    mid_end = 2 * game_max_turn // 3

    early = [d for t, d in deltas if 2 <= t <= early_end]
    mid = [d for t, d in deltas if early_end < t <= mid_end]
    late = [d for t, d in deltas if t > mid_end]

    print(f"\n{strategy}:")
    if early:
        print(f"  Early game (T2-{early_end}):  {sum(early) / len(early):>6.1f} prestige/turn")
    if mid:
        print(f"  Mid game (T{early_end+1}-{mid_end}):   {sum(mid) / len(mid):>6.1f} prestige/turn")
    if late:
        print(f"  Late game (T{mid_end+1}-{game_max_turn}):  {sum(late) / len(late):>6.1f} prestige/turn")

    actual_turns = turns[-1] - turns[0]
    if actual_turns > 0:
        print(f"  Overall (T1-{game_max_turn}):     {(prestiges[-1] - prestiges[0]) / actual_turns:>6.1f} prestige/turn")

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

        # Check final trajectory (last 1/6 of game)
        if len(prestiges) >= 6:
            last_sixth = max(1, len(prestiges) // 6)
            last_delta = prestiges[-1] - prestiges[-last_sixth]
            if last_delta < 0:
                games_with_decline.append((game_id, f'last_{last_sixth}', last_delta))

    print(f"\n{strategy}:")
    if games_with_decline:
        print(f"  {len(set(g[0] for g in games_with_decline))} games with significant decline:")
        for game_id, turn, delta in games_with_decline[:5]:
            if isinstance(turn, str) and turn.startswith('last_'):
                turns_checked = turn.split('_')[1]
                print(f"    Game {game_id}: Final {turns_checked} turns decline: {delta:+.0f}")
            else:
                print(f"    Game {game_id}, Turn {turn}: {delta:+.0f}")
    else:
        print(f"  ✅ No games with significant prestige decline")

print("\n" + "=" * 70)
