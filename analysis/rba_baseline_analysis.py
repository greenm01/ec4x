#!/usr/bin/env python3
"""
RBA Baseline Analysis - Current AI Performance

Analyzes existing game CSV data to establish baseline metrics
for comparing against potential GOAP implementation.

Target Metrics (from GOAP docs):
- Wars: 6-15 per 40-turn game
- Invasions: 15-40 per 40-turn game
- Military Budget Act 3: 40-60%
"""

import polars as pl
import sys
from pathlib import Path

def load_game_data(diagnostics_dir: str = "balance_results/diagnostics") -> pl.DataFrame:
    """Load all game CSV files"""
    csv_files = list(Path(diagnostics_dir).glob("game_*.csv"))

    if not csv_files:
        print(f"No CSV files found in {diagnostics_dir}")
        return None

    print(f"Loading {len(csv_files)} game files...")

    # Load all CSVs and add game_id column
    dfs = []
    for csv_file in csv_files:
        game_id = csv_file.stem  # e.g., "game_2000"
        df = pl.read_csv(csv_file)
        df = df.with_columns(pl.lit(game_id).alias("game_id"))
        dfs.append(df)

    return pl.concat(dfs)

def analyze_military_behavior(df: pl.DataFrame) -> dict:
    """Analyze military/aggressive behavior metrics"""

    # Get final turn data for each game/house
    final_turns = df.group_by(["game_id", "house"]).agg([
        pl.col("turn").max().alias("max_turn"),
        pl.col("war_declarations").max().alias("wars"),
        pl.col("total_invasions").max().alias("invasions"),
        pl.col("space_total").max().alias("space_battles"),
        pl.col("orbital_total").max().alias("orbital_bombardments"),
        pl.col("total_ships").last().alias("final_ships"),
        pl.col("total_colonies").last().alias("final_colonies"),
    ])

    return {
        "total_games": final_turns["game_id"].n_unique(),
        "total_houses": len(final_turns),
        "wars_mean": final_turns["wars"].mean(),
        "wars_std": final_turns["wars"].std(),
        "wars_min": final_turns["wars"].min(),
        "wars_max": final_turns["wars"].max(),
        "invasions_mean": final_turns["invasions"].mean(),
        "invasions_std": final_turns["invasions"].std(),
        "invasions_min": final_turns["invasions"].min(),
        "invasions_max": final_turns["invasions"].max(),
        "space_battles_mean": final_turns["space_battles"].mean(),
        "orbital_bombardments_mean": final_turns["orbital_bombardments"].mean(),
    }

def analyze_budget_allocation(df: pl.DataFrame) -> dict:
    """Analyze budget allocation patterns by Act"""

    # Calculate military budget percentage
    # Military = ships + defenses + invasions
    # Need to infer from ship counts and changes

    # For now, use proxy: growth in military assets
    act3_turns = df.filter(pl.col("turn").is_between(25, 35))  # Act 3 roughly

    if len(act3_turns) == 0:
        return {
            "act3_avg_production": 0,
            "act3_avg_treasury": 0,
            "act3_avg_ship_growth": 0,
        }

    # Calculate change in military assets
    act3_summary = act3_turns.group_by(["game_id", "house"]).agg([
        pl.col("total_ships").first().alias("ships_start"),
        pl.col("total_ships").last().alias("ships_end"),
        pl.col("production").mean().alias("avg_production"),
        pl.col("treasury").mean().alias("avg_treasury"),
    ])

    act3_summary = act3_summary.with_columns([
        (pl.col("ships_end") - pl.col("ships_start")).alias("ships_growth")
    ])

    return {
        "act3_avg_production": float(act3_summary["avg_production"].mean() or 0),
        "act3_avg_treasury": float(act3_summary["avg_treasury"].mean() or 0),
        "act3_avg_ship_growth": float(act3_summary["ships_growth"].mean() or 0),
    }

def analyze_game_quality(df: pl.DataFrame) -> dict:
    """Analyze overall game quality metrics"""

    final_state = df.group_by(["game_id", "house"]).agg([
        pl.col("turn").max().alias("max_turn"),
        pl.col("total_colonies").last().alias("final_colonies"),
        pl.col("total_ships").last().alias("final_ships"),
        pl.col("prestige").last().alias("final_prestige"),
        pl.col("defensive_collapse").last().alias("collapsed"),
        pl.col("turns_to_elimination").last().alias("eliminated"),
    ])

    # Count games that reached turn 40
    full_games = final_state.filter(pl.col("max_turn") >= 40)

    return {
        "games_reaching_turn_40": len(full_games),
        "houses_collapsed": final_state["collapsed"].sum(),
        "houses_eliminated": final_state.filter(pl.col("eliminated") > 0).height,
        "avg_final_colonies": final_state["final_colonies"].mean(),
        "avg_final_ships": final_state["final_ships"].mean(),
        "avg_final_prestige": final_state["final_prestige"].mean(),
    }

