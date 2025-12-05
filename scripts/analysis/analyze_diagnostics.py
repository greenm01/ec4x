#!/usr/bin/env python3
"""
EC4X Diagnostics Analysis Tool

Efficient analysis of game diagnostics CSV files using Polars.
Provides quick insights into AI behavior, balance, and performance.

Usage:
    python scripts/analysis/analyze_diagnostics.py [command] [options]

Commands:
    summary         - Quick summary statistics
    strategy        - Strategy performance comparison
    economy         - Economic metrics analysis
    military        - Military metrics analysis
    research        - Research progression analysis
    diplomacy       - Diplomatic relationship analysis
    game-length     - Analyze game length and pacing
    red-flags       - Detect balance issues and anomalies
    compare         - Compare two strategy types
    custom          - Custom query (provide SQL-like expression)

Examples:
    python scripts/analysis/analyze_diagnostics.py summary
    python scripts/analysis/analyze_diagnostics.py strategy --min-turn 10
    python scripts/analysis/analyze_diagnostics.py compare Aggressive Economic
    python scripts/analysis/analyze_diagnostics.py custom "filter(pl.col('prestige') > 500)"
"""

import polars as pl
import sys
from pathlib import Path
from typing import Optional

# Constants
DIAGNOSTICS_DIR = Path("balance_results/diagnostics")
DEFAULT_METRICS = [
    "turn", "house", "strategy", "treasury", "production", "prestige",
    "tech_cst", "tech_wep", "total_ships", "total_colonies"
]

def load_diagnostics(min_turn: int = 0, max_turn: Optional[int] = None) -> pl.DataFrame:
    """Load all diagnostic CSV files into a single DataFrame."""
    csv_files = list(DIAGNOSTICS_DIR.glob("game_*.csv"))

    if not csv_files:
        print(f"Error: No CSV files found in {DIAGNOSTICS_DIR}", file=sys.stderr)
        sys.exit(1)

    print(f"Loading {len(csv_files)} diagnostic files...")

    # Load and concatenate all CSV files
    df = pl.concat([pl.read_csv(f) for f in csv_files])

    # Filter by turn range
    df = df.filter(pl.col("turn") >= min_turn)
    if max_turn:
        df = df.filter(pl.col("turn") <= max_turn)

    print(f"Loaded {len(df)} records from {df['house'].n_unique()} houses across {df['turn'].max()} turns")

    return df

def command_summary(df: pl.DataFrame):
    """Print quick summary statistics."""
    print("\n=== EC4X Diagnostics Summary ===\n")

    print(f"Games analyzed: {len(df['house'].unique())}")
    print(f"Total turns: {df['turn'].max()}")
    print(f"Strategies: {', '.join(df['strategy'].unique().sort())}")

    print("\n--- Final Turn Statistics (Turn {}) ---".format(df['turn'].max()))
    final = df.filter(pl.col("turn") == df["turn"].max())

    print("\nPrestige (Victory Points):")
    print(final.group_by("strategy").agg(
        pl.col("prestige").mean().alias("avg"),
        pl.col("prestige").min().alias("min"),
        pl.col("prestige").max().alias("max"),
        pl.col("prestige").std().alias("std")
    ).sort("avg", descending=True))

    print("\nTreasury (PP):")
    print(final.group_by("strategy").agg(
        pl.col("treasury").mean().alias("avg"),
        pl.col("treasury").min().alias("min"),
        pl.col("treasury").max().alias("max")
    ).sort("avg", descending=True))

    print("\nProduction (PP/turn):")
    print(final.group_by("strategy").agg(
        pl.col("production").mean().alias("avg"),
        pl.col("production").min().alias("min"),
        pl.col("production").max().alias("max")
    ).sort("avg", descending=True))

