#!/usr/bin/env python3
"""
Terminal CLI for balance analysis.

Usage:
    python3 -m analysis.cli summary
    python3 -m analysis.cli by-house
    python3 -m analysis.cli outliers total_fighters
    python3 -m analysis.cli phase2
    python3 -m analysis.cli export summary.csv
"""

import sys
from pathlib import Path

try:
    import click
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich import box
except ImportError:
    print("ERROR: Required packages not installed")
    print("Ensure you're in the nix shell: nix develop")
    sys.exit(1)

from .balance_analyzer import BalanceAnalyzer

console = Console()


@click.group()
@click.option(
    "--parquet",
    default="balance_results/diagnostics_combined.parquet",
    type=click.Path(exists=True),
    help="Path to Parquet file"
)
@click.pass_context
def cli(ctx, parquet):
    """EC4X Balance Analysis - Terminal Interface"""
    ctx.ensure_object(dict)
    try:
        ctx.obj["analyzer"] = BalanceAnalyzer(parquet)
    except Exception as e:
        console.print(f"[red]ERROR:[/red] Failed to load {parquet}")
        console.print(f"[red]{e}[/red]")
        sys.exit(1)


@cli.command()
@click.pass_context
def summary(ctx):
    """Show quick overview of dataset"""
    analyzer = ctx.obj["analyzer"]
    metadata = analyzer.get_metadata()

    # Create summary panel
    summary_text = f"""[cyan]Dataset Info:[/cyan]
  • Parquet: {metadata['parquet_path']}
  • Git hash: {metadata['git_hash']}
  • Timestamp: {metadata['timestamp']}

[cyan]Statistics:[/cyan]
  • Games: {metadata['num_games']}
  • Houses: {metadata['num_houses']}
  • Total turns: {metadata['total_turns']:,}
  • Turns/game: {metadata['turns_per_game']:.1f}

[dim]Use 'phase2' for detailed analysis[/dim]"""

    console.print(Panel(summary_text, title="Balance Analysis Summary", border_style="cyan"))


@cli.command(name="by-house")
@click.option("--metrics", "-m", multiple=True, help="Metrics to include (default: all)")
@click.option("--limit", "-n", default=10, help="Number of rows to display")
@click.pass_context
def by_house(ctx, metrics, limit):
    """Aggregate metrics by house"""
    analyzer = ctx.obj["analyzer"]

    metrics_list = list(metrics) if metrics else None
    df = analyzer.summary_by_house(metrics_list)

    # Limit columns for terminal display
    if len(df.columns) > 10:
        console.print("[yellow]Tip:[/yellow] Use --metrics to select specific columns")
        df = df.select(df.columns[:10])

    # Create rich table
    table = Table(title="Summary by House", box=box.ROUNDED)

    for col in df.columns:
        table.add_column(col, style="cyan" if col == "house" else None)

    for row in df.head(limit).iter_rows():
        table.add_row(*[str(val) if val is not None else "-" for val in row])

    console.print(table)
    console.print(f"\n[dim]Showing {min(limit, len(df))} of {len(df)} rows[/dim]")


@cli.command(name="by-turn")
@click.option("--metrics", "-m", multiple=True, help="Metrics to include (default: all)")
@click.option("--limit", "-n", default=20, help="Number of rows to display")
@click.pass_context
def by_turn(ctx, metrics, limit):
    """Aggregate metrics by turn"""
    analyzer = ctx.obj["analyzer"]

    metrics_list = list(metrics) if metrics else None
    df = analyzer.summary_by_turn(metrics_list)

    # Limit columns for terminal display
    if len(df.columns) > 10:
        console.print("[yellow]Tip:[/yellow] Use --metrics to select specific columns")
        df = df.select(df.columns[:10])

    # Create rich table
    table = Table(title="Summary by Turn", box=box.ROUNDED)

    for col in df.columns:
        table.add_column(col, style="cyan" if col == "turn" else None)

    for row in df.head(limit).iter_rows():
        table.add_row(*[str(val) if val is not None else "-" for val in row])

    console.print(table)
    console.print(f"\n[dim]Showing {min(limit, len(df))} of {len(df)} rows[/dim]")


