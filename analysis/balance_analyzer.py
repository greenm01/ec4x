#!/usr/bin/env python3
"""
Core Balance Analysis Engine

Consolidates all diagnostic analysis functionality using Polars for
fast parallel processing on 32-core AMD Ryzen 9 7950X3D.

Benefits:
- Instant loading from Parquet (vs slow CSV parsing)
- Parallel processing using all CPU cores
- Type-safe data operations
- Excel/LibreOffice compatibility via CSV export
"""

import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    import polars as pl
except ImportError:
    print("ERROR: Polars not installed")
    print("Install with: pip install polars")
    sys.exit(1)


class BalanceAnalyzer:
    """
    Core analysis engine for EC4X balance testing.

    Loads Parquet-formatted diagnostic data and provides methods for:
    - Summary statistics (by house, by turn)
    - Outlier detection (z-score, IQR)
    - Phase 2 gap analysis
    - Excel export

    Usage:
        analyzer = BalanceAnalyzer("balance_results/diagnostics_combined.parquet")
        summary = analyzer.summary_by_house()
        outliers = analyzer.detect_outliers_zscore("total_fighters", threshold=2.5)
        analyzer.export_for_excel("summary.csv")
    """

    def __init__(self, parquet_path: Path | str):
        """
        Load diagnostic data from Parquet file.

        Args:
            parquet_path: Path to combined diagnostics Parquet file
        """
        self.parquet_path = Path(parquet_path)

        if not self.parquet_path.exists():
            raise FileNotFoundError(f"Parquet file not found: {self.parquet_path}")

        # Load with predicate pushdown enabled (fast filtering)
        self.df = pl.read_parquet(self.parquet_path)

        # Extract metadata if present
        self.metadata = {
            "git_hash": self.df.select(pl.col("_git_hash").first()).item() if "_git_hash" in self.df.columns else "unknown",
            "timestamp": self.df.select(pl.col("_timestamp").first()).item() if "_timestamp" in self.df.columns else "unknown"
        }

        # Compute basic stats
        self.num_games = self.df.select(pl.col("turn").n_unique()).item()
        self.num_houses = self.df.select(pl.col("house").n_unique()).item()
        self.total_turns = len(self.df)
        self.turns_per_game = self.total_turns / self.num_games if self.num_games > 0 else 0

    def get_metadata(self) -> Dict[str, any]:
        """Return dataset metadata (git hash, timestamp, row counts)."""
        return {
            **self.metadata,
            "num_games": self.num_games,
            "num_houses": self.num_houses,
            "total_turns": self.total_turns,
            "turns_per_game": self.turns_per_game,
            "parquet_path": str(self.parquet_path),
        }

    def summary_by_house(self, metrics: Optional[List[str]] = None) -> pl.DataFrame:
        """
        Aggregate metrics by house (one row per house).

        Args:
            metrics: List of metric columns to aggregate (default: all numeric)

        Returns:
            DataFrame with columns: house, metric1_mean, metric1_sum, ...
        """
        if metrics is None:
            # Default: all numeric columns except metadata
            metrics = [
                col for col in self.df.columns
                if col not in ["house", "turn", "_git_hash", "_timestamp"]
                and self.df[col].dtype in [pl.Int64, pl.Float64, pl.Int32, pl.Float32]
            ]

        # Build aggregation expressions
        agg_exprs = []
        for metric in metrics:
            if metric in self.df.columns:
                agg_exprs.extend([
                    pl.col(metric).mean().alias(f"{metric}_mean"),
                    pl.col(metric).sum().alias(f"{metric}_sum"),
                    pl.col(metric).std().alias(f"{metric}_std"),
                    pl.col(metric).min().alias(f"{metric}_min"),
                    pl.col(metric).max().alias(f"{metric}_max"),
                ])

        return self.df.group_by("house").agg(agg_exprs).sort("house")

    def summary_by_turn(self, metrics: Optional[List[str]] = None) -> pl.DataFrame:
        """
        Aggregate metrics by turn (one row per turn, averaged across houses).

        Args:
            metrics: List of metric columns to aggregate (default: all numeric)

        Returns:
            DataFrame with columns: turn, metric1_mean, metric1_sum, ...
        """
        if metrics is None:
            # Default: all numeric columns except metadata
            metrics = [
                col for col in self.df.columns
                if col not in ["house", "turn", "_git_hash", "_timestamp"]
                and self.df[col].dtype in [pl.Int64, pl.Float64, pl.Int32, pl.Float32]
            ]

        # Build aggregation expressions
        agg_exprs = []
        for metric in metrics:
            if metric in self.df.columns:
                agg_exprs.extend([
                    pl.col(metric).mean().alias(f"{metric}_mean"),
                    pl.col(metric).sum().alias(f"{metric}_sum"),
                    pl.col(metric).std().alias(f"{metric}_std"),
                ])

        return self.df.group_by("turn").agg(agg_exprs).sort("turn")

    def detect_outliers_zscore(
        self,
        metric: str,
        threshold: float = 3.0,
        by_house: bool = False
    ) -> pl.DataFrame:
        """
        Detect outliers using z-score method.

        Args:
            metric: Column name to analyze
            threshold: Z-score threshold (default: 3.0 = 99.7% confidence)
            by_house: If True, compute z-scores per house (default: global)

        Returns:
            DataFrame with outlier rows + z_score column
        """
        if metric not in self.df.columns:
            raise ValueError(f"Metric '{metric}' not found in data")

        # Compute z-scores
        if by_house:
            # Per-house z-scores
            df_with_zscore = self.df.with_columns([
                ((pl.col(metric) - pl.col(metric).mean().over("house")) /
                 pl.col(metric).std().over("house")).alias("z_score")
            ])
        else:
            # Global z-scores
            mean = self.df.select(pl.col(metric).mean()).item()
            std = self.df.select(pl.col(metric).std()).item()

            if std == 0:
                # No variation - no outliers
                return self.df.filter(pl.lit(False))

            df_with_zscore = self.df.with_columns([
                ((pl.col(metric) - mean) / std).alias("z_score")
            ])

        # Filter outliers
        return df_with_zscore.filter(
            pl.col("z_score").abs() > threshold
        ).sort(pl.col("z_score").abs(), descending=True)

    def detect_outliers_iqr(
        self,
        metric: str,
        multiplier: float = 1.5,
        by_house: bool = False
    ) -> pl.DataFrame:
        """
        Detect outliers using IQR (Interquartile Range) method.

        Args:
            metric: Column name to analyze
            multiplier: IQR multiplier (default: 1.5 = standard outlier, 3.0 = extreme)
            by_house: If True, compute IQR per house (default: global)

        Returns:
            DataFrame with outlier rows
        """
        if metric not in self.df.columns:
            raise ValueError(f"Metric '{metric}' not found in data")

        if by_house:
            # Per-house IQR
            q1 = self.df.select(pl.col(metric).quantile(0.25).over("house")).to_series()
            q3 = self.df.select(pl.col(metric).quantile(0.75).over("house")).to_series()
            iqr = q3 - q1
            lower = q1 - multiplier * iqr
            upper = q3 + multiplier * iqr

            return self.df.filter(
                (pl.col(metric) < lower) | (pl.col(metric) > upper)
            )
        else:
            # Global IQR
            q1 = self.df.select(pl.col(metric).quantile(0.25)).item()
            q3 = self.df.select(pl.col(metric).quantile(0.75)).item()
            iqr = q3 - q1
            lower = q1 - multiplier * iqr
            upper = q3 + multiplier * iqr

            return self.df.filter(
                (pl.col(metric) < lower) | (pl.col(metric) > upper)
            )

    def analyze_phase2_gaps(self) -> Dict[str, any]:
        """
        Comprehensive Phase 2 gap analysis (consolidates analyze_phase2_gaps.py).

        Returns:
            Dictionary with Phase 2 metrics and anomaly detection results
        """
        results = {}

        # Phase 2b: Fighter/Carrier System
        capacity_violations = self.df.filter(pl.col("capacity_violations") > 0)
        violation_rate = len(capacity_violations) / self.total_turns * 100

        idle_carrier_rate = self.df.select(
            (pl.col("idle_carriers") / pl.col("total_carriers").replace(0, 1)).mean()
        ).item() * 100

        avg_fighters = self.df.select(pl.col("total_fighters").mean()).item()
        avg_carriers = self.df.select(pl.col("total_carriers").mean()).item()

        results["phase2b_fighter_carrier"] = {
            "capacity_violation_rate": round(violation_rate, 2),
            "idle_carrier_rate": round(idle_carrier_rate, 2),
            "avg_fighters_per_house": round(avg_fighters, 1),
            "avg_carriers_per_house": round(avg_carriers, 1),
            "target_violation_rate": 0,
            "target_idle_rate": 5,
            "status": "pass" if violation_rate < 1 and idle_carrier_rate < 10 else "fail"
        }

        # Phase 2c: Scout Operational Modes
        if "scout_count" in self.df.columns:
            avg_scouts = self.df.select(pl.col("scout_count").mean()).item()
            scout_turns = self.df.filter(pl.col("scout_count") >= 5)
            scout_utilization = len(scout_turns) / self.total_turns * 100

            results["phase2c_scouts"] = {
                "avg_scouts_per_house": round(avg_scouts, 1),
                "utilization_5plus": round(scout_utilization, 1),
                "target_scouts": "5-7",
                "status": "pass" if avg_scouts >= 3 else "fail"
            }
        else:
            results["phase2c_scouts"] = {
                "status": "not_implemented",
                "note": "scout_count column not found"
            }

        # Phase 2g: Espionage Usage
        spy_planet_total = self.df.select(pl.col("spy_planet").sum()).item()
        hack_starbase_total = self.df.select(pl.col("hack_starbase").sum()).item()
        total_espionage = self.df.select(pl.col("total_espionage").sum()).item()

        turns_with_espionage = len(self.df.filter(pl.col("total_espionage") > 0))
        espionage_usage_rate = turns_with_espionage / self.total_turns * 100

        results["phase2g_espionage"] = {
            "spy_planet_missions": spy_planet_total,
            "hack_starbase_missions": hack_starbase_total,
            "total_missions": total_espionage,
            "turns_with_espionage": turns_with_espionage,
            "usage_rate": round(espionage_usage_rate, 1),
            "target_usage": "100%",
            "status": "pass" if total_espionage > 0 else "critical_fail"
        }

        # Phase 2f: Defense Layering
        avg_undefended = self.df.select(
            (pl.col("undefended_colonies") / pl.col("total_colonies").replace(0, 1)).mean()
        ).item() * 100

        results["phase2f_defense"] = {
            "avg_undefended_rate": round(avg_undefended, 1),
            "target_rate": "<40%",
            "status": "pass" if avg_undefended < 50 else "fail"
        }

        # Phase 2c/2d: ELI Mesh Coordination
        invasions_without_eli = self.df.select(pl.col("invasions_no_eli").sum()).item()
        total_invasions = self.df.select(pl.col("total_invasions").sum()).item()

        if total_invasions > 0:
            eli_coverage = (1 - invasions_without_eli / total_invasions) * 100
            results["phase2cd_eli_mesh"] = {
                "invasions_with_eli": round(eli_coverage, 1),
                "total_invasions": total_invasions,
                "target_coverage": ">80%",
                "status": "pass" if eli_coverage > 50 else "fail"
            }
        else:
            results["phase2cd_eli_mesh"] = {
                "invasions_with_eli": 0,
                "total_invasions": 0,
                "note": "No invasion data available"
            }

        # Anomaly detection
        anomalies = []

        # Zero-spend turns (treasury hoarding)
        high_zero_spend = len(self.df.filter(pl.col("zero_spend_turns") > 10))
        if high_zero_spend > 0:
            anomalies.append({
                "type": "treasury_hoarding",
                "severity": "warning",
                "count": high_zero_spend,
                "description": f"{high_zero_spend} turns with 10+ consecutive zero-spend turns"
            })

        # Space combat balance
        total_wins = self.df.select(pl.col("space_wins").sum()).item()
        total_losses = self.df.select(pl.col("space_losses").sum()).item()
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
        clk_no_raiders = len(self.df.filter(pl.col("clk_no_raiders") == True))
        if clk_no_raiders > 0:
            anomalies.append({
                "type": "clk_no_raiders",
                "severity": "error",
                "count": clk_no_raiders,
                "description": f"{clk_no_raiders} turns where CLK researched but no Raiders built"
            })

        # Invalid orders
        invalid_orders = self.df.select(pl.col("invalid_orders").sum()).item()
        total_orders = self.df.select(pl.col("total_orders").sum()).item()
        if total_orders > 0:
            invalid_rate = invalid_orders / total_orders * 100
            if invalid_rate > 5:
                anomalies.append({
                    "type": "invalid_orders",
                    "severity": "error",
                    "invalid_rate": round(invalid_rate, 2),
                    "description": f"Invalid order rate {invalid_rate:.2f}% (should be <5%)"
                })

        results["anomalies"] = anomalies

        # Overall status
        critical_failures = [a for a in anomalies if a["severity"] == "error"]
        phase_failures = [
            k for k, v in results.items()
            if isinstance(v, dict) and v.get("status") in ["fail", "critical_fail"]
        ]

        if critical_failures or phase_failures:
            results["overall_status"] = "issues_found"
            results["issues_summary"] = {
                "critical_failures": len(critical_failures),
                "phase_failures": len(phase_failures),
                "failed_phases": phase_failures
            }
        else:
            results["overall_status"] = "all_systems_nominal"

        return results

    def export_for_excel(
        self,
        output_path: Path | str,
        summary_type: str = "by_house",
        metrics: Optional[List[str]] = None
    ):
        """
        Export summary data to CSV for Excel/LibreOffice.

        Args:
            output_path: Output CSV file path
            summary_type: "by_house" or "by_turn" or "raw"
            metrics: List of metrics to include (default: all)
        """
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        if summary_type == "by_house":
            df = self.summary_by_house(metrics)
        elif summary_type == "by_turn":
            df = self.summary_by_turn(metrics)
        elif summary_type == "raw":
            df = self.df
        else:
            raise ValueError(f"Invalid summary_type: {summary_type}")

        # Write CSV
        df.write_csv(output_path)

        return output_path
