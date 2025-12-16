#!/usr/bin/env python3.11
"""
Analyze Scout Detection and Espionage Mission Mechanics

Examines two types of intelligence operations:
1. Scout-on-Scout Detection (reconnaissance encounters)
2. Espionage Mission Detection (spy missions detected/destroyed)

Usage:
    python3.11 scripts/analysis/analyze_scout_detection.py --seed SEED
    python3.11 scripts/analysis/analyze_scout_detection.py -s SEED
    python3.11 scripts/analysis/analyze_scout_detection.py --games PATTERN
"""

import polars as pl
import argparse
from pathlib import Path


def analyze_espionage_missions(df: pl.DataFrame, game_id: str = "unknown") -> None:
    """Analyze espionage mission outcomes and detection patterns."""

    print(f"\n{'='*70}")
    print(f"Espionage Mission Analysis - Game {game_id}")
    print(f"{'='*70}")

    # Check if there are any espionage operations
    total_ops = (
        df["espionage_success"].sum() +
        df["espionage_failure"].sum() +
        df["espionage_detected"].sum()
    )

    if total_ops == 0:
        print("\n⚠️  No espionage operations in this game")
        return

    # Overall espionage statistics
    print(f"\n📊 Overall Espionage Operations")
    print(f"{'─'*70}")
    print(f"Total operations: {total_ops}")
    print(f"  Successful: {df['espionage_success'].sum()}")
    print(f"  Failed: {df['espionage_failure'].sum()}")
    print(f"  Detected: {df['espionage_detected'].sum()}")

    success_rate = (df["espionage_success"].sum() / total_ops * 100) if total_ops > 0 else 0
    detection_rate = (df["espionage_detected"].sum() / total_ops * 100) if total_ops > 0 else 0

    print(f"\nSuccess rate: {success_rate:.1f}%")
    print(f"Detection rate: {detection_rate:.1f}%")

    # Espionage by house
    print(f"\n🕵️  Espionage Performance by House")
    print(f"{'─'*70}")
    house_esp = (
        df.group_by("house")
        .agg([
            pl.col("espionage_success").sum().alias("success"),
            pl.col("espionage_failure").sum().alias("failure"),
            pl.col("espionage_detected").sum().alias("detected"),
            pl.col("tech_eli").mean().alias("avg_eli"),
            pl.col("tech_clk").mean().alias("avg_clk"),
            pl.col("tech_cic").mean().alias("avg_cic"),
            pl.col("spy_planet").sum().alias("spy_missions"),
            pl.col("hack_starbase").sum().alias("hack_missions")
        ])
        .with_columns([
            (pl.col("success") + pl.col("failure") + pl.col("detected")).alias("total_ops")
        ])
        .filter(pl.col("total_ops") > 0)
        .sort("success", descending=True)
    )

    if house_esp.height == 0:
        print("No espionage data available")
        return

    print(f"{'House':20} | {'Success':7} | {'Fail':4} | {'Detected':8} | {'ELI':4} | {'CLK':4} | {'CIC':4}")
    print(f"{'─'*80}")
    for row in house_esp.iter_rows(named=True):
        success_pct = (row['success'] / row['total_ops'] * 100) if row['total_ops'] > 0 else 0
        print(f"{row['house']:20} | "
              f"{row['success']:7} | "
              f"{row['failure']:4} | "
              f"{row['detected']:8} | "
              f"{row['avg_eli']:4.1f} | "
              f"{row['avg_clk']:4.1f} | "
              f"{row['avg_cic']:4.1f}")

    # Mission type breakdown
    print(f"\n🎯 Mission Type Distribution")
    print(f"{'─'*70}")
    mission_types = (
        df.group_by("house")
        .agg([
            pl.col("spy_planet").sum().alias("spy_planet"),
            pl.col("hack_starbase").sum().alias("hack_starbase"),
            pl.col("espionage_success").sum().alias("success")
        ])
        .filter((pl.col("spy_planet") > 0) | (pl.col("hack_starbase") > 0))
        .sort("success", descending=True)
    )

    if mission_types.height > 0:
        print(f"{'House':20} | {'SpyPlanet':10} | {'HackStarbase':12} | {'Total':5}")
        print(f"{'─'*70}")
        for row in mission_types.iter_rows(named=True):
            total = row['spy_planet'] + row['hack_starbase']
            print(f"{row['house']:20} | "
                  f"{row['spy_planet']:10} | "
                  f"{row['hack_starbase']:12} | "
                  f"{total:5}")

    # Mission duration analysis (estimate via scout count changes)
    print(f"\n⏱️  Mission Duration Analysis")
    print(f"{'─'*70}")

    # Track scout count changes to estimate mission lifetimes
    duration_data = []
    for house in df["house"].unique():
        house_df = df.filter(pl.col("house") == house).sort("turn")

        if house_df.height < 2:
            continue

        # Calculate turn-over-turn changes in active missions
        scout_counts = house_df["scout_count"].to_list()
        turns = house_df["turn"].to_list()

        missions_started = 0
        missions_ended = 0
        total_mission_turns = 0

        for i in range(1, len(scout_counts)):
            prev_count = scout_counts[i-1]
            curr_count = scout_counts[i]

            if curr_count > prev_count:
                missions_started += (curr_count - prev_count)
            elif curr_count < prev_count:
                missions_ended += (prev_count - curr_count)

            # Accumulate active mission-turns
            total_mission_turns += curr_count

        if missions_ended > 0:
            avg_duration = total_mission_turns / missions_ended
            duration_data.append({
                "house": house,
                "missions_ended": missions_ended,
                "avg_duration": avg_duration
            })

    if duration_data:
        print(f"{'House':20} | {'Missions Ended':14} | {'Avg Duration':12}")
        print(f"{'─'*70}")
        for data in sorted(duration_data, key=lambda x: x['avg_duration'], reverse=True):
            print(f"{data['house']:20} | "
                  f"{data['missions_ended']:14} | "
                  f"{data['avg_duration']:12.1f} turns")
    else:
        print("Insufficient data for mission duration estimation")

    # Detection correlation with tech levels
    print(f"\n🔬 Detection vs Counter-Intelligence Tech")
    print(f"{'─'*70}")

    # Analyze detection rates by CIC level
    detection_by_cic = (
        df.filter(
            (pl.col("espionage_detected") > 0) |
            (pl.col("espionage_success") > 0) |
            (pl.col("espionage_failure") > 0)
        )
        .group_by("tech_cic")
        .agg([
            pl.col("espionage_detected").sum().alias("detected"),
            pl.col("espionage_success").sum().alias("success"),
            pl.col("espionage_failure").sum().alias("failure"),
            pl.len().alias("sample_size")
        ])
        .with_columns([
            ((pl.col("detected") / (pl.col("detected") + pl.col("success") + pl.col("failure"))) * 100)
            .alias("detection_rate")
        ])
        .sort("tech_cic")
    )

    if detection_by_cic.height > 0:
        print(f"{'CIC Lvl':7} | {'Detected':8} | {'Success':7} | {'Failed':6} | {'Detection %':11}")
        print(f"{'─'*70}")
        for row in detection_by_cic.iter_rows(named=True):
            print(f"{row['tech_cic']:7} | "
                  f"{row['detected']:8} | "
                  f"{row['success']:7} | "
                  f"{row['failure']:6} | "
                  f"{row['detection_rate']:10.1f}%")

    # Key insights
    print(f"\n💡 Key Insights")
    print(f"{'─'*70}")

    if house_esp.height > 0:
        best_spy = house_esp.row(0, named=True)
        print(f"• Most successful: {best_spy['house']} ({best_spy['success']} successes)")

        most_detected = house_esp.sort("detected", descending=True).row(0, named=True)
        print(f"• Most detected: {most_detected['house']} ({most_detected['detected']} times)")

    print(f"\n📝 Espionage Detection Factors:")
    print(f"   • Higher CLK → Better mission stealth (harder to detect)")
    print(f"   • Higher CIC (defender) → Better counter-intelligence (more detections)")
    print(f"   • ELI → Helps detect enemy scouts, not direct mission detection")


