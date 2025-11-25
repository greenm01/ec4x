#!/usr/bin/env python3
"""
Analyze Phase 2 diagnostic data to find unknown-unknowns.

This script identifies gaps, anomalies, and potential issues by analyzing
diagnostic CSV files from batch game runs.
"""

import polars as pl
import sys
from pathlib import Path

def analyze_diagnostics(diagnostics_dir: Path):
    """Analyze all diagnostic CSV files to find Phase 2 gaps."""

    # Load all CSV files
    csv_files = list(diagnostics_dir.glob("*.csv"))
    if not csv_files:
        print(f"ERROR: No CSV files found in {diagnostics_dir}")
        return

    print(f"Found {len(csv_files)} diagnostic files")

    # Combine all CSVs using Polars - handle schema mismatches
    all_data = []
    for csv_file in csv_files:
        try:
            df = pl.read_csv(csv_file)
            all_data.append(df)
        except Exception as e:
            print(f"WARNING: Failed to read {csv_file}: {e}")

    if not all_data:
        print("ERROR: No valid CSV data found")
        return

    # Concatenate with diagonal to handle schema mismatches (missing columns get nulls)
    df = pl.concat(all_data, how="diagonal")
    print(f"Loaded {len(df)} total diagnostic records")
    print()

    # ========================================================================
    # Phase 2 Gap Analysis
    # ========================================================================

    print("=" * 70)
    print("PHASE 2 GAP ANALYSIS - Looking for Unknown-Unknowns")
    print("=" * 70)
    print()

    # 1. Fighter/Carrier System (Phase 2b)
    print("--- Phase 2b: Fighter/Carrier Ownership ---")
    capacity_violations = df.filter(pl.col('capacity_violations') > 0)
    violation_rate = len(capacity_violations) / len(df) * 100
    print(f"  Capacity Violations: {violation_rate:.2f}% of turns")
    print(f"    ✅ Target: 0% (grace period should prevent all violations)")

    idle_carrier_turns = df.filter(pl.col('idle_carriers') > 0)
    # Safe division: replace 0 with 1 in denominator
    avg_idle_rate = df.select(
        (pl.col('idle_carriers') / pl.col('total_carriers').replace(0, 1))
    ).mean().item() * 100
    print(f"  Idle Carriers: {avg_idle_rate:.2f}% average idle rate")
    print(f"    ✅ Target: <5% (carriers should auto-load fighters)")

    avg_fighters = df.select(pl.col('total_fighters').mean()).item()
    print(f"  Fighter Count: {avg_fighters:.1f} average per house")
    print()

    # 2. Scout Operational Modes (Phase 2c)
    print("--- Phase 2c: Scout Operational Modes ---")
    # Check if scout_count column exists
    if 'scout_count' in df.columns:
        avg_scouts = df.select(pl.col('scout_count').mean()).item()
        scout_turns = df.filter(pl.col('scout_count') >= 5)
        scout_utilization = len(scout_turns) / len(df) * 100
        print(f"  Scout Count: {avg_scouts:.1f} average per house")
        print(f"    ✅ Target: 5-7 scouts for ELI mesh + espionage")
        print(f"  Scout Utilization: {scout_utilization:.1f}% of turns with 5+ scouts")
    else:
        print(f"  ⚠️  scout_count column not found in diagnostics")
        print(f"      (Metric may not be implemented yet)")
    print()

    # 3. Espionage Usage (Phase 2g)
    print("--- Phase 2g: Espionage Mission Targeting ---")
    spy_planet_total = df.select(pl.col('spy_planet').sum()).item()
    hack_starbase_total = df.select(pl.col('hack_starbase').sum()).item()
    total_espionage = df.select(pl.col('total_espionage').sum()).item()

    # Count unique games (approximate: every 100 turns is a new game)
    total_turns = len(df)
    total_games = len(csv_files)  # More accurate: one CSV per game
    games_with_espionage = df.filter(pl.col('total_espionage') > 0).select(
        pl.col('turn').count()
    ).item()

    print(f"  SpyPlanet Missions: {spy_planet_total} total")
    print(f"  HackStarbase Missions: {hack_starbase_total} total")
    print(f"  Total Espionage: {total_espionage} missions")
    print(f"  Turns with Espionage: {games_with_espionage}/{total_turns}")
    print(f"    ✅ Target: 100% games use espionage")
    print()

    # 4. Defense Layering (Phase 2f)
    print("--- Phase 2f: Defense Layering Strategy ---")
    avg_undefended = df.select(
        (pl.col('undefended_colonies') / pl.col('total_colonies').replace(0, 1))
    ).mean().item() * 100
    print(f"  Undefended Colonies: {avg_undefended:.1f}% average")
    print(f"    ✅ Target: <40% (important/frontier colonies defended)")
    print()

    # 5. ELI Mesh Coordination (Phase 2c + 2d)
    print("--- Phase 2c/2d: ELI Mesh & Scout Coordination ---")
    invasions_without_eli = df.select(pl.col('invasions_no_eli').sum()).item()
    total_invasions = df.select(pl.col('total_invasions').sum()).item()
    if total_invasions > 0:
        eli_coverage = (1 - invasions_without_eli / total_invasions) * 100
        print(f"  Invasions with ELI Mesh: {eli_coverage:.1f}%")
        print(f"    ✅ Target: >80% (3+ scouts for mesh network)")
    else:
        print(f"  Invasions: 0 total (no data)")
    print()

    # 6. Fighter Doctrine Research Trigger (Phase 2e)
    print("--- Phase 2e: Fighter Doctrine & ACO Research ---")
    high_fighter_turns = df.filter(pl.col('total_fighters') > 5)
    if len(high_fighter_turns) > 0:
        avg_fighters_when_many = high_fighter_turns.select(
            pl.col('total_fighters').mean()
        ).item()
        print(f"  Fighter Count (when >5): {avg_fighters_when_many:.1f} average")
    else:
        print(f"  Fighter Count (when >5): No data (fighters rarely built)")
    print(f"    Note: FD research triggers at >70% capacity utilization")
    print(f"    Cannot directly measure from diagnostics (need tech levels)")
    print()

    # ========================================================================
    # Unknown-Unknown Detection
    # ========================================================================

    print("=" * 70)
    print("UNKNOWN-UNKNOWN DETECTION")
    print("=" * 70)
    print()

    # Look for anomalies
    print("--- Potential Issues ---")

    # Zero-spend turns (treasury not changing)
    high_zero_spend = df.filter(pl.col('zero_spend_turns') > 10)
    if len(high_zero_spend) > 0:
        print(f"  ⚠️  {len(high_zero_spend)} turns with 10+ consecutive zero-spend turns")
        print(f"      (AI may be hoarding treasury instead of building)")

    # Space combat imbalance
    total_wins = df.select(pl.col('space_wins').sum()).item()
    total_losses = df.select(pl.col('space_losses').sum()).item()
    if total_wins + total_losses > 0:
        win_rate = total_wins / (total_wins + total_losses) * 100
        print(f"  Space Combat: {win_rate:.1f}% win rate (should be ~50% in balanced play)")

    # CLK researched but no Raiders
    clk_no_raiders = df.filter(pl.col('clk_no_raiders') == True)
    if len(clk_no_raiders) > 0:
        print(f"  ⚠️  {len(clk_no_raiders)} turns where CLK researched but no Raiders built")
        print(f"      (Phase 2d should ensure Raiders built when CLK available)")

    # Orbital failures (won space but lost orbital)
    orbital_failures = df.select(pl.col('orbital_failures').sum()).item()
    orbital_total = df.select(pl.col('orbital_total').sum()).item()
    if orbital_total > 0:
        orbital_failure_rate = orbital_failures / orbital_total * 100
        print(f"  Orbital Phase Failures: {orbital_failure_rate:.1f}% (won space but lost orbital)")
        if orbital_failure_rate > 20:
            print(f"      ⚠️  High failure rate suggests starbase strength underestimated")

    # Invalid orders
    invalid_orders = df.select(pl.col('invalid_orders').sum()).item()
    total_orders = df.select(pl.col('total_orders').sum()).item()
    if total_orders > 0:
        invalid_rate = invalid_orders / total_orders * 100
        print(f"  Invalid Orders: {invalid_rate:.2f}% of all orders rejected")
        if invalid_rate > 5:
            print(f"      ⚠️  High rate suggests AI generating invalid commands")

    print()

    # ========================================================================
    # Summary & Recommendations
    # ========================================================================

    print("=" * 70)
    print("SUMMARY & RECOMMENDATIONS")
    print("=" * 70)
    print()

    issues = []

    if violation_rate > 1:
        issues.append("- Capacity violations still occurring (Phase 2b not working)")
    if avg_idle_rate > 10:
        issues.append("- High idle carrier rate (Phase 2b auto-loading not working)")
    if 'scout_count' in df.columns:
        avg_scouts_val = df.select(pl.col('scout_count').mean()).item()
        if avg_scouts_val < 3:
            issues.append("- Low scout count (Phase 2c not building enough scouts)")
    if total_espionage == 0:
        issues.append("- CRITICAL: Zero espionage missions (Phase 2g not working)")
    if avg_undefended > 50:
        issues.append("- High undefended colony rate (Phase 2f defense layering weak)")
    if total_invasions > 0:
        eli_cov = (1 - invasions_without_eli / total_invasions) * 100
        if eli_cov < 50:
            issues.append("- Low ELI mesh coverage (Phase 2c/2d coordination failing)")

    if issues:
        print("🚨 ISSUES FOUND:")
        for issue in issues:
            print(issue)
    else:
        print("✅ All Phase 2 metrics look good!")
        print("   No major unknown-unknowns detected.")

    print()
    print("Recommendation: Review detailed metrics above and investigate any anomalies.")
    print()

if __name__ == "__main__":
    # Check both possible locations
    diagnostics_dir = Path("balance_results/diagnostics")
    if not diagnostics_dir.exists():
        diagnostics_dir = Path("../../balance_results/diagnostics")

    if not diagnostics_dir.exists():
        print(f"ERROR: Diagnostics directory not found")
        print(f"Tried: balance_results/diagnostics and ../../balance_results/diagnostics")
        sys.exit(1)

    analyze_diagnostics(diagnostics_dir)
