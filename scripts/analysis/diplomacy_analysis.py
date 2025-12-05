#!/usr/bin/env python3
"""Analyze diplomatic relations and dishonor mechanics"""

import polars as pl
from pathlib import Path
import sys

# Load all diagnostic data
diagnostic_dir = Path("balance_results/diagnostics")

# Get list of CSV files and check which have the new schema
csv_files = list(diagnostic_dir.glob("*.csv"))
if not csv_files:
    print("No CSV files found in balance_results/diagnostics/")
    sys.exit(1)

# Try loading first file to check schema
try:
    sample_df = pl.read_csv(csv_files[0])
    # Check if new schema (has game_id, act, rank, etc)
    required_cols = ['game_id', 'turn', 'act', 'rank', 'bilateral_relations']
    has_new_schema = all(col in sample_df.columns for col in required_cols)

    if not has_new_schema:
        print(f"⚠️  File {csv_files[0].name} has old schema (missing enhanced diagnostics)")
        print("   Looking for files with new schema...")

        # Find files with new schema
        new_schema_files = []
        for csv_file in csv_files:
            try:
                test_df = pl.read_csv(csv_file)
                if all(col in test_df.columns for col in required_cols):
                    new_schema_files.append(csv_file)
            except:
                pass

        if not new_schema_files:
            print("❌ No files with enhanced diagnostics found")
            print("   Run a new simulation to generate enhanced diagnostic data")
            sys.exit(1)

        print(f"✓ Found {len(new_schema_files)} files with new schema")
        # Load only new schema files
        df = pl.concat([pl.read_csv(f) for f in new_schema_files])
    else:
        # All files have new schema, load all
        df = pl.concat([pl.read_csv(f) for f in csv_files])

except Exception as e:
    print(f"Error loading CSV files: {e}")
    sys.exit(1)

print("\n" + "=" * 70)
print("DIPLOMACY & DISHONOR ANALYSIS")
print("=" * 70)

# === Basic Stats ===
print("\n=== Dataset Overview ===")
total_games = df["game_id"].n_unique()
total_turns = df.group_by("game_id").agg(pl.col("turn").max().alias("max_turn"))["max_turn"].mean()
total_houses = df["house"].n_unique()

print(f"Total games analyzed: {total_games}")
print(f"Average turns per game: {total_turns:.1f}")
print(f"Houses per game: {total_houses}")

# === Diplomatic Relations Progression ===
print("\n" + "=" * 70)
print("DIPLOMATIC RELATIONS PROGRESSION")
print("=" * 70)

# Count relation types over time
relation_counts = (
    df.group_by("turn")
    .agg([
        pl.col("neutral_count").mean().alias("avg_neutral"),
        pl.col("hostile_count").mean().alias("avg_hostile"),
        pl.col("enemy_count").mean().alias("avg_enemy"),
        pl.col("ally_count").mean().alias("avg_ally"),
    ])
    .sort("turn")
)

# Show key turns
key_turns = [1, 5, 10, 15, 20, 25, 30]
print("\nAverage relations per house at key turns:")
print("Turn | Neutral | Hostile | Enemy | Ally")
print("-----|---------|---------|-------|-----")
for turn in key_turns:
    turn_data = relation_counts.filter(pl.col("turn") == turn)
    if len(turn_data) > 0:
        row = turn_data.row(0, named=True)
        print(f"{turn:4d} | {row['avg_neutral']:7.2f} | {row['avg_hostile']:7.2f} | {row['avg_enemy']:5.2f} | {row['avg_ally']:4.2f}")

# === Diplomatic Events ===
print("\n" + "=" * 70)
print("DIPLOMATIC EVENTS")
print("=" * 70)

# Total events
total_hostility = df["hostility_declarations"].sum()
total_wars = df["war_declarations"].sum()
total_pact_formed = df["pact_formations"].sum()
total_pact_broken = df["pact_breaks"].sum()
total_violations = df["pact_violations"].sum()

print(f"\nTotal diplomatic events across all games:")
print(f"  Hostility declarations: {total_hostility}")
print(f"  War declarations: {total_wars}")
print(f"  Pacts formed: {total_pact_formed}")
print(f"  Pacts broken: {total_pact_broken}")
print(f"  Pact violations: {total_violations}")

# Events per game
events_per_game = (
    df.group_by("game_id")
    .agg([
        pl.col("hostility_declarations").sum().alias("hostility"),
        pl.col("war_declarations").sum().alias("wars"),
        pl.col("pact_formations").sum().alias("pacts"),
        pl.col("pact_breaks").sum().alias("breaks"),
        pl.col("pact_violations").sum().alias("violations"),
    ])
)

print(f"\nAverage per game:")
print(f"  Hostility declarations: {events_per_game['hostility'].mean():.2f}")
print(f"  War declarations: {events_per_game['wars'].mean():.2f}")
print(f"  Pacts formed: {events_per_game['pacts'].mean():.2f}")
print(f"  Pacts broken: {events_per_game['breaks'].mean():.2f}")
print(f"  Pact violations: {events_per_game['violations'].mean():.2f}")

# === Dishonor Analysis ===
print("\n" + "=" * 70)
print("DISHONOR MECHANICS")
print("=" * 70)

# Check dishonored status
total_dishonored_instances = df["dishonored"].sum()
houses_dishonored = df.filter(pl.col("dishonored") > 0).shape[0]