@cli.command()
@click.argument("metric")
@click.option("--threshold", "-t", default=3.0, help="Z-score threshold")
@click.option("--by-house", is_flag=True, help="Compute per-house z-scores")
@click.option("--limit", "-n", default=20, help="Number of outliers to display")
@click.pass_context
def outliers(ctx, metric, threshold, by_house, limit):
    """Detect outliers using z-score method"""
    analyzer = ctx.obj["analyzer"]

    try:
        df = analyzer.detect_outliers_zscore(metric, threshold, by_house)
    except ValueError as e:
        console.print(f"[red]ERROR:[/red] {e}")
        sys.exit(1)

    if len(df) == 0:
        console.print(f"[green]✓[/green] No outliers found for [cyan]{metric}[/cyan] (threshold={threshold})")
        return

    # Create rich table
    table = Table(
        title=f"Outliers: {metric} (threshold={threshold}, {'per-house' if by_house else 'global'})",
        box=box.ROUNDED
    )

    # Show key columns
    display_cols = ["house", "turn", metric, "z_score"]
    for col in display_cols:
        if col in df.columns:
            style = "red" if col == "z_score" else "cyan" if col in ["house", "turn"] else None
            table.add_column(col, style=style)

    for row in df.head(limit).iter_rows(named=True):
        table.add_row(*[
            f"{row[col]:.2f}" if isinstance(row[col], float) else str(row[col])
            for col in display_cols if col in df.columns
        ])

    console.print(table)
    console.print(f"\n[red]Found {len(df)} outliers[/red] (showing {min(limit, len(df))})")


@cli.command()
@click.pass_context
def phase2(ctx):
    """Run Phase 2 gap analysis"""
    analyzer = ctx.obj["analyzer"]

    console.print("[cyan]Running Phase 2 gap analysis...[/cyan]\n")
    results = analyzer.analyze_phase2_gaps()

    # Display results by phase
    for key in sorted(results.keys()):
        if key.startswith("phase2"):
            phase_data = results[key]
            status = phase_data.get("status", "unknown")

            # Status icon
            status_icon = {
                "pass": "✓",
                "fail": "✗",
                "critical_fail": "🚨",
                "not_implemented": "⚠"
            }.get(status, "?")

            # Status color
            status_color = {
                "pass": "green",
                "fail": "yellow",
                "critical_fail": "red",
                "not_implemented": "dim"
            }.get(status, "white")

            # Build table
            table = Table(title=f"{status_icon} {key.upper()}", box=box.SIMPLE)
            table.add_column("Metric", style="cyan")
            table.add_column("Value")

            for k, v in phase_data.items():
                if k != "status":
                    table.add_row(k, str(v))

            console.print(table)
            console.print()

    # Display anomalies
    if results.get("anomalies"):
        console.print("[bold red]Anomalies Detected:[/bold red]")
        for anomaly in results["anomalies"]:
            severity_icon = "🚨" if anomaly["severity"] == "error" else "⚠"
            severity_color = "red" if anomaly["severity"] == "error" else "yellow"
            console.print(f"  {severity_icon} [{severity_color}]{anomaly['type']}[/{severity_color}]: {anomaly['description']}")
        console.print()

    # Overall status
    overall = results.get("overall_status", "unknown")
    if overall == "all_systems_nominal":
        console.print(Panel("[bold green]✓ ALL SYSTEMS NOMINAL[/bold green]", border_style="green"))
    else:
        issues = results.get("issues_summary", {})
        issue_text = f"""[bold red]🚨 ISSUES FOUND[/bold red]

  • Critical failures: {issues.get('critical_failures', 0)}
  • Phase failures: {issues.get('phase_failures', 0)}
  • Failed phases: {', '.join(issues.get('failed_phases', []))}"""
        console.print(Panel(issue_text, border_style="red"))


@cli.command()
@click.argument("output", type=click.Path())
@click.option("--type", "-t", default="by_house", type=click.Choice(["by_house", "by_turn", "raw"]))
@click.option("--metrics", "-m", multiple=True, help="Metrics to include (default: all)")
@click.pass_context
def export(ctx, output, type, metrics):
    """Export data to CSV for Excel/LibreOffice"""
    analyzer = ctx.obj["analyzer"]

    metrics_list = list(metrics) if metrics else None

    console.print(f"[cyan]Exporting {type} summary to {output}...[/cyan]")

    try:
        output_path = analyzer.export_for_excel(output, type, metrics_list)
        console.print(f"[green]✓[/green] Exported to {output_path}")
    except Exception as e:
        console.print(f"[red]ERROR:[/red] {e}")
        sys.exit(1)


if __name__ == "__main__":
    cli(obj={})
