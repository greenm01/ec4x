#!/usr/bin/env python3.11
"""
Analyze RBA unit progression patterns by Act.

Validates that RBA follows the unit-progression.md specification:
- Act 1 (turns 1-7): ETACs, scouts, light escorts, basic defense
- Act 2 (turns 8-15): Capitals, transports, marines, invasion prep
- Act 3 (turns 16-25): Heavy capitals, active invasions, attrition war
- Act 4 (turns 26+): SuperDreadnoughts, PlanetBreakers, total domination

Usage:
    python3.11 scripts/analysis/analyze_unit_progression.py --seed SEED
    python3.11 scripts/analysis/analyze_unit_progression.py -s SEED
    python3.11 scripts/analysis/analyze_unit_progression.py --games PATTERN
"""

import polars as pl
from pathlib import Path
import argparse


def load_diagnostics(game_id: str = None) -> pl.DataFrame:
    """Load diagnostic CSV(s)."""
    if game_id:
        csv_path = f"balance_results/diagnostics/game_{game_id}.csv"
        if not Path(csv_path).exists():
            print(f"❌ File not found: {csv_path}")
            raise SystemExit(1)
        print(f"📊 Loading game {game_id}...")
        df = pl.read_csv(csv_path)
    else:
        path = Path("balance_results/diagnostics")
        if not path.exists():
            print(f"❌ Directory not found: balance_results/diagnostics")
            raise SystemExit(1)
        csv_files = list(path.glob("game_*.csv"))
        if not csv_files:
            print(f"❌ No game_*.csv files found")
            raise SystemExit(1)
        print(f"📊 Loading {len(csv_files)} game files...")
        df = pl.scan_csv(str(path / "game_*.csv")).collect()

    print(f"✓ Loaded {len(df)} rows")
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


def analyze_colonization_by_turn(df: pl.DataFrame) -> None:
    """Analyze colonization patterns turn-by-turn."""

    print("\n" + "=" * 80)
    print("COLONIZATION PROGRESSION BY TURN")
    print("=" * 80)

    if "total_colonies" not in df.columns:
        print("⚠️  total_colonies column not found")
        return

    # Colonization metrics per turn
    colon_by_turn = (
        df.group_by("turn")
        .agg([
            pl.col("total_colonies").mean().alias("avg_colonies"),
            pl.col("total_colonies").max().alias("max_colonies"),
            pl.col("total_colonies").sum().alias("total_colonies"),
            pl.col("colonies_gained_via_colonization").sum().alias("total_colonized") if "colonies_gained_via_colonization" in df.columns else pl.lit(0).alias("total_colonized"),
            pl.col("etac_ships").mean().alias("avg_etacs"),
            pl.col("total_systems_on_map").first().alias("map_size")
        ])
        .sort("turn")
    )

    print("\nTurn | Act    | Avg Colonies | Colonized | Avg ETACs | Map Utilization")
    print("-" * 80)
    for row in colon_by_turn.iter_rows(named=True):
        turn = row["turn"]
        act = classify_act(turn)
        map_size = row["map_size"]
        utilization = (row["total_colonies"] / map_size * 100) if map_size > 0 else 0

        # Flag turns where colonization is slow
        marker = ""
        if act in ["Act1", "Act2"] and utilization < 50:
            marker = "⚠️ "

        print(f"{marker}{turn:4} | {act:6} | {row['avg_colonies']:12.2f} | {row['total_colonized']:9} | {row['avg_etacs']:9.2f} | {utilization:6.1f}%")

    # Summary analysis
    act1_df = df.filter(pl.col("turn") <= 7)
    act2_df = df.filter((pl.col("turn") > 7) & (pl.col("turn") <= 15))

    if len(act1_df) > 0:
        act1_end_colonies = act1_df.filter(pl.col("turn") == 7).select(pl.col("total_colonies").mean()).item()
        act1_end_etacs = act1_df.filter(pl.col("turn") == 7).select(pl.col("etac_ships").mean()).item()

        print(f"\n📊 Act 1 Summary (End of Turn 7):")
        print(f"   Avg colonies: {act1_end_colonies:.2f}")
        print(f"   Avg ETACs: {act1_end_etacs:.2f}")

    if len(act2_df) > 0:
        act2_end_colonies = act2_df.filter(pl.col("turn") == 15).select(pl.col("total_colonies").mean()).item() if 15 in act2_df["turn"].to_list() else None
        act2_end_etacs = act2_df.filter(pl.col("turn") == 15).select(pl.col("etac_ships").mean()).item() if 15 in act2_df["turn"].to_list() else None

        if act2_end_colonies:
            print(f"\n📊 Act 2 Summary (End of Turn 15):")
            print(f"   Avg colonies: {act2_end_colonies:.2f}")
            print(f"   Avg ETACs: {act2_end_etacs:.2f}")

    print("\n⚠️  EXPECTED BEHAVIOR (from unit-progression.md):")
    print("  Act 1: Rapid expansion (ETAC-driven colonization)")
    print("  Turn 7: Should have 50%+ map coverage")
    print("  Turn 15: Should have 75%+ map coverage")