def command_strategy(df: pl.DataFrame, min_turn: int = 0):
    """Analyze strategy performance over time."""
    print("\n=== Strategy Performance Analysis ===\n")

    # Group by strategy and turn, calculate averages
    strategy_trends = df.group_by(["strategy", "turn"]).agg([
        pl.col("prestige").mean().alias("prestige"),
        pl.col("treasury").mean().alias("treasury"),
        pl.col("production").mean().alias("production"),
        pl.col("total_ships").mean().alias("ships"),
        pl.col("total_colonies").mean().alias("colonies")
    ]).sort(["strategy", "turn"])

    # Print final turn comparison
    final_turn = strategy_trends.filter(pl.col("turn") == df["turn"].max())
    print("Final Turn Comparison:")
    print(final_turn.sort("prestige", descending=True))

    # Calculate win rates (highest prestige at final turn)
    final_df = df.filter(pl.col("turn") == df["turn"].max())

    # Group by game (each game has unique turn+house combination at turn 0)
    # For each game, find the winner (highest prestige)
    games = df.filter(pl.col("turn") == 0).select("house").unique()

    print(f"\n--- Growth Rates (Turn 0 to Final) ---")
    initial = df.filter(pl.col("turn") == min_turn).group_by("strategy").agg([
        pl.col("prestige").mean().alias("prestige_start"),
        pl.col("production").mean().alias("prod_start")
    ])

    final = final_df.group_by("strategy").agg([
        pl.col("prestige").mean().alias("prestige_end"),
        pl.col("production").mean().alias("prod_end")
    ])

    growth = initial.join(final, on="strategy")
    growth = growth.with_columns([
        ((pl.col("prestige_end") - pl.col("prestige_start")) / pl.col("prestige_start") * 100).alias("prestige_growth_%"),
        ((pl.col("prod_end") - pl.col("prod_start")) / pl.col("prod_start") * 100).alias("production_growth_%")
    ])
    print(growth.select(["strategy", "prestige_growth_%", "production_growth_%"]).sort("prestige_growth_%", descending=True))

def command_economy(df: pl.DataFrame):
    """Analyze economic metrics."""
    print("\n=== Economic Analysis ===\n")

    final = df.filter(pl.col("turn") == df["turn"].max())

    print("--- Treasury & Production ---")
    econ = final.group_by("strategy").agg([
        pl.col("treasury").mean().alias("treasury"),
        pl.col("production").mean().alias("production"),
        pl.col("gco").mean().alias("gross_output"),
        pl.col("total_iu").mean().alias("industry"),
        pl.col("tax_rate").mean().alias("tax_rate")
    ]).sort("production", descending=True)
    print(econ)

    print("\n--- Resource Efficiency ---")
    efficiency = final.group_by("strategy").agg([
        (pl.col("production") / pl.col("total_iu")).mean().alias("PP_per_IU"),
        (pl.col("prestige") / pl.col("production")).mean().alias("prestige_per_PP"),
        pl.col("maintenance_cost").mean().alias("maintenance")
    ]).sort("PP_per_IU", descending=True)
    print(efficiency)

    # Detect economic problems
    print("\n--- Economic Red Flags ---")
    problems = df.group_by("house").agg([
        pl.col("zero_spend_turns").max().alias("max_zero_spend"),
        pl.col("treasury_deficit").sum().alias("deficit_turns"),
        pl.col("maintenance_shortfall_turns").max().alias("maintenance_issues")
    ]).filter(
        (pl.col("max_zero_spend") > 3) |
        (pl.col("deficit_turns") > 0) |
        (pl.col("maintenance_issues") > 0)
    )

    if len(problems) > 0:
        print(problems)
    else:
        print("No major economic issues detected!")

def command_military(df: pl.DataFrame):
    """Analyze military metrics."""
    print("\n=== Military Analysis ===\n")

    final = df.filter(pl.col("turn") == df["turn"].max())

    print("--- Fleet Composition ---")
    ships = final.group_by("strategy").agg([
        pl.col("total_ships").mean().alias("total"),
        pl.col("fighter_ships").mean().alias("fighters"),
        pl.col("destroyer_ships").mean().alias("destroyers"),
        pl.col("cruiser_ships").mean().alias("cruisers"),
        pl.col("battleship_ships").mean().alias("battleships"),
        pl.col("carrier_ships").mean().alias("carriers"),
        pl.col("scout_ships").mean().alias("scouts")
    ]).sort("total", descending=True)
    print(ships)

    print("\n--- Combat Performance ---")
    combat = df.group_by("strategy").agg([
        pl.col("space_wins").sum().alias("wins"),
        pl.col("space_losses").sum().alias("losses"),
        (pl.col("space_wins").sum() / pl.col("space_total").sum()).alias("win_rate"),
        pl.col("ground_victories").sum().alias("invasions"),
        pl.col("retreats").sum().alias("retreats")
    ]).sort("win_rate", descending=True)
    print(combat)

    print("\n--- Capacity Violations ---")
    violations = df.group_by("strategy").agg([
        pl.col("fighter_violation").sum().alias("fighter_violations"),
        pl.col("squadron_violation").sum().alias("squadron_violations"),
        pl.col("capacity_violations").sum().alias("capacity_violations"),
        pl.col("fighters_disbanded").sum().alias("fighters_lost")
    ])

    if violations.select(pl.all().sum()).sum_horizontal()[0] > 0:
        print(violations)
    else:
        print("No capacity violations detected!")

