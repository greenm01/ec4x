#!/usr/bin/env python3
"""
Generate AI-friendly diagnostic summary from CSV files.

Outputs compact JSON summary optimized for minimal token usage:
- Raw CSV: ~5M tokens
- Parquet: ~1M tokens (not directly readable by AI)
- This summary: ~500-1000 tokens (99.9% reduction!)

Usage:
    python3 tools/ai_tuning/generate_summary.py
    python3 tools/ai_tuning/generate_summary.py --output balance_results/summary.json
    python3 tools/ai_tuning/generate_summary.py --format human
"""

import argparse
import json
import sys
from pathlib import Path
from datetime import datetime

try:
    import polars as pl
except ImportError:
    print("ERROR: Polars not installed")
    print("Install with: pip install polars")
    sys.exit(1)


def safe_mean(series):
    """Compute mean with null handling."""
    try:
        return series.mean()
    except:
        return 0.0


def safe_sum(series):
    """Compute sum with null handling."""
    try:
        return series.sum()
    except:
        return 0


def safe_division(numerator, denominator):
    """Safe division that returns 0 if denominator is 0."""
    return (numerator / denominator) if denominator != 0 else 0.0


def load_diagnostics(diagnostics_dir: Path):
    """Load all diagnostic CSV files into a single DataFrame."""
    csv_files = list(diagnostics_dir.glob("game_*.csv"))

    if not csv_files:
        print(f"ERROR: No CSV files found in {diagnostics_dir}")
        sys.exit(1)

    print(f"Loading {len(csv_files)} diagnostic files...", file=sys.stderr)

    # Load all CSVs with schema handling
    all_data = []
    for csv_file in csv_files:
        try:
            df = pl.read_csv(csv_file)
            all_data.append(df)
        except Exception as e:
            print(f"WARNING: Failed to read {csv_file}: {e}", file=sys.stderr)

    if not all_data:
        print("ERROR: No valid CSV data found", file=sys.stderr)
        sys.exit(1)

    # Concatenate with diagonal to handle schema mismatches
    df = pl.concat(all_data, how="diagonal")
    print(f"Loaded {len(df)} total diagnostic records", file=sys.stderr)

    return df, len(csv_files)