def analyze_scout_detection(df: pl.DataFrame, game_id: str = "unknown") -> None:
    """Analyze scout-on-scout detection patterns from game diagnostics."""

    print(f"\n{'='*70}")
    print(f"Scout-on-Scout Detection Analysis - Game {game_id}")
    print(f"{'='*70}")

    # Filter for games with scout detection activity
    scout_activity = df.filter(
        (pl.col("scouts_detected") > 0) | (pl.col("scouts_detected_by") > 0)
    )

    if scout_activity.height == 0:
        print("\n⚠️  No scout-on-scout encounters in this game")
        print("   (Scout-only fleets from different houses never at same location)")
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
            pl.len().alias("sample_size")
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
        description="Analyze scout detection and espionage mission mechanics"
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
    parser.add_argument(
        "--espionage-only",
        action="store_true",
        help="Only show espionage mission analysis (skip scout-on-scout)"
    )
    parser.add_argument(
        "--reconnaissance-only",
        action="store_true",
        help="Only show scout-on-scout analysis (skip espionage missions)"
    )

    args = parser.parse_args()

    if args.seed:
        # Analyze specific game
        csv_path = f"balance_results/diagnostics/game_{args.seed}.csv"
        if not Path(csv_path).exists():
            print(f"❌ Game file not found: {csv_path}")
            return 1

        df = pl.read_csv(csv_path)

        # Run both analyses unless filtered
        if not args.reconnaissance_only:
            analyze_espionage_missions(df, game_id=str(args.seed))

        if not args.espionage_only:
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
        print(f"Multi-Game Intelligence Analysis ({len(csv_files)} games)")
        print(f"{'='*70}")

        total_esp_ops = (
            df["espionage_success"].sum() +
            df["espionage_failure"].sum() +
            df["espionage_detected"].sum()
        )
        total_scout_detections = df["scouts_detected"].sum()

        print(f"\n📊 Overall Statistics")
        print(f"{'─'*70}")
        print(f"Total games analyzed: {len(csv_files)}")
        print(f"Espionage operations: {total_esp_ops}")
        print(f"Scout-on-scout detections: {total_scout_detections}")

        # Run analyses
        if not args.reconnaissance_only and total_esp_ops > 0:
            analyze_espionage_missions(df, game_id=f"{len(csv_files)} games")

        if not args.espionage_only and total_scout_detections > 0:
            analyze_scout_detection(df, game_id=f"{len(csv_files)} games")

        if total_esp_ops == 0 and total_scout_detections == 0:
            print("\n⚠️  No intelligence operations across all games")

    return 0


if __name__ == "__main__":
    exit(main())