def command_research(df: pl.DataFrame):
    """Analyze research progression."""
    print("\n=== Research Analysis ===\n")

    final = df.filter(pl.col("turn") == df["turn"].max())

    print("--- Final Tech Levels ---")
    tech = final.group_by("strategy").agg([
        pl.col("tech_el").mean().alias("EL"),
        pl.col("tech_sl").mean().alias("SL"),
        pl.col("tech_cst").mean().alias("CST"),
        pl.col("tech_wep").mean().alias("WEP"),
        pl.col("tech_eli").mean().alias("ELI"),
        pl.col("tech_clk").mean().alias("CLK")
    ]).sort("CST", descending=True)
    print(tech)

    print("\n--- Research Investment ---")
    investment = df.group_by("strategy").agg([
        pl.col("research_erp").sum().alias("total_ERP"),
        pl.col("research_srp").sum().alias("total_SRP"),
        pl.col("research_trp").sum().alias("total_TRP"),
        pl.col("research_breakthroughs").sum().alias("breakthroughs")
    ]).sort("total_TRP", descending=True)
    print(investment)

    print("\n--- Research Efficiency ---")
    waste = df.group_by("strategy").agg([
        pl.col("research_wasted_erp").sum().alias("wasted_ERP"),
        pl.col("research_wasted_srp").sum().alias("wasted_SRP"),
        (pl.col("research_wasted_erp").sum() / pl.col("research_erp").sum()).alias("ERP_waste_%"),
        (pl.col("research_wasted_srp").sum() / pl.col("research_srp").sum()).alias("SRP_waste_%")
    ]).sort("wasted_ERP")
    print(waste)

def command_diplomacy(df: pl.DataFrame):
    """Analyze diplomatic relationships."""
    print("\n=== Diplomacy Analysis ===\n")

    final = df.filter(pl.col("turn") == df["turn"].max())

    print("--- Diplomatic Position ---")
    diplo = final.group_by("strategy").agg([
        pl.col("ally_count").mean().alias("allies"),
        pl.col("hostile_count").mean().alias("hostiles"),
        pl.col("enemy_count").mean().alias("enemies"),
        pl.col("neutral_count").mean().alias("neutrals")
    ]).sort("allies", descending=True)
    print(diplo)

    print("\n--- Diplomatic Activity ---")
    activity = df.group_by("strategy").agg([
        pl.col("pact_formations").sum().alias("pacts_formed"),
        pl.col("pact_breaks").sum().alias("pacts_broken"),
        pl.col("war_declarations").sum().alias("wars_declared"),
        pl.col("pact_violations").sum().alias("violations"),
        pl.col("dishonored").sum().alias("dishonored")
    ]).sort("wars_declared", descending=True)
    print(activity)

