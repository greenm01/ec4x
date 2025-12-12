#!/usr/bin/env python3
"""
Diagnose the invasion planning pipeline to find where it's breaking.

Checks each stage:
1. SpyPlanet orders generated
2. Colony intelligence gathered
3. Vulnerable targets identified
4. Invasion orders generated
5. Campaigns activated
"""

import polars as pl
import sys
import argparse

def diagnose_pipeline(seed: int):
    """Diagnose invasion pipeline for a specific game."""

    csv_path = f"balance_results/diagnostics/game_{seed}.csv"

    try:
        df = pl.read_csv(csv_path)
    except FileNotFoundError:
        print(f"Error: {csv_path} not found")
        print("Run simulation first: ./bin/run_simulation -s {seed} --fixed-turns -t 35")
        return

    print(f"Invasion Pipeline Diagnosis (game {seed})")
    print("=" * 70)

    # Stage 1: SpyPlanet order generation
    print("\n[STAGE 1] SpyPlanet Orders")
    print("-" * 70)
    columns = df.columns
    spy_cols = ["spy_planet", "hack_starbase", "total_espionage"]
    if "espionage_success" in columns:
        spy_cols.append("espionage_success")

    spy_stats = (
        df.group_by("turn")
        .agg([pl.col(c).sum().alias(f"{c}_total") for c in spy_cols])
        .sort("turn")
        .tail(10)
    )
    print(spy_stats)

    spy_total = df.select(pl.col("spy_planet").sum()).item()
    print(f"\nTotal SpyPlanet orders across all turns: {spy_total}")

    if "espionage_success" in columns:
        success_total = df.select(pl.col("espionage_success").sum()).item()
        print(f"Total espionage successes: {success_total}")
        if spy_total > 0:
            print(f"Success rate: {success_total}/{spy_total} ({success_total/spy_total*100:.1f}%)")
    else:
        print("⚠️  'espionage_success' metric not available - can't verify execution")

    # Stage 2: Intelligence gathering (proxy: vulnerable targets identified)
    print("\n[STAGE 2] Vulnerable Target Identification")
    print("-" * 70)
    vulnerable_stats = (
        df.group_by("turn")
        .agg([
            pl.col("vulnerable_targets_count").sum().alias("vulnerable_targets"),
            pl.col("house").count().alias("houses")
        ])
        .sort("turn")
        .tail(10)
    )
    print(vulnerable_stats)

    vulnerable_total = df.select(
        (pl.col("vulnerable_targets_count") > 0).sum()
    ).item()
    total_rows = len(df)
    print(f"\nHouse-turns with vulnerable targets: {vulnerable_total}/{total_rows} ({vulnerable_total/total_rows*100:.1f}%)")

    # Stage 3: Invasion order generation
    print("\n[STAGE 3] Invasion Orders Generated")
    print("-" * 70)
    invasion_stats = (
        df.group_by("turn")
        .agg([
            pl.col("invasion_orders_bombard").sum().alias("bombard"),
            pl.col("invasion_orders_invade").sum().alias("invade"),
            pl.col("invasion_orders_blitz").sum().alias("blitz"),
            pl.col("invasion_orders_generated").sum().alias("total")
        ])
        .sort("turn")
        .tail(10)
    )
    print(invasion_stats)

    # Stage 4: Campaign activation (check if columns exist)
    print("\n[STAGE 4] Campaign Activation (Phase 2)")
    print("-" * 70)
    columns = df.columns
    if "active_campaigns_total" in columns:
        campaign_cols = ["active_campaigns_total"]
        if "campaigns_started" in columns:
            campaign_cols.extend(["campaigns_started", "campaigns_completed_success", "campaigns_abandoned"])

        campaign_stats = (
            df.group_by("turn")
            .agg([pl.col(c).sum().alias(c) for c in campaign_cols])
            .sort("turn")
            .tail(10)
        )
        print(campaign_stats)
    else:
        print("⚠️  Campaign metrics not available in CSV (may need rebuild)")

    # Stage 5: GOAP invasion planning
    print("\n[STAGE 5] GOAP Invasion Planning (Phase 3)")
    print("-" * 70)
    goap_stats = (
        df.group_by("turn")
        .agg([
            pl.col("goap_invasion_goals").sum().alias("invasion_goals"),
            pl.col("goap_invasion_plans").sum().alias("invasion_plans"),
            pl.col("goap_actions_executed").sum().alias("actions_executed")
        ])
        .sort("turn")
        .tail(10)
    )
    print(goap_stats)

    # Detailed house-by-house breakdown for last turn
    print("\n[DETAILED] Final Turn Breakdown")
    print("-" * 70)
    final_turn = df.select(pl.col("turn").max()).item()

    # Build column list dynamically
    detail_cols = ["house", "spy_planet", "vulnerable_targets_count", "invasion_orders_generated"]
    if "active_campaigns_total" in columns:
        detail_cols.append("active_campaigns_total")
    if "goap_invasion_goals" in columns:
        detail_cols.append("goap_invasion_goals")
    for col in ["total_scouts", "total_ships"]:
        if col in columns:
            detail_cols.append(col)

    # Add military strength columns if available
    for col in ["total_battleships", "total_destroyers", "total_marines", "total_troop_transports"]:
        if col in columns:
            detail_cols.append(col)

    final_data = (
        df.filter(pl.col("turn") == final_turn)
        .select(detail_cols)
    )
    print(final_data)

    # Check overall military capability
    print("\n[MILITARY STRENGTH] Can houses actually invade?")
    print("-" * 70)

    military_cols = ["house"]
    for col in ["total_troop_transports", "total_marines", "total_destroyers", "total_battleships"]:
        if col in columns:
            military_cols.append(col)

    if len(military_cols) > 1:
        military_data = (
            df.filter(pl.col("turn") == final_turn)
            .select(military_cols)
        )
        print(military_data)

        # Check if anyone has invasion capability (transports + marines)
        if "total_troop_transports" in columns and "total_marines" in columns:
            capable = (
                df.filter(pl.col("turn") == final_turn)
                .filter((pl.col("total_troop_transports") > 0) & (pl.col("total_marines") > 0))
                .select(["house", "total_troop_transports", "total_marines"])
            )
            if len(capable) > 0:
                print(f"\n✅ {len(capable)} houses have invasion capability (transports + marines)")
            else:
                print("\n❌ NO houses have invasion capability!")
    else:
        print("⚠️  Military strength metrics not available")

    # Summary diagnosis
    print("\n[DIAGNOSIS]")
    print("=" * 70)

    if spy_total == 0:
        print("❌ FAILURE AT STAGE 1: No SpyPlanet orders generated")
        print("   → Check: exploration_ops.nim line 174 (should be SpyPlanet, not ViewWorld)")
        print("   → Check: Are scouts available? Do reconnaissance targets exist?")
    elif vulnerable_total == 0:
        print("❌ FAILURE AT STAGE 2: SpyPlanet orders exist but no vulnerable targets")
        print("   → SpyPlanet orders: {} per turn".format(spy_total // final_turn if final_turn > 0 else 0))

        if "espionage_success" in columns:
            success_total = df.select(pl.col("espionage_success").sum()).item()
            if success_total == 0:
                print("   → ❌ Espionage success rate: 0% - orders failing!")
                print("   → Check: Espionage resistance/detection mechanics")
                print("   → Check: Are scouts being detected/destroyed?")
            else:
                success_rate = success_total / spy_total * 100 if spy_total > 0 else 0
                print(f"   → Espionage success: {success_total}/{spy_total} ({success_rate:.1f}%)")
                print("   → Orders succeeding but no vulnerable targets found")
                print("   → LIKELY CAUSE: Colony analyzer thresholds too strict")
                print()
                print("   → Check colony_analyzer.nim:")
                print("      - Defense ratio threshold (currently 0.5)")
                print("      - Prestige value threshold (currently 30)")
                print("      - Are enemy colonies actually weak enough?")
                print()
                print("   → Verify intelligence.colonyReports is populated:")
                print("      - Add debug logging in colony_analyzer.nim line 42")
                print("      - Log: \"Processing X colony intel reports\"")
        else:
            print("   → Cannot verify espionage execution (no success metric)")
            print("   → Check: Are SpyPlanet orders being executed by engine?")
            print("   → Check: intelligence.colonyReports being populated?")
            print("   → Check: colony_analyzer.nim threshold logic")
    elif df.select(pl.col("invasion_orders_invade").sum()).item() == 0:
        print("❌ FAILURE AT STAGE 3: Vulnerable targets found but no Invade orders")
        print("   → Check: offensive_ops.nim invasion order generation")
        print("   → Check: Are TroopTransports and Marines available?")
    elif "active_campaigns_total" in columns and df.select(pl.col("active_campaigns_total").sum()).item() == 0:
        print("❌ FAILURE AT STAGE 4: Orders exist but campaigns not activating")
        print("   → Check: Campaign state machine in controller.nim")
        print("   → Check: Campaign creation conditions (line 746)")
    else:
        print("⚠️  ALL STAGES GENERATING DATA - but no conquests")
        print("   → Possible execution issue: Orders generated but not executed?")
        print("   → Check: Engine processing of Invade orders")
        print("   → Check: Combat strength calculations")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Diagnose invasion planning pipeline")
    parser.add_argument("--seed", "-s", type=int, default=12345,
                        help="Game seed to analyze (default: 12345)")
    args = parser.parse_args()

    diagnose_pipeline(args.seed)
