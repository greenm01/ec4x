#!/usr/bin/env python3
"""
Convert diagnostic CSV files to Parquet format.

Benefits:
- 3-5x smaller file size (columnar compression)
- Instant loading for analysis (no parsing)
- Preserves type information (no string conversion)
- Better for sharing with AI (fewer tokens when uploaded)

Usage:
    python3 tools/ai_tuning/convert_to_parquet.py
    python3 tools/ai_tuning/convert_to_parquet.py --output balance_results/diagnostics_combined.parquet
"""

import argparse
import sys
from pathlib import Path

try:
    import polars as pl
except ImportError:
    print("ERROR: Polars not installed")
    print("Install with: pip install polars")
    sys.exit(1)


def convert_to_parquet(diagnostics_dir: Path, output_path: Path) -> None:
    """Convert all CSV files to a single Parquet file."""

    # Find all CSV files
    csv_files = list(diagnostics_dir.glob("game_*.csv"))

    if not csv_files:
        print(f"ERROR: No CSV files found in {diagnostics_dir}")
        sys.exit(1)

    print(f"Loading {len(csv_files)} CSV files...")

    # Load all CSVs
    all_data = []
    for csv_file in csv_files:
        try:
            df = pl.read_csv(csv_file)
            all_data.append(df)
        except Exception as e:
            print(f"WARNING: Failed to read {csv_file}: {e}")

    if not all_data:
        print("ERROR: No valid CSV data found")
        sys.exit(1)

    # Concatenate with diagonal to handle schema mismatches
    print("Combining data...")
    df = pl.concat(all_data, how="diagonal")

    # Write to Parquet
    print(f"Writing {len(df)} rows to {output_path}...")
    df.write_parquet(output_path, compression="zstd")

    # Report statistics
    csv_total_size = sum(f.stat().st_size for f in csv_files)
    parquet_size = output_path.stat().st_size
    compression_ratio = csv_total_size / parquet_size if parquet_size > 0 else 0

    print("=" * 70)
    print("Conversion Complete!")
    print("=" * 70)
    print(f"CSV files:       {len(csv_files)} files, {csv_total_size / 1024 / 1024:.1f} MB")
    print(f"Parquet output:  {parquet_size / 1024 / 1024:.1f} MB")
    print(f"Compression:     {compression_ratio:.1f}x smaller")
    print(f"Rows:            {len(df):,}")
    print(f"Columns:         {len(df.columns)}")
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