def command_red_flags(df: pl.DataFrame):
    """Detect balance issues and anomalies."""
    print("\n=== Red Flag Detection ===\n")

    flags_found = False

    # 0. Game length variance (check for pacing issues)
    game_lengths = df.group_by("game_id").agg([
        pl.col("turn").max().alias("final_turn")
    ])

    if len(game_lengths) > 0:
        avg_length = game_lengths["final_turn"].mean()
        std_length = game_lengths["final_turn"].std()
        min_length = game_lengths["final_turn"].min()
        max_length = game_lengths["final_turn"].max()

        # Calculate coefficient of variation (CV)
        cv = std_length / avg_length if avg_length > 0 else 0

        # Flag if CV > 30% (high variability in game length)
        if cv > 0.3:
            print(f"⚠️  GAME LENGTH VARIANCE: Games vary widely in length")
            print(f"    Average: {avg_length:.1f} turns (σ={std_length:.1f}, CV={cv:.1%})")
            print(f"    Range: {min_length}-{max_length} turns")
            print(f"    Recommendation: Review prestige scaling or victory thresholds")
            flags_found = True

    # 1. Strategy dominance (>60% win rate)
    final = df.filter(pl.col("turn") == df["turn"].max())
    strategy_prestige = final.group_by("strategy").agg([
        pl.col("prestige").mean().alias("avg_prestige"),
        pl.col("prestige").count().alias("count")
    ]).sort("avg_prestige", descending=True)

    if len(strategy_prestige) > 0:
        top_prestige = strategy_prestige[0, "avg_prestige"]
        for row in strategy_prestige.iter_rows(named=True):
            if row["avg_prestige"] > top_prestige * 1.3:  # 30% better
                print(f"⚠️  DOMINANCE: {row['strategy']} has {row['avg_prestige']:.0f} avg prestige (30%+ above average)")
                flags_found = True

    # 2. Economic stagnation
    stagnant = df.group_by("house").agg([
        pl.col("zero_spend_turns").max().alias("zero_spend"),
        pl.col("pu_growth").sum().alias("total_growth")
    ]).filter(
        (pl.col("zero_spend") > 5) | (pl.col("total_growth") < 100)
    )

    if len(stagnant) > 0:
        print(f"⚠️  STAGNATION: {len(stagnant)} houses with >5 zero-spend turns or <100 population growth")
        flags_found = True

    # 3. Tech waste
    waste = df.group_by("strategy").agg([
        (pl.col("research_wasted_erp").sum() / pl.col("research_erp").sum()).alias("erp_waste"),
        (pl.col("research_wasted_srp").sum() / pl.col("research_srp").sum()).alias("srp_waste")
    ]).filter(
        (pl.col("erp_waste") > 0.2) | (pl.col("srp_waste") > 0.2)
    )

    if len(waste) > 0:
        print(f"⚠️  RESEARCH WASTE: Some strategies wasting >20% of research points")
        print(waste)
        flags_found = True

    # 4. Capacity violations
    violations = df.agg([
        pl.col("capacity_violations").sum().alias("total_violations")
    ])

    if violations[0, "total_violations"] > 0:
        print(f"⚠️  CAPACITY: {violations[0, 'total_violations']} total capacity violations detected")
        flags_found = True

    # 5. Autopilot/collapse
    failures = df.group_by("house").agg([
        pl.col("autopilot").max().alias("autopilot"),
        pl.col("defensive_collapse").max().alias("collapse")
    ]).filter(
        (pl.col("autopilot") > 0) | (pl.col("collapse") > 0)
    )

    if len(failures) > 0:
        print(f"⚠️  AI FAILURE: {len(failures)} houses entered autopilot or defensive collapse")
        flags_found = True

    if not flags_found:
        print("✅ No major red flags detected! Balance looks good.")

def command_compare(df: pl.DataFrame, strategy1: str, strategy2: str):
    """Compare two strategies head-to-head."""
    print(f"\n=== {strategy1} vs {strategy2} ===\n")

    comparison = df.filter(
        pl.col("strategy").is_in([strategy1, strategy2])
    ).filter(
        pl.col("turn") == df["turn"].max()
    ).group_by("strategy").agg([
        pl.col("prestige").mean().alias("prestige"),
        pl.col("treasury").mean().alias("treasury"),
        pl.col("production").mean().alias("production"),
        pl.col("total_ships").mean().alias("ships"),
        pl.col("total_colonies").mean().alias("colonies"),
        pl.col("tech_cst").mean().alias("CST"),
        pl.col("tech_wep").mean().alias("WEP")
    ])

    print(comparison)

    # Calculate % difference
    if len(comparison) == 2:
        s1 = comparison.filter(pl.col("strategy") == strategy1)
        s2 = comparison.filter(pl.col("strategy") == strategy2)

        print(f"\n--- {strategy1} advantage over {strategy2} ---")
        for col in ["prestige", "treasury", "production", "ships", "colonies"]:
            v1 = s1[0, col]
            v2 = s2[0, col]
            diff = ((v1 - v2) / v2 * 100) if v2 > 0 else 0
            print(f"{col:12s}: {diff:+6.1f}%")

