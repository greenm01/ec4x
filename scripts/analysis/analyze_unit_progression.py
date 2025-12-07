#!/usr/bin/env python3
"""
Analyze RBA unit progression patterns by Act.

Validates that RBA follows the unit-progression.md specification:
- Act 1 (turns 1-7): ETACs, scouts, light escorts, basic defense
- Act 2 (turns 8-15): Capitals, transports, marines, invasion prep
- Act 3 (turns 16-25): Heavy capitals, active invasions, attrition war
- Act 4 (turns 26+): SuperDreadnoughts, PlanetBreakers, total domination
"""

import polars as pl
from pathlib import Path
import sys


def load_diagnostics(game_id: str = None) -> pl.DataFrame:
    """Load diagnostic CSV(s)."""
    if game_id:
        csv_path = f"balance_results/diagnostics/game_{game_id}.csv"
        if not Path(csv_path).exists():
            print(f"ERROR: File not found: {csv_path}")
            sys.exit(1)
        print(f"Loading {csv_path}...")
        df = pl.read_csv(csv_path)
    else:
        path = Path("balance_results/diagnostics")
        if not path.exists():
            print(f"ERROR: Directory not found: balance_results/diagnostics")
            sys.exit(1)
        csv_files = list(path.glob("game_*.csv"))
        if not csv_files:
            print(f"ERROR: No game_*.csv files found")
            sys.exit(1)
        print(f"Loading {len(csv_files)} CSV files...")
        df = pl.read_csv(str(path / "game_*.csv"))

    print(f"Loaded {len(df)} rows")
    return df


def classify_act(turn: int) -> str:
    """Classify turn into Act (matches unit-progression.md)."""
    if turn <= 7:
        return "Act1"
    elif turn <= 15:
        return "Act2"
    elif turn <= 25:
        return "Act3"
    else:
        return "Act4"


def analyze_fleet_composition_by_act(df: pl.DataFrame) -> None:
    """Analyze fleet composition in each Act (final turn snapshot)."""

    print("\n" + "=" * 80)
    print("FLEET COMPOSITION BY ACT (Final Turn Averages)")
    print("=" * 80)

    # Add act classification
    df = df.with_columns([
        pl.col("turn").map_elements(classify_act, return_dtype=pl.Utf8).alias("act_classification")
    ])

    # Ship type columns
    ship_types = {
        "ETAC": "etac_ships",
        "Scout": "scout_ships",
        "Fighter": "fighter_ships",
        "Corvette": "corvette_ships",
        "Frigate": "frigate_ships",
        "Destroyer": "destroyer_ships",
        "Light Cruiser": "light_cruiser_ships",
        "Cruiser": "cruiser_ships",
        "Heavy Cruiser": "heavy_cruiser_ships",
        "Battlecruiser": "battlecruiser_ships",
        "Battleship": "battleship_ships",
        "Dreadnought": "dreadnought_ships",
        "Super Dreadnought": "super_dreadnought_ships",
        "Carrier": "carrier_ships",
        "Super Carrier": "super_carrier_ships",
        "Raider": "raider_ships",
        "Troop Transport": "troop_transport_ships",
        "Planet Breaker": "planet_breaker_ships",
    }

    # Get last turn of each act for each game/house
    for act in ["Act1", "Act2", "Act3", "Act4"]:
        act_df = df.filter(pl.col("act_classification") == act)

        if len(act_df) == 0:
            continue

        # Get last turn of act per game/house
        last_turns = (
            act_df
            .group_by(["game_id", "house"])
            .agg(pl.col("turn").max().alias("max_turn"))
        )

        # Join to get final snapshots
        final_snapshots = act_df.join(
            last_turns,
            on=["game_id", "house"],
            how="inner"
        ).filter(pl.col("turn") == pl.col("max_turn"))

        print(f"\n{act} (Turns {act_df['turn'].min()}-{act_df['turn'].max()}):")
        print("-" * 80)

        for ship_name, col in ship_types.items():
            if col not in df.columns:
                continue

            avg = final_snapshots[col].mean()
            total = final_snapshots[col].sum()

            if avg > 0.1:  # Only show ships that exist
                print(f"  {ship_name:20} Avg: {avg:6.2f}  Total: {total:6}")


def analyze_etac_by_turn(df: pl.DataFrame) -> None:
    """Analyze ETAC counts turn-by-turn."""

    print("\n" + "=" * 80)
    print("ETAC PROGRESSION BY TURN")
    print("=" * 80)

    if "etac_ships" not in df.columns:
        print("ERROR: etac_ships column not found")
        return

    # Average ETAC count per turn across all houses
    etac_by_turn = (
        df.group_by("turn")
        .agg([
            pl.col("etac_ships").mean().alias("avg_etacs"),
            pl.col("etac_ships").max().alias("max_etacs"),
            pl.col("etac_ships").sum().alias("total_etacs")
        ])
        .sort("turn")
    )

    print("\nTurn | Avg ETACs | Max ETACs | Total")
    print("-" * 45)
    for row in etac_by_turn.iter_rows(named=True):
        turn = row["turn"]
        act_marker = f"[{classify_act(turn)}]"
        print(f"{turn:4} {act_marker:7} {row['avg_etacs']:8.2f}  {row['max_etacs']:8}  {row['total_etacs']:8}")

    print("\n⚠️  EXPECTED BEHAVIOR (from unit-progression.md):")
    print("  Act 1: ETAC count should GROW (expansion)")
    print("  Act 2+: ETAC count should PLATEAU (cap reached)")