def generate_report(df: pl.DataFrame) -> str:
    """Generate comprehensive baseline report"""

    military = analyze_military_behavior(df)
    budget = analyze_budget_allocation(df)
    quality = analyze_game_quality(df)

    report = f"""
╔══════════════════════════════════════════════════════════════╗
║           RBA BASELINE ANALYSIS REPORT                       ║
╚══════════════════════════════════════════════════════════════╝

Dataset Overview:
  Total Games:    {military['total_games']}
  Total Houses:   {military['total_houses']}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MILITARY BEHAVIOR ANALYSIS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Wars Declared:
  Mean:       {military['wars_mean']:.1f}
  Std Dev:    {military['wars_std']:.1f}
  Range:      [{military['wars_min']}, {military['wars_max']}]

  Target:     6-15 wars per game
  Status:     {'✅ MEETS TARGET' if 6 <= military['wars_mean'] <= 15 else '❌ BELOW TARGET' if military['wars_mean'] < 6 else '⚠️  ABOVE TARGET'}

Invasions Attempted:
  Mean:       {military['invasions_mean']:.1f}
  Std Dev:    {military['invasions_std']:.1f}
  Range:      [{military['invasions_min']}, {military['invasions_max']}]

  Target:     15-40 invasions per game
  Status:     {'✅ MEETS TARGET' if 15 <= military['invasions_mean'] <= 40 else '❌ BELOW TARGET' if military['invasions_mean'] < 15 else '⚠️  ABOVE TARGET'}

Other Combat:
  Space Battles (avg):         {military['space_battles_mean']:.1f}
  Orbital Bombardments (avg):  {military['orbital_bombardments_mean']:.1f}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BUDGET ALLOCATION (ACT 3)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Production (avg):         {budget['act3_avg_production']:.1f} PP/turn
Treasury (avg):           {budget['act3_avg_treasury']:.1f} PP
Ship Growth (avg):        {budget['act3_avg_ship_growth']:.1f} ships

Note: Detailed budget breakdown requires additional instrumentation

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GAME QUALITY METRICS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Games Reaching Turn 40:   {quality['games_reaching_turn_40']}/{military['total_games']}
Houses Collapsed:         {quality['houses_collapsed']}
Houses Eliminated:        {quality['houses_eliminated']}

Final State (avg):
  Colonies:    {quality['avg_final_colonies']:.1f}
  Ships:       {quality['avg_final_ships']:.1f}
  Prestige:    {quality['avg_final_prestige']:.0f}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GOAP EVALUATION CRITERIA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Current RBA Performance:
  Wars:        {military['wars_mean']:.1f} (target: 6-15)
  Invasions:   {military['invasions_mean']:.1f} (target: 15-40)

Recommendation:
"""

    # Generate recommendation
    wars_ok = 6 <= military['wars_mean'] <= 15
    invasions_ok = 15 <= military['invasions_mean'] <= 40

    if wars_ok and invasions_ok:
        report += """
  ✅ CURRENT RBA MEETS TARGETS

  Consider staying with RBA unless:
  - Strategic decision-making feels too rigid
  - You want emergent GOAP behavior
  - Neural network training needs higher quality data
"""
    elif military['wars_mean'] < 6 or military['invasions_mean'] < 15:
        report += f"""
  ❌ CURRENT RBA BELOW TARGETS

  GOAP could help by:
  - Better multi-turn planning (invasion sequences)
  - Goal-driven war declarations
  - Opportunistic military strategy

  Gaps:
    Wars: {6 - military['wars_mean']:.1f} below minimum
    Invasions: {max(0, 15 - military['invasions_mean']):.1f} below minimum
"""
    else:
        report += """
  ⚠️  CURRENT RBA ABOVE TARGETS

  RBA may be too aggressive. Consider:
  - Tuning aggression thresholds
  - Adding more economic focus
  - GOAP probably won't help here
"""

    report += """

Next Steps:
  1. Review detailed game CSVs for patterns
  2. Run 2-3 day GOAP prototype spike
  3. Compare complexity vs benefit
  4. Make informed decision

Report saved to: analysis/rba_baseline_report.md
"""

    return report

def main():
    df = load_game_data()

    if df is None:
        sys.exit(1)

    print(f"Loaded {len(df)} rows of data")
    print()

    report = generate_report(df)
    print(report)

    # Save report
    Path("analysis").mkdir(exist_ok=True)
    Path("analysis/rba_baseline_report.md").write_text(report)
    print("\n✅ Report saved to analysis/rba_baseline_report.md")

if __name__ == "__main__":
    main()
