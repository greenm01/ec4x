#!/usr/bin/env python3
"""
Convert diagnostic CSV files to Parquet format.

Benefits:
- 3-5x smaller file size (columnar compression)
- Instant loading for analysis (no parsing)
- Preserves type information (no string conversion)
- Better for sharing with AI (fewer tokens when uploaded)
- Parallel loading using all CPU cores

Usage:
    python3 tools/ai_tuning/convert_to_parquet.py
    python3 tools/ai_tuning/convert_to_parquet.py --output balance_results/diagnostics_combined.parquet
"""

import argparse
import sys
import subprocess
from pathlib import Path
from datetime import datetime

try:
    import polars as pl
except ImportError:
    print("ERROR: Polars not installed")
    print("Install with: pip install polars")
    sys.exit(1)

try:
    from rich.console import Console
    from rich.progress import track
    from rich.panel import Panel
    HAVE_RICH = True
except ImportError:
    HAVE_RICH = False

console = Console() if HAVE_RICH else None


def get_git_hash() -> str:
    """Get current git commit hash"""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except:
        return "unknown"


def convert_to_parquet(diagnostics_dir: Path, output_path: Path) -> None:
    """Convert all CSV files to a single Parquet file with parallel loading."""

    # Find all CSV files
    csv_files = sorted(list(diagnostics_dir.glob("game_*.csv")))

    if not csv_files:
        if HAVE_RICH:
            console.print(f"[red]ERROR:[/red] No CSV files found in {diagnostics_dir}")
        else:
            print(f"ERROR: No CSV files found in {diagnostics_dir}")
        sys.exit(1)

    if HAVE_RICH:
        console.print(f"\n[bold]Found {len(csv_files)} CSV files[/bold]")
        console.print(f"Loading with parallel processing...\n")
    else:
        print(f"Loading {len(csv_files)} CSV files...")

    # Load all CSVs in parallel using lazy loading
    # scan_csv is lazy (doesn't load data), concat + collect parallelizes
    all_data = []
    iterator = track(csv_files, description="Scanning CSVs") if HAVE_RICH else csv_files

    for csv_file in iterator:
        try:
            # Lazy load - doesn't read data yet
            df = pl.scan_csv(csv_file)
            all_data.append(df)
        except Exception as e:
            msg = f"WARNING: Failed to scan {csv_file.name}: {e}"
            if HAVE_RICH:
                console.print(f"[yellow]{msg}[/yellow]")
            else:
                print(msg)

    if not all_data:
        if HAVE_RICH:
            console.print("[red]ERROR:[/red] No valid CSV data found")
        else:
            print("ERROR: No valid CSV data found")
        sys.exit(1)

    # Concatenate and collect - THIS is where parallel processing happens
    if HAVE_RICH:
        console.print("[bold]Combining data (parallel processing)...[/bold]")
    else:
        print("Combining data...")

    # concat with diagonal handles schema mismatches, collect() parallelizes
    df = pl.concat(all_data, how="diagonal").collect()

    # Add metadata columns
    df = df.with_columns([
        pl.lit(get_git_hash()).alias("_git_hash"),
        pl.lit(datetime.now().isoformat()).alias("_timestamp"),
    ])

    # Write to Parquet with statistics enabled
    if HAVE_RICH:
        console.print(f"[bold]Writing {len(df):,} rows to Parquet...[/bold]")
    else:
        print(f"Writing {len(df):,} rows to {output_path}...")

    df.write_parquet(
        output_path,
        compression="zstd",  # Best for Excel compatibility
        statistics=True,      # Enable predicate pushdown for fast queries
    )

    # Report statistics
    csv_total_size = sum(f.stat().st_size for f in csv_files)
    parquet_size = output_path.stat().st_size
    compression_ratio = csv_total_size / parquet_size if parquet_size > 0 else 0

    # Pretty output
    if HAVE_RICH:
        summary = f"""[bold green]✓ Conversion Complete![/bold green]

[cyan]Input:[/cyan]
  • {len(csv_files)} CSV files
  • {csv_total_size / 1024 / 1024:.1f} MB total size

[cyan]Output:[/cyan]
  • {output_path}
  • {parquet_size / 1024 / 1024:.1f} MB
  • {len(df):,} rows × {len(df.columns)} columns
  • [bold]{compression_ratio:.1f}x[/bold] compression ratio

[cyan]Metadata:[/cyan]
  • Git hash: {get_git_hash()}
  • Timestamp: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}

[dim]Next: nimble balanceSummary[/dim]"""

        console.print(Panel(summary, title="Parquet Conversion", border_style="green"))
    else:
        print("=" * 70)
        print("Conversion Complete!")
        print("=" * 70)
        print(f"CSV files:       {len(csv_files)} files, {csv_total_size / 1024 / 1024:.1f} MB")
        print(f"Parquet output:  {parquet_size / 1024 / 1024:.1f} MB")
        print(f"Compression:     {compression_ratio:.1f}x smaller")
        print(f"Rows:            {len(df):,}")
        print(f"Columns:         {len(df.columns)}")
        print(f"Git hash:        {get_git_hash()}")
        print("=" * 70)


def main():
    parser = argparse.ArgumentParser(
        description="Convert diagnostic CSV files to Parquet"
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
        default=Path("balance_results/diagnostics_combined.parquet"),
        help="Output Parquet file path"
    )

    args = parser.parse_args()

    # Check diagnostics directory
    if not args.diagnostics_dir.exists():
        print(f"ERROR: Diagnostics directory not found: {args.diagnostics_dir}")
        sys.exit(1)

    # Create output directory
    args.output.parent.mkdir(parents=True, exist_ok=True)

    # Convert
    convert_to_parquet(args.diagnostics_dir, args.output)


if __name__ == "__main__":
    main()