def command_game_length(df: pl.DataFrame):
    """Analyze game length statistics and pacing."""
    print("\n=== Game Length Analysis ===\n")

    # Calculate game lengths
    game_lengths = df.group_by("game_id").agg([
        pl.col("turn").max().alias("final_turn")
    ])

    if len(game_lengths) == 0:
        print("No games found in diagnostics data.")
        return

    avg_length = game_lengths["final_turn"].mean()
    std_length = game_lengths["final_turn"].std()
    min_length = game_lengths["final_turn"].min()
    max_length = game_lengths["final_turn"].max()
    cv = std_length / avg_length if avg_length > 0 else 0

    print(f"Total games analyzed: {len(game_lengths)}")
    print(f"\n--- Game Length Distribution ---")
    print(f"Average: {avg_length:.1f} turns")
    print(f"Std Dev: {std_length:.1f} turns (CV: {cv:.1%})")
    print(f"Range: {min_length} - {max_length} turns")
    print(f"Median: {game_lengths['final_turn'].median():.1f} turns")

    # Histogram
    print(f"\n--- Length Histogram ---")
    buckets = [0, 25, 50, 75, 100, 125, 150, 175, 200, 999]
    for i in range(len(buckets) - 1):
        count = game_lengths.filter(
            (pl.col("final_turn") >= buckets[i]) & (pl.col("final_turn") < buckets[i+1])
        ).shape[0]
        if count > 0:
            bar = "█" * int(count / len(game_lengths) * 50)
            print(f"{buckets[i]:3d}-{buckets[i+1]:3d} turns: {bar} ({count} games)")

    # Pacing assessment
    print(f"\n--- Pacing Assessment ---")
    if cv < 0.15:
        print("✅ EXCELLENT: Very consistent game length (CV < 15%)")
    elif cv < 0.3:
        print("✅ GOOD: Acceptable game length variance (CV < 30%)")
    else:
        print("⚠️  WARNING: High game length variance (CV > 30%)")
        print("    This may indicate pacing issues or strategy imbalance")
        print("    Consider reviewing prestige scaling or victory thresholds")

    # Victory type analysis if available
    if "victory_type" in df.columns:
        victories = df.group_by(["game_id", "victory_type"]).agg([
            pl.col("turn").max().alias("final_turn")
        ]).group_by("victory_type").agg([
            pl.col("final_turn").mean().alias("avg_turns"),
            pl.col("game_id").count().alias("count")
        ])

        if len(victories) > 0:
            print(f"\n--- Victory Types ---")
            print(victories.sort("count", descending=True))

def command_custom(df: pl.DataFrame, query: str):
    """Execute custom Polars query."""
    print("\n=== Custom Query ===\n")
    print(f"Query: {query}\n")

    try:
        # Allow user to write Polars expressions
        result = eval(f"df.{query}")
        print(result)
    except Exception as e:
        print(f"Error executing query: {e}", file=sys.stderr)
        print("\nExample queries:", file=sys.stderr)
        print("  filter(pl.col('prestige') > 500)", file=sys.stderr)
        print("  select(['strategy', 'prestige', 'production'])", file=sys.stderr)
        print("  group_by('strategy').agg(pl.col('prestige').mean())", file=sys.stderr)

def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Analyze EC4X diagnostics with Polars")
    parser.add_argument("command", nargs="?", default="summary",
                       choices=["summary", "strategy", "economy", "military",
                               "research", "diplomacy", "game-length", "red-flags", "compare", "custom"],
                       help="Analysis command to run")
    parser.add_argument("--min-turn", type=int, default=0,
                       help="Minimum turn to analyze (default: 0)")
    parser.add_argument("--max-turn", type=int, default=None,
                       help="Maximum turn to analyze (default: all)")
    parser.add_argument("args", nargs="*", help="Additional arguments for command")

    args = parser.parse_args()

    # Load data
    df = load_diagnostics(min_turn=args.min_turn, max_turn=args.max_turn)

    # Execute command
    if args.command == "summary":
        command_summary(df)
    elif args.command == "strategy":
        command_strategy(df, min_turn=args.min_turn)
    elif args.command == "economy":
        command_economy(df)
    elif args.command == "military":
        command_military(df)
    elif args.command == "research":
        command_research(df)
    elif args.command == "diplomacy":
        command_diplomacy(df)
    elif args.command == "game-length":
        command_game_length(df)
    elif args.command == "red-flags":
        command_red_flags(df)
    elif args.command == "compare":
        if len(args.args) < 2:
            print("Error: compare requires two strategy names", file=sys.stderr)
            sys.exit(1)
        command_compare(df, args.args[0], args.args[1])
    elif args.command == "custom":
        if len(args.args) < 1:
            print("Error: custom requires a query expression", file=sys.stderr)
            sys.exit(1)
        command_custom(df, " ".join(args.args))

if __name__ == "__main__":
    main()
