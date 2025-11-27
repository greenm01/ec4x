"""
EC4X Balance Analysis System

Terminal-based data analysis for balance testing and diagnostics.

Usage:
    from analysis import BalanceAnalyzer

    analyzer = BalanceAnalyzer("balance_results/diagnostics_combined.parquet")
    print(analyzer.summary_by_house())
    analyzer.detect_outliers_zscore()
    analyzer.export_for_excel("summary.csv")
"""

from .balance_analyzer import BalanceAnalyzer

__all__ = ["BalanceAnalyzer"]