def analyze_etac_efficiency(df: pl.DataFrame) -> None:
    """Analyze ETAC production vs colonization efficiency."""

    print("\n" + "=" * 80)
    print("ETAC EFFICIENCY ANALYSIS")
    print("=" * 80)

    if "etac_ships" not in df.columns or "colonies_gained_via_colonization" not in df.columns:
        print("⚠️  Required columns not found")
        return

    # Per-house ETAC efficiency in Act 1
    act1_df = df.filter(pl.col("turn") <= 7)

    efficiency = (
        act1_df.group_by("house")
        .agg([
            pl.col("etac_ships").max().alias("max_etacs"),
            pl.col("colonies_gained_via_colonization").sum().alias("total_colonized"),
            pl.col("total_colonies").max().alias("final_colonies"),
            pl.col("total_systems_on_map").first().alias("map_size")
        ])
        .with_columns([
            (pl.col("total_colonized") / pl.col("max_etacs").clip(1, None)).alias("colonies_per_etac")
        ])
        .sort("total_colonized", descending=True)
    )

    print("\n🏆 House Colonization Performance (Act 1):")
    print("-" * 80)
    print(f"{'House':20} | {'Max ETACs':9} | {'Colonized':10} | {'Final':6} | {'Efficiency':10}")
    print("-" * 80)

    for row in efficiency.iter_rows(named=True):
        eff = row['colonies_per_etac']
        rating = ""
        if eff >= 1.0:
            rating = "★★★"
        elif eff >= 0.5:
            rating = "★★"
        elif eff >= 0.25:
            rating = "★"

        print(f"{row['house']:20} | {row['max_etacs']:9} | {row['total_colonized']:10} | {row['final_colonies']:6} | {eff:10.2f} {rating}")

    print("\n💡 Efficiency Analysis:")
    print("   • 1.0+ colonies/ETAC = Excellent (each ETAC colonizes)")
    print("   • 0.5+ colonies/ETAC = Good (most ETACs colonize)")
    print("   • <0.5 colonies/ETAC = Poor (ETACs not being used)")


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
        print("❌ etac_ships column not found")
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
        print("⚠️  troop_transport_ships column not found")
        return

    if "marine_division_units" not in df.columns:
        print("⚠️  marine_division_units column not found")
        return

    # Check if we have the detailed breakdown columns
    has_breakdown = "marines_at_colonies" in df.columns and "marines_on_transports" in df.columns

    if has_breakdown:
        invasion_by_turn = (
            df.group_by("turn")
            .agg([
                pl.col("troop_transport_ships").mean().alias("avg_transports"),
                pl.col("marine_division_units").mean().alias("avg_marines"),
                pl.col("marines_at_colonies").mean().alias("avg_colony_marines"),
                pl.col("marines_on_transports").mean().alias("avg_loaded_marines"),
                pl.col("troop_transport_ships").sum().alias("total_transports"),
                pl.col("marine_division_units").sum().alias("total_marines"),
                pl.col("marines_at_colonies").sum().alias("total_colony_marines"),
                pl.col("marines_on_transports").sum().alias("total_loaded_marines")
            ])
            .sort("turn")
        )

        print("\nTurn | Act    | Transports | Marines (Colony/Loaded/Total)")
        print("-" * 70)
        for row in invasion_by_turn.iter_rows(named=True):
            turn = row["turn"]
            act = classify_act(turn)
            marker = "❌" if act == "Act1" and (row["total_transports"] > 0 or row["total_marines"] > 0) else ""
            print(f"{marker}{turn:4} | {act:6} | {row['total_transports']:10} | {row['total_colony_marines']:6}/{row['total_loaded_marines']:6}/{row['total_marines']:6}")
    else:
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
    if has_breakdown:
        print("  Marines auto-load onto transports after recruitment (Colony marines will be ~0)")


def analyze_strategy_progression(df: pl.DataFrame) -> None:
    """Compare unit progression across different strategies."""

    print("\n" + "=" * 80)
    print("UNIT PROGRESSION BY STRATEGY")
    print("=" * 80)

    if "strategy" not in df.columns:
        print("⚠️  strategy column not found")
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

    parser = argparse.ArgumentParser(
        description="Analyze RBA unit progression patterns by Act"
    )
    parser.add_argument(
        "--seed", "-s",
        type=int,
        help="Analyze specific game seed"
    )
    parser.add_argument(
        "--games", "-g",
        type=str,
        help="Game file pattern (default: all games)"
    )

    args = parser.parse_args()

    # Load diagnostics
    game_id = str(args.seed) if args.seed else None
    df = load_diagnostics(game_id)

    # Run analyses
    analyze_colonization_by_turn(df)
    analyze_etac_efficiency(df)
    analyze_fleet_composition_by_act(df)
    analyze_etac_by_turn(df)
    analyze_capital_ships_by_turn(df)
    analyze_invasion_capability_by_turn(df)
    analyze_strategy_progression(df)

    print("\n" + "=" * 80)
    print("ANALYSIS COMPLETE")
    print("=" * 80)
    print("\n✓ Next steps:")
    print("  1. Check if ETAC production continues past Act 1")
    print("  2. Verify capital ships appear in appropriate acts")
    print("  3. Confirm invasion capability starts in Act 2")
    print("  4. Compare strategies for diversity")
    print("\n📖 See docs/ai/mechanics/unit-progression.md for expected behavior")

    if game_id:
        print(f"\n💡 To analyze all games: python3.11 {__file__}")
    else:
        print(f"\n💡 To analyze specific game: python3.11 {__file__} --seed 99")


if __name__ == "__main__":
    main()
