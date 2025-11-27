#!/usr/bin/env python3
"""
Markdown Report Generation

Generate git-committable markdown reports from balance analysis.

Usage:
    from analysis.reports import generate_markdown_report

    generate_markdown_report(
        parquet_path="balance_results/diagnostics_combined.parquet",
        output_path="balance_results/analysis_report.md"
    )
"""

from pathlib import Path
from datetime import datetime
from typing import List, Optional

from .balance_analyzer import BalanceAnalyzer


def format_table_row(values: List[str], widths: List[int]) -> str:
    """Format a markdown table row with proper padding."""
    return "| " + " | ".join(
        str(v).ljust(w) for v, w in zip(values, widths)
    ) + " |"


def format_status_badge(status: str) -> str:
    """Format status as emoji badge."""
    badges = {
        "pass": "✅ PASS",
        "fail": "⚠️ FAIL",
        "critical_fail": "🚨 CRITICAL",
        "not_implemented": "⏸️ N/A"
    }
    return badges.get(status, "❓ UNKNOWN")


def generate_phase2_section(results: dict) -> str:
    """Generate Phase 2 analysis section."""
    lines = []
    lines.append("## Phase 2 Gap Analysis\n")

    # Phase results
    for key in sorted(results.keys()):
        if key.startswith("phase2"):
            phase_data = results[key]
            status = phase_data.get("status", "unknown")

            lines.append(f"### {key.upper()}\n")
            lines.append(f"**Status:** {format_status_badge(status)}\n")

            # Build table
            lines.append("| Metric | Value |")
            lines.append("|--------|-------|")
            for k, v in phase_data.items():
                if k != "status":
                    lines.append(f"| {k} | {v} |")

            lines.append("")

    # Anomalies
    if results.get("anomalies"):
        lines.append("### Anomalies Detected\n")
        for anomaly in results["anomalies"]:
            severity_badge = "🚨 ERROR" if anomaly["severity"] == "error" else "⚠️ WARNING"
            lines.append(f"- **{severity_badge}** - `{anomaly['type']}`: {anomaly['description']}")
        lines.append("")

    # Overall status
    overall = results.get("overall_status", "unknown")
    if overall == "all_systems_nominal":
        lines.append("### Overall Status\n")
        lines.append("✅ **ALL SYSTEMS NOMINAL** - No critical issues detected.\n")
    else:
        issues = results.get("issues_summary", {})
        lines.append("### Overall Status\n")
        lines.append("🚨 **ISSUES FOUND**\n")
        lines.append(f"- Critical failures: {issues.get('critical_failures', 0)}")
        lines.append(f"- Phase failures: {issues.get('phase_failures', 0)}")
        if issues.get("failed_phases"):
            lines.append(f"- Failed phases: {', '.join(issues['failed_phases'])}")
        lines.append("")

    return "\n".join(lines)


def generate_outlier_section(analyzer: BalanceAnalyzer, metrics: List[str], threshold: float = 3.0) -> str:
    """Generate outlier detection section."""
    lines = []
    lines.append("## Outlier Detection\n")
    lines.append(f"**Method:** Z-score (threshold={threshold})\n")

    for metric in metrics:
        try:
            outliers = analyzer.detect_outliers_zscore(metric, threshold)

            if len(outliers) > 0:
                lines.append(f"### {metric}\n")
                lines.append(f"**Found {len(outliers)} outliers**\n")

                # Show top 5
                lines.append("| House | Turn | Value | Z-Score |")
                lines.append("|-------|------|-------|---------|")

                for row in outliers.head(5).iter_rows(named=True):
                    house = row.get("house", "-")
                    turn = row.get("turn", "-")
                    value = row.get(metric, "-")
                    zscore = row.get("z_score", "-")

                    # Format values
                    if isinstance(value, float):
                        value = f"{value:.2f}"
                    if isinstance(zscore, float):
                        zscore = f"{zscore:.2f}"

                    lines.append(f"| {house} | {turn} | {value} | {zscore} |")

                if len(outliers) > 5:
                    lines.append(f"\n*...and {len(outliers) - 5} more*\n")

                lines.append("")
        except Exception as e:
            lines.append(f"### {metric}\n")
            lines.append(f"⚠️ Error: {e}\n")

    if all("Error" in line or "outliers**" not in line for line in lines if line.startswith("###")):
        lines.append("✅ No significant outliers detected.\n")

    return "\n".join(lines)


def generate_summary_section(analyzer: BalanceAnalyzer) -> str:
    """Generate summary statistics section."""
    lines = []
    metadata = analyzer.get_metadata()

    lines.append("## Dataset Summary\n")
    lines.append("| Metric | Value |")
    lines.append("|--------|-------|")
    lines.append(f"| Git Hash | `{metadata['git_hash']}` |")
    lines.append(f"| Timestamp | {metadata['timestamp']} |")
    lines.append(f"| Total Games | {metadata['num_games']} |")
    lines.append(f"| Total Houses | {metadata['num_houses']} |")
    lines.append(f"| Total Turns | {metadata['total_turns']:,} |")
    lines.append(f"| Turns/Game | {metadata['turns_per_game']:.1f} |")
    lines.append(f"| Parquet Path | `{metadata['parquet_path']}` |")
    lines.append("")

    return "\n".join(lines)


def generate_markdown_report(
    parquet_path: Path | str,
    output_path: Path | str,
    outlier_metrics: Optional[List[str]] = None,
    outlier_threshold: float = 3.0
) -> Path:
    """
    Generate comprehensive markdown report.

    Args:
        parquet_path: Path to Parquet diagnostics file
        output_path: Path to output markdown file
        outlier_metrics: Metrics to check for outliers (default: key metrics)
        outlier_threshold: Z-score threshold for outliers

    Returns:
        Path to generated report
    """
    parquet_path = Path(parquet_path)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Default outlier metrics
    if outlier_metrics is None:
        outlier_metrics = [
            "total_fighters",
            "total_carriers",
            "capacity_violations",
            "idle_carriers",
            "total_espionage",
            "invalid_orders",
            "zero_spend_turns"
        ]

    # Load analyzer
    analyzer = BalanceAnalyzer(parquet_path)

    # Build report
    lines = []
    lines.append(f"# Balance Analysis Report\n")
    lines.append(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    lines.append("---\n")

    # Summary
    lines.append(generate_summary_section(analyzer))

    # Phase 2 analysis
    phase2_results = analyzer.analyze_phase2_gaps()
    lines.append(generate_phase2_section(phase2_results))

    # Outliers
    lines.append(generate_outlier_section(analyzer, outlier_metrics, outlier_threshold))

    # Footer
    lines.append("---\n")
    lines.append("*Generated by EC4X Balance Analysis System*\n")

    # Write report
    report_content = "\n".join(lines)
    output_path.write_text(report_content)

    return output_path


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python3 -m analysis.reports <parquet_file> [output_file]")
        sys.exit(1)

    parquet_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else "balance_results/analysis_report.md"

    report_path = generate_markdown_report(parquet_path, output_path)
    print(f"Report generated: {report_path}")