print(f"\nDishonor incidents:")
print(f"  Total dishonored status instances: {total_dishonored_instances}")
print(f"  Houses marked dishonored: {houses_dishonored}")

if total_dishonored_instances > 0:
    # Find games with dishonor
    dishonor_games = (
        df.filter(pl.col("dishonored") > 0)
        .group_by("game_id")
        .agg([
            pl.col("house").n_unique().alias("houses_dishonored"),
            pl.col("dishonored").sum().alias("total_dishonor_turns"),
        ])
    )

    print(f"\nGames with dishonor: {len(dishonor_games)}/{total_games} ({len(dishonor_games)/total_games*100:.1f}%)")
    print(f"Average dishonor turns per affected game: {dishonor_games['total_dishonor_turns'].mean():.1f}")

    # Show strategy breakdown
    dishonor_by_strategy = (
        df.filter(pl.col("dishonored") > 0)
        .group_by("strategy")
        .agg([
            pl.col("dishonored").sum().alias("dishonor_instances"),
            pl.col("house").n_unique().alias("houses_affected"),
        ])
        .sort("dishonor_instances", descending=True)
    )

    print("\nDishonor by strategy:")
    for row in dishonor_by_strategy.iter_rows(named=True):
        print(f"  {row['strategy']:12s}: {row['dishonor_instances']:3d} instances, {row['houses_affected']:2d} houses")
else:
    print("\n⚠️  NO DISHONOR DETECTED in any game!")
    print("   Possible reasons:")
    print("   - Pact violations not generating dishonor status")
    print("   - No pacts being formed/broken")
    print("   - Dishonor mechanic not implemented/enabled")

# === Isolation Analysis ===
print("\n" + "=" * 70)
print("DIPLOMATIC ISOLATION")
print("=" * 70)

total_isolation_turns = df["diplo_isolation_turns"].sum()
houses_isolated = df.filter(pl.col("diplo_isolation_turns") > 0).shape[0]

print(f"\nIsolation incidents:")
print(f"  Total isolation turns: {total_isolation_turns}")
print(f"  House-turns in isolation: {houses_isolated}")

if total_isolation_turns > 0:
    isolation_by_strategy = (
        df.filter(pl.col("diplo_isolation_turns") > 0)
        .group_by("strategy")
        .agg([
            pl.col("diplo_isolation_turns").sum().alias("total_turns"),
            pl.col("house").n_unique().alias("houses_affected"),
        ])
        .sort("total_turns", descending=True)
    )

    print("\nIsolation by strategy:")
    for row in isolation_by_strategy.iter_rows(named=True):
        print(f"  {row['strategy']:12s}: {row['total_turns']:3d} turns, {row['houses_affected']:2d} houses")
else:
    print("\n✓ No diplomatic isolation detected")

# === Conflict Progression ===
print("\n" + "=" * 70)
print("CONFLICT ESCALATION OVER TIME")
print("=" * 70)

# Track when hostilities begin
conflict_start = (
    df.filter((pl.col("hostile_count") > 0) | (pl.col("enemy_count") > 0))
    .group_by("game_id")
    .agg(pl.col("turn").min().alias("first_conflict_turn"))
)

if len(conflict_start) > 0:
    avg_conflict_start = conflict_start["first_conflict_turn"].mean()
    min_conflict_start = conflict_start["first_conflict_turn"].min()
    max_conflict_start = conflict_start["first_conflict_turn"].max()

    print(f"\nFirst conflict timing:")
    print(f"  Average turn: {avg_conflict_start:.1f}")
    print(f"  Earliest: Turn {min_conflict_start}")
    print(f"  Latest: Turn {max_conflict_start}")
    print(f"  Games with conflict: {len(conflict_start)}/{total_games} ({len(conflict_start)/total_games*100:.1f}%)")
else:
    print("\n⚠️  NO CONFLICTS in any game!")
    print("   All games remained peaceful (all Neutral relations)")

# === Strategy Impact on Relations ===
print("\n" + "=" * 70)
print("STRATEGY DIPLOMATIC BEHAVIOR")
print("=" * 70)

strategy_diplo = (
    df.group_by("strategy")
    .agg([
        pl.col("neutral_count").mean().alias("avg_neutral"),
        pl.col("hostile_count").mean().alias("avg_hostile"),
        pl.col("enemy_count").mean().alias("avg_enemy"),
        pl.col("ally_count").mean().alias("avg_ally"),
        pl.col("pact_formations").sum().alias("pacts_formed"),
        pl.col("pact_breaks").sum().alias("pacts_broken"),
        pl.col("hostility_declarations").sum().alias("hostilities"),
        pl.col("war_declarations").sum().alias("wars"),
    ])
    .sort("avg_enemy", descending=True)
)

print("\nAverage relations by strategy:")
print("Strategy     | Neutral | Hostile | Enemy | Ally | Pacts | Breaks | Hostility | Wars")
print("-------------|---------|---------|-------|------|-------|--------|-----------|-----")
for row in strategy_diplo.iter_rows(named=True):
    print(f"{row['strategy']:12s} | {row['avg_neutral']:7.2f} | {row['avg_hostile']:7.2f} | {row['avg_enemy']:5.2f} | {row['avg_ally']:4.2f} | "
          f"{row['pacts_formed']:5d} | {row['pacts_broken']:6d} | {row['hostilities']:9d} | {row['wars']:4d}")

print("\n" + "=" * 70)