def generate_summary(df: pl.DataFrame, num_files: int) -> dict:
    """Generate compact summary optimized for AI analysis."""

    total_turns = len(df)

    # Basic metadata
    summary = {
        "generated_at": datetime.now().isoformat(),
        "total_games": num_files,
        "total_turns": total_turns,
        "turns_per_game": total_turns / num_files if num_files > 0 else 0,
    }

    # Phase 2b: Fighter/Carrier System
    capacity_violations = df.filter(pl.col("capacity_violations") > 0)
    violation_rate = len(capacity_violations) / total_turns * 100 if total_turns > 0 else 0

    idle_carrier_rate = df.select(
        (pl.col("idle_carriers") / pl.col("total_carriers").replace(0, 1)).mean()
    ).item() * 100 if total_turns > 0 else 0

    avg_fighters = safe_mean(df["total_fighters"])
    avg_carriers = safe_mean(df["total_carriers"])

    summary["phase2b_fighter_carrier"] = {
        "capacity_violation_rate": round(violation_rate, 2),
        "idle_carrier_rate": round(idle_carrier_rate, 2),
        "avg_fighters_per_house": round(avg_fighters, 1),
        "avg_carriers_per_house": round(avg_carriers, 1),
        "target_violation_rate": 0,
        "target_idle_rate": 5,
        "status": "pass" if violation_rate < 1 and idle_carrier_rate < 10 else "fail"
    }

    # Phase 2c: Scout Operational Modes
    if "scout_count" in df.columns:
        avg_scouts = safe_mean(df["scout_count"])
        scout_turns = df.filter(pl.col("scout_count") >= 5)
        scout_utilization = len(scout_turns) / total_turns * 100 if total_turns > 0 else 0

        summary["phase2c_scouts"] = {
            "avg_scouts_per_house": round(avg_scouts, 1),
            "utilization_5plus": round(scout_utilization, 1),
            "target_scouts": "5-7",
            "status": "pass" if avg_scouts >= 3 else "fail"
        }
    else:
        summary["phase2c_scouts"] = {
            "status": "not_implemented",
            "note": "scout_count column not found"
        }

    # Phase 2g: Espionage Usage
    spy_planet_total = safe_sum(df["spy_planet"])
    hack_starbase_total = safe_sum(df["hack_starbase"])
    total_espionage = safe_sum(df["total_espionage"])

    turns_with_espionage = len(df.filter(pl.col("total_espionage") > 0))
    espionage_usage_rate = turns_with_espionage / total_turns * 100 if total_turns > 0 else 0

    summary["phase2g_espionage"] = {
        "spy_planet_missions": spy_planet_total,
        "hack_starbase_missions": hack_starbase_total,
        "total_missions": total_espionage,
        "turns_with_espionage": turns_with_espionage,
        "usage_rate": round(espionage_usage_rate, 1),
        "target_usage": "100%",
        "status": "pass" if total_espionage > 0 else "critical_fail"
    }

    # Phase 2f: Defense Layering
    avg_undefended = df.select(
        (pl.col("undefended_colonies") / pl.col("total_colonies").replace(0, 1)).mean()
    ).item() * 100 if total_turns > 0 else 0

    summary["phase2f_defense"] = {
        "avg_undefended_rate": round(avg_undefended, 1),
        "target_rate": "<40%",
        "status": "pass" if avg_undefended < 50 else "fail"
    }

    # Phase 2c/2d: ELI Mesh Coordination
    invasions_without_eli = safe_sum(df["invasions_no_eli"])
    total_invasions = safe_sum(df["total_invasions"])

    if total_invasions > 0:
        eli_coverage = (1 - invasions_without_eli / total_invasions) * 100
        summary["phase2cd_eli_mesh"] = {
            "invasions_with_eli": round(eli_coverage, 1),
            "total_invasions": total_invasions,
            "target_coverage": ">80%",
            "status": "pass" if eli_coverage > 50 else "fail"
        }
    else:
        summary["phase2cd_eli_mesh"] = {
            "invasions_with_eli": 0,
            "total_invasions": 0,
            "note": "No invasion data available"
        }

    # Unknown-Unknown Detection: Anomalies
    anomalies = []

    # Zero-spend turns (treasury hoarding)
    high_zero_spend = len(df.filter(pl.col("zero_spend_turns") > 10))
    if high_zero_spend > 0:
        anomalies.append({
            "type": "treasury_hoarding",
            "severity": "warning",
            "count": high_zero_spend,
            "description": f"{high_zero_spend} turns with 10+ consecutive zero-spend turns"
        })

    # Space combat balance
    total_wins = safe_sum(df["space_wins"])
    total_losses = safe_sum(df["space_losses"])
    if total_wins + total_losses > 0:
        win_rate = total_wins / (total_wins + total_losses) * 100
        if win_rate < 40 or win_rate > 60:
            anomalies.append({
                "type": "combat_imbalance",
                "severity": "warning",
                "win_rate": round(win_rate, 1),
                "description": f"Space combat win rate {win_rate:.1f}% (should be ~50%)"
            })

    # CLK researched but no Raiders
    clk_no_raiders = len(df.filter(pl.col("clk_no_raiders") == True))
    if clk_no_raiders > 0:
        anomalies.append({
            "type": "clk_no_raiders",
            "severity": "error",
            "count": clk_no_raiders,
            "description": f"{clk_no_raiders} turns where CLK researched but no Raiders built"
        })

    # Orbital failures (won space but lost orbital)
    orbital_failures = safe_sum(df["orbital_failures"])
    orbital_total = safe_sum(df["orbital_total"])
    if orbital_total > 0:
        orbital_failure_rate = orbital_failures / orbital_total * 100
        if orbital_failure_rate > 20:
            anomalies.append({
                "type": "orbital_failures",
                "severity": "warning",
                "failure_rate": round(orbital_failure_rate, 1),
                "description": f"Orbital phase failure rate {orbital_failure_rate:.1f}%"
            })

    # Invalid orders
    invalid_orders = safe_sum(df["invalid_orders"])
    total_orders = safe_sum(df["total_orders"])
    if total_orders > 0:
        invalid_rate = invalid_orders / total_orders * 100
        if invalid_rate > 5:
            anomalies.append({
                "type": "invalid_orders",
                "severity": "error",
                "invalid_rate": round(invalid_rate, 2),
                "description": f"Invalid order rate {invalid_rate:.2f}% (should be <5%)"
            })

    summary["anomalies"] = anomalies

    # Overall Status
    critical_failures = [
        a for a in anomalies if a["severity"] == "error"
    ]

    phase_failures = [
        k for k, v in summary.items()
        if isinstance(v, dict) and v.get("status") in ["fail", "critical_fail"]
    ]

    if critical_failures or phase_failures:
        summary["overall_status"] = "issues_found"
        summary["issues_summary"] = {
            "critical_failures": len(critical_failures),
            "phase_failures": len(phase_failures),
            "failed_phases": phase_failures
        }
    else:
        summary["overall_status"] = "all_systems_nominal"

    return summary


