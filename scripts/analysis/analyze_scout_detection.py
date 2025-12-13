#!/usr/bin/env python3.11
"""
Analyze Scout-on-Scout Detection Mechanics

Examines reconnaissance encounters between scout fleets:
- Detection success rates by house
- ELI tech correlation with detection success
- Scout fleet positioning and encounters
- Asymmetric detection patterns

Usage:
    python3.11 scripts/analysis/analyze_scout_detection.py [--seed SEED]
    python3.11 scripts/analysis/analyze_scout_detection.py --games PATTERN
"""

import polars as pl
import argparse
from pathlib import Path


def analyze_scout_detection(df: pl.DataFrame, game_id: str = "unknown") -> None:
    """Analyze scout detection patterns from game diagnostics."""

    print(f"\n{'='*70}")
    print(f"Scout Detection Analysis - Game {game_id}")
    print(f"{'='*70}")

    # Filter for games with scout detection activity
    scout_activity = df.filter(
        (pl.col("scouts_detected") > 0) | (pl.col("scouts_detected_by") > 0)
    )

    if scout_activity.height == 0:
        print("\n⚠️  No scout-on-scout encounters in this game")
        print("   (Scout fleets from different houses never at same location)")
        return

    # Overall detection stats
    total_detections = df["scouts_detected"].sum()
    total_detected = df["scouts_detected_by"].sum()

    print(f"\n📊 Overall Scout Reconnaissance")
    print(f"{'─'*70}")
    print(f"Total detection events: {total_detections}")
    print(f"Total scouts detected: {total_detected}")
    print(f"Turns with encounters: {scout_activity.height}")

    # Detection by house (observer perspective)
    print(f"\n🔍 Detection Success by House (Observer)")
    print(f"{'─'*70}")
    observer_stats = (
        df.group_by("house")
        .agg([
            pl.col("scouts_detected").sum().alias("total_detected"),
            pl.col("scouts_detected").filter(pl.col("scouts_detected") > 0).count().alias("detection_turns"),
            pl.col("tech_eli").mean().alias("avg_eli"),
            pl.col("scout_ships").mean().alias("avg_scouts")
        ])
        .sort("total_detected", descending=True)
    )

    for row in observer_stats.iter_rows(named=True):
        print(f"{row['house']:20} | "
              f"Detected: {row['total_detected']:3} | "
              f"Turns: {row['detection_turns']:3} | "
              f"Avg ELI: {row['avg_eli']:.1f} | "
              f"Avg Scouts: {row['avg_scouts']:.1f}")

    # Detection by house (target perspective)
    print(f"\n🎯 Times Detected by House (Target)")
    print(f"{'─'*70}")
    target_stats = (
        df.group_by("house")
        .agg([
            pl.col("scouts_detected_by").sum().alias("times_spotted"),
            pl.col("scouts_detected_by").filter(pl.col("scouts_detected_by") > 0).count().alias("spotted_turns"),
            pl.col("tech_eli").mean().alias("avg_eli"),
            pl.col("scout_ships").mean().alias("avg_scouts")
        ])
        .sort("times_spotted", descending=True)
    )

    for row in target_stats.iter_rows(named=True):
        print(f"{row['house']:20} | "
              f"Spotted: {row['times_spotted']:3} | "
              f"Turns: {row['spotted_turns']:3} | "
              f"Avg ELI: {row['avg_eli']:.1f} | "
              f"Avg Scouts: {row['avg_scouts']:.1f}")

    # Scout efficiency ratio (detections / times_detected)
    print(f"\n⚖️  Scout Efficiency Ratio (Detections / Times Spotted)")
    print(f"{'─'*70}")
    efficiency = (
        df.group_by("house")
        .agg([
            pl.col("scouts_detected").sum().alias("detected_others"),
            pl.col("scouts_detected_by").sum().alias("detected_by_others"),
            pl.col("tech_eli").mean().alias("avg_eli")
        ])
        .with_columns([
            (pl.col("detected_others") / pl.col("detected_by_others").clip(1, None))
            .alias("efficiency_ratio")
        ])
        .sort("efficiency_ratio", descending=True)
    )

    for row in efficiency.iter_rows(named=True):
        ratio = row['efficiency_ratio']
        if ratio > 1.5:
            rating = "★★★ Excellent"
        elif ratio > 1.0:
            rating = "★★  Good"
        elif ratio > 0.5:
            rating = "★   Average"
        else:
            rating = "    Poor"

        print(f"{row['house']:20} | "
              f"Ratio: {ratio:5.2f} | "
              f"ELI: {row['avg_eli']:4.1f} | "
              f"{rating}")

    # Detection timeline
    print(f"\n📈 Detection Timeline")
    print(f"{'─'*70}")
    timeline = (
        df.group_by("turn")
        .agg([
            pl.col("scouts_detected").sum().alias("detections"),
            pl.col("scouts_detected_by").sum().alias("spotted"),
            pl.col("scout_ships").sum().alias("total_scouts"),
            pl.col("tech_eli").mean().alias("avg_eli")
        ])
        .filter(
            (pl.col("detections") > 0) | (pl.col("spotted") > 0)
        )
        .sort("turn")
    )

    if timeline.height > 0:
        print(f"{'Turn':5} | {'Detections':10} | {'Spotted':7} | {'Scouts':7} | {'Avg ELI':8}")
        print(f"{'─'*60}")
        for row in timeline.iter_rows(named=True):
            print(f"{row['turn']:5} | "
                  f"{row['detections']:10} | "
                  f"{row['spotted']:7} | "
                  f"{row['total_scouts']:7} | "
                  f"{row['avg_eli']:8.1f}")
    else:
        print("No timeline data available")

    # ELI correlation analysis
    print(f"\n🧪 ELI Tech Correlation")
    print(f"{'─'*70}")
    eli_analysis = (
        df.filter(pl.col("scouts_detected") > 0)
        .group_by("tech_eli")
        .agg([
            pl.col("scouts_detected").sum().alias("total_detections"),
            pl.count().alias("sample_size")
        ])
        .sort("tech_eli")
    )

    if eli_analysis.height > 0:
        print(f"{'ELI Level':10} | {'Detections':11} | {'Sample Size':11}")
        print(f"{'─'*60}")
        for row in eli_analysis.iter_rows(named=True):
            print(f"{row['tech_eli']:10} | "
                  f"{row['total_detections']:11} | "
                  f"{row['sample_size']:11}")
    else:
        print("No ELI correlation data (no detections occurred)")

    # Key insights
    print(f"\n💡 Key Insights")
    print(f"{'─'*70}")

    best_observer = observer_stats.row(0, named=True)
    most_stealthy = target_stats.row(-1, named=True)

    print(f"• Best observer: {best_observer['house']} ({best_observer['total_detected']} detections)")
    print(f"• Most stealthy: {most_stealthy['house']} ({most_stealthy['times_spotted']} times spotted)")

    # Detection formula reminder
    avg_eli_all = df["tech_eli"].mean()
    print(f"\n📝 Detection Formula: 1d20 vs (15 - observerScoutCount + targetELI)")
    print(f"   Average ELI in game: {avg_eli_all:.1f}")
    print(f"   Higher ELI → Harder to detect (better stealth)")
    print(f"   More scout squadrons → Better detection chance")