def analyze_capital_ships_by_turn(df: pl.DataFrame) -> None:
    """Analyze capital ship progression over turns."""

    print("\n" + "=" * 80)
    print("CAPITAL SHIP PROGRESSION BY TURN")
    print("=" * 80)

    capital_cols = {
        "Medium Capitals": ["cruiser_ships", "heavy_cruiser_ships", "battlecruiser_ships"],
        "Heavy Capitals": ["battleship_ships", "dreadnought_ships"],
        "Ultimate Capitals": ["super_dreadnought_ships"]
    }

    for group_name, cols in capital_cols.items():
        available = [c for c in cols if c in df.columns]
        if not available:
            continue

        print(f"\n{group_name}:")
        print("-" * 45)

        # Sum the group per turn
        group_sums = []
        for turn in sorted(df["turn"].unique()):
            turn_df = df.filter(pl.col("turn") == turn)
            total = sum(turn_df[col].sum() for col in available)
            avg = sum(turn_df[col].mean() for col in available)
            act = classify_act(turn)
            group_sums.append((turn, act, avg, total))

        print("Turn | Act    | Avg  | Total")
        for turn, act, avg, total in group_sums[:15]:  # Show first 15 turns
            print(f"{turn:4} | {act:6} | {avg:4.1f} | {total:5}")


def analyze_invasion_capability_by_turn(df: pl.DataFrame) -> None:
    """Analyze invasion capability (Transports + Marines) by turn."""

    print("\n" + "=" * 80)
    print("INVASION CAPABILITY BY TURN")
    print("=" * 80)

    if "troop_transport_ships" not in df.columns:
        print("WARNING: troop_transport_ships column not found")
        return

    if "marine_division_units" not in df.columns:
        print("WARNING: marine_division_units column not found")
        return

    invasion_by_turn = (
        df.group_by("turn")
        .agg([
            pl.col("troop_transport_ships").mean().alias("avg_transports"),
            pl.col("marine_division_units").mean().alias("avg_marines"),
            pl.col("troop_transport_ships").sum().alias("total_transports"),
            pl.col("marine_division_units").sum().alias("total_marines")
        ])
        .sort("turn")
    )

    print("\nTurn | Act    | Avg Transports | Avg Marines | Total Transports | Total Marines")
    print("-" * 85)
    for row in invasion_by_turn.iter_rows(named=True):
        turn = row["turn"]
        act = classify_act(turn)
        marker = "❌" if act == "Act1" and (row["total_transports"] > 0 or row["total_marines"] > 0) else ""
        print(f"{marker}{turn:4} | {act:6} | {row['avg_transports']:14.2f} | {row['avg_marines']:11.2f} | {row['total_transports']:16} | {row['total_marines']:13}")

    print("\n⚠️  EXPECTED BEHAVIOR:")
    print("  Act 1: ZERO transports/marines")
    print("  Act 2+: Active transport/marine production")


def analyze_strategy_progression(df: pl.DataFrame) -> None:
    """Compare unit progression across different strategies."""

    print("\n" + "=" * 80)
    print("UNIT PROGRESSION BY STRATEGY")
    print("=" * 80)

    if "strategy" not in df.columns:
        print("WARNING: strategy column not found")
        return

    strategies = df["strategy"].unique().to_list()

    # Ship categories
    categories = {
        "ETACs": ["etac_ships"],
        "Escorts": ["corvette_ships", "frigate_ships", "destroyer_ships", "light_cruiser_ships"],
        "Medium Capitals": ["cruiser_ships", "heavy_cruiser_ships", "battlecruiser_ships"],
        "Heavy Capitals": ["battleship_ships", "dreadnought_ships", "super_dreadnought_ships"],
        "Support": ["carrier_ships", "super_carrier_ships", "raider_ships", "troop_transport_ships"]
    }

    for strategy in strategies:
        strat_df = df.filter(pl.col("strategy") == strategy)

        print(f"\n{strategy} Strategy:")
        print("-" * 60)

        for category, cols in categories.items():
            available = [c for c in cols if c in df.columns]
            if not available:
                continue

            # Get final turn average
            last_turn_df = strat_df.filter(
                pl.col("turn") == strat_df["turn"].max()
            )

            total = sum(last_turn_df[col].mean() for col in available)
            print(f"  {category:20} Final turn avg: {total:6.2f}")


def main():
    """Run all unit progression analyses."""

    # Check for command line argument (game_id)
    game_id = sys.argv[1] if len(sys.argv) > 1 else None

    # Load diagnostics
    df = load_diagnostics(game_id)

    # Run analyses
    analyze_fleet_composition_by_act(df)
    analyze_etac_by_turn(df)
    analyze_capital_ships_by_turn(df)
    analyze_invasion_capability_by_turn(df)
    analyze_strategy_progression(df)

    print("\n" + "=" * 80)
    print("ANALYSIS COMPLETE")
    print("=" * 80)
    print("\nNext steps:")
    print("1. Check if ETAC production continues past Act 1")
    print("2. Verify capital ships appear in appropriate acts")
    print("3. Confirm invasion capability starts in Act 2")
    print("4. Compare strategies for diversity")
    print("\nSee docs/ai/mechanics/unit-progression.md for expected behavior")

    if game_id:
        print(f"\nTo analyze all games: python {sys.argv[0]}")
    else:
        print(f"\nTo analyze specific game: python {sys.argv[0]} 99999")


if __name__ == "__main__":
    main()