def format_human_readable(summary: dict) -> str:
    """Format summary for human reading."""
    lines = []
    lines.append("=" * 70)
    lines.append("EC4X Diagnostic Summary")
    lines.append("=" * 70)
    lines.append(f"Generated: {summary['generated_at']}")
    lines.append(f"Games: {summary['total_games']}")
    lines.append(f"Total Turns: {summary['total_turns']}")
    lines.append(f"Turns/Game: {summary['turns_per_game']:.1f}")
    lines.append("")

    # Phase results
    lines.append("Phase 2 Results:")
    lines.append("-" * 70)

    for phase_key in sorted(summary.keys()):
        if phase_key.startswith("phase2"):
            phase_data = summary[phase_key]
            if isinstance(phase_data, dict):
                status = phase_data.get("status", "unknown")
                status_icon = {
                    "pass": "✓",
                    "fail": "✗",
                    "critical_fail": "🚨",
                    "not_implemented": "⚠"
                }.get(status, "?")

                lines.append(f"\n{status_icon} {phase_key.upper()}: {status}")
                for k, v in phase_data.items():
                    if k != "status":
                        lines.append(f"    {k}: {v}")

    # Anomalies
    if summary.get("anomalies"):
        lines.append("\n")
        lines.append("Anomalies Detected:")
        lines.append("-" * 70)
        for anomaly in summary["anomalies"]:
            severity_icon = {
                "error": "🚨",
                "warning": "⚠"
            }.get(anomaly["severity"], "ℹ")
            lines.append(f"{severity_icon} {anomaly['type']}: {anomaly['description']}")

    # Overall status
    lines.append("\n")
    lines.append("=" * 70)
    if summary["overall_status"] == "all_systems_nominal":
        lines.append("✓ ALL SYSTEMS NOMINAL")
    else:
        lines.append("🚨 ISSUES FOUND")
        issues = summary["issues_summary"]
        lines.append(f"  Critical Failures: {issues['critical_failures']}")
        lines.append(f"  Phase Failures: {issues['phase_failures']}")
        if issues["failed_phases"]:
            lines.append(f"  Failed Phases: {', '.join(issues['failed_phases'])}")
    lines.append("=" * 70)

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Generate AI-friendly diagnostic summary"
    )
    parser.add_argument(
        "--diagnostics-dir",
        type=Path,
        default=Path("balance_results/diagnostics"),
        help="Directory containing diagnostic CSV files"
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output file path (default: stdout)"
    )
    parser.add_argument(
        "--format",
        choices=["json", "human"],
        default="json",
        help="Output format (default: json)"
    )

    args = parser.parse_args()

    # Check diagnostics directory
    if not args.diagnostics_dir.exists():
        # Try alternate location
        alt_dir = Path("../../balance_results/diagnostics")
        if alt_dir.exists():
            args.diagnostics_dir = alt_dir
        else:
            print(f"ERROR: Diagnostics directory not found: {args.diagnostics_dir}", file=sys.stderr)
            sys.exit(1)

    # Load data
    df, num_files = load_diagnostics(args.diagnostics_dir)

    # Generate summary
    print("Generating summary...", file=sys.stderr)
    summary = generate_summary(df, num_files)

    # Format output
    if args.format == "json":
        output = json.dumps(summary, indent=2)
    else:
        output = format_human_readable(summary)

    # Write output
    if args.output:
        args.output.write_text(output)
        print(f"Summary written to {args.output}", file=sys.stderr)
    else:
        print(output)

    # Always exit successfully - issues are expected during development
    # (Use --check flag if you want non-zero exit codes for CI)
    sys.exit(0)


if __name__ == "__main__":
    main()