def main():
    parser = argparse.ArgumentParser(
        description="Analyze scout-on-scout detection mechanics"
    )
    parser.add_argument(
        "--seed", "-s",
        type=int,
        help="Analyze specific game seed"
    )
    parser.add_argument(
        "--games", "-g",
        type=str,
        default="balance_results/diagnostics/game_*.csv",
        help="Game file pattern (default: all games)"
    )

    args = parser.parse_args()

    if args.seed:
        # Analyze specific game
        csv_path = f"balance_results/diagnostics/game_{args.seed}.csv"
        if not Path(csv_path).exists():
            print(f"❌ Game file not found: {csv_path}")
            return 1

        df = pl.read_csv(csv_path)
        analyze_scout_detection(df, game_id=str(args.seed))

    else:
        # Analyze all matching games
        csv_files = list(Path("balance_results/diagnostics").glob("game_*.csv"))

        if not csv_files:
            print(f"❌ No game files found matching: {args.games}")
            return 1

        print(f"📊 Loading {len(csv_files)} game files...")
        df = pl.scan_csv(args.games).collect()

        # Aggregate analysis across all games
        print(f"\n{'='*70}")
        print(f"Multi-Game Scout Detection Analysis ({len(csv_files)} games)")
        print(f"{'='*70}")

        total_detections = df["scouts_detected"].sum()
        total_detected = df["scouts_detected_by"].sum()
        games_with_detections = (
            df.group_by("game_id")
            .agg(pl.col("scouts_detected").sum())
            .filter(pl.col("scouts_detected") > 0)
            .height
        )

        print(f"\n📊 Overall Statistics")
        print(f"{'─'*70}")
        print(f"Total games analyzed: {len(csv_files)}")
        print(f"Games with scout encounters: {games_with_detections}")
        print(f"Total detection events: {total_detections}")
        print(f"Total scouts detected: {total_detected}")

        if total_detections > 0:
            # Run detailed analysis on aggregate data
            analyze_scout_detection(df, game_id=f"{len(csv_files)} games")
        else:
            print("\n⚠️  No scout-on-scout encounters across all games")
            print("   This may indicate:")
            print("   • Short game duration (scouts need time to meet)")
            print("   • Low scout production by AI")
            print("   • Scouts using different systems (avoiding encounters)")

    return 0


if __name__ == "__main__":
    exit(main())
