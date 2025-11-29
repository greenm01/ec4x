#!/usr/bin/env python3
"""
EC4X Comprehensive Test Runner
Runs all test types: unit, integration, stress, and balance tests
Generates comprehensive reports using polars
"""

import subprocess
import re
import sys
from pathlib import Path
from dataclasses import dataclass
from typing import List, Optional, Dict
import time
from datetime import datetime
import argparse

try:
    import polars as pl
except ImportError:
    print("Warning: polars not installed. Install with: pip install polars")
    print("Falling back to basic reporting...")
    pl = None


@dataclass
class TestResult:
    """Result of a single test file execution"""
    test_type: str  # 'unit', 'integration', 'stress', 'balance'
    file_name: str
    file_path: str
    status: str  # 'passed', 'failed', 'error', 'timeout', 'skipped'
    passed_count: int
    failed_count: int
    duration_ms: float
    error_message: Optional[str] = None


class Colors:
    """ANSI color codes"""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    MAGENTA = '\033[0;35m'
    CYAN = '\033[0;36m'
    BOLD = '\033[1m'
    NC = '\033[0m'


def print_header():
    """Print test runner header"""
    print("╔════════════════════════════════════════════════╗")
    print("║  EC4X Comprehensive Test Suite Runner         ║")
    print("╚════════════════════════════════════════════════╝")
    print()


def find_test_files(test_type: str, project_root: Path) -> List[Path]:
    """Find all test files of a given type"""
    test_dirs = {
        'unit': project_root / "tests",
        'integration': project_root / "tests" / "integration",
        'stress': project_root / "tests" / "stress",
        'balance': project_root / "tests" / "balance",
    }

    test_dir = test_dirs.get(test_type)
    if not test_dir or not test_dir.exists():
        return []

    # For unit tests, look in tests/ but exclude subdirectories
    if test_type == 'unit':
        return sorted([f for f in test_dir.glob("test_*.nim") if f.is_file()])
    else:
        return sorted(test_dir.glob("test_*.nim"))


def run_test(test_file: Path, test_type: str, timeout: int = 120) -> TestResult:
    """Run a single test file and collect results"""
    start_time = time.time()

    try:
        # Compile and run test
        result = subprocess.run(
            ["nim", "c", "-r", "--hints:off", str(test_file)],
            capture_output=True,
            text=True,
            timeout=timeout
        )

        duration_ms = (time.time() - start_time) * 1000

        # Parse output for test results
        output = result.stdout + result.stderr
        passed_matches = re.findall(r'\[OK\]', output)
        failed_matches = re.findall(r'\[FAILED\]', output)

        passed_count = len(passed_matches)
        failed_count = len(failed_matches)

        if result.returncode != 0:
            # Check for compilation errors
            if "Error:" in output:
                error_lines = [line for line in output.split('\n') if 'Error:' in line]
                error_msg = error_lines[0][:100] if error_lines else "Unknown compilation error"
                return TestResult(
                    test_type=test_type,
                    file_name=test_file.name,
                    file_path=str(test_file),
                    status='error',
                    passed_count=passed_count,
                    failed_count=failed_count,
                    duration_ms=duration_ms,
                    error_message=error_msg
                )
            else:
                status = 'failed' if failed_count > 0 else 'error'
                return TestResult(
                    test_type=test_type,
                    file_name=test_file.name,
                    file_path=str(test_file),
                    status=status,
                    passed_count=passed_count,
                    failed_count=failed_count,
                    duration_ms=duration_ms,
                    error_message="Test execution failed"
                )

        status = 'passed' if failed_count == 0 else 'failed'
        return TestResult(
            test_type=test_type,
            file_name=test_file.name,
            file_path=str(test_file),
            status=status,
            passed_count=passed_count,
            failed_count=failed_count,
            duration_ms=duration_ms
        )

    except subprocess.TimeoutExpired:
        duration_ms = timeout * 1000
        return TestResult(
            test_type=test_type,
            file_name=test_file.name,
            file_path=str(test_file),
            status='timeout',
            passed_count=0,
            failed_count=0,
            duration_ms=duration_ms,
            error_message=f"Test timed out after {timeout}s"
        )
    except Exception as e:
        duration_ms = (time.time() - start_time) * 1000
        return TestResult(
            test_type=test_type,
            file_name=test_file.name,
            file_path=str(test_file),
            status='error',
            passed_count=0,
            failed_count=0,
            duration_ms=duration_ms,
            error_message=str(e)[:100]
        )


def print_progress(test_type: str, current: int, total: int, test_name: str, result: TestResult):
    """Print progress for a single test"""
    type_prefix = f"[{test_type.upper():12}]"
    progress = f"[{current:2}/{total:2}]"

    if result.status == 'passed':
        status_color = Colors.GREEN
        status_text = "✓ PASS"
        details = f"{result.passed_count:3} tests, {result.duration_ms/1000:6.1f}s"
    elif result.status == 'failed':
        status_color = Colors.RED
        status_text = "✗ FAIL"
        details = f"{result.passed_count:3} passed, {result.failed_count:3} failed, {result.duration_ms/1000:6.1f}s"
    elif result.status == 'timeout':
        status_color = Colors.YELLOW
        status_text = "⧗ TIME"
        details = f"exceeded {result.duration_ms/1000:.0f}s"
    else:  # error
        status_color = Colors.RED
        status_text = "✗ ERR "
        details = f"{result.duration_ms/1000:6.1f}s"

    print(f"{type_prefix} {progress} {test_name:40} {status_color}{status_text}{Colors.NC} {details}")

    if result.error_message and result.status != 'passed':
        print(f"      └─ {Colors.YELLOW}{result.error_message}{Colors.NC}")


def create_dataframe(results: List[TestResult]) -> Optional[pl.DataFrame]:
    """Create a polars DataFrame from test results"""
    if pl is None:
        return None

    data = {
        'test_type': [r.test_type for r in results],
        'test_file': [r.file_name for r in results],
        'status': [r.status for r in results],
        'passed': [r.passed_count for r in results],
        'failed': [r.failed_count for r in results],
        'total_tests': [r.passed_count + r.failed_count for r in results],
        'duration_ms': [r.duration_ms for r in results],
        'duration_s': [r.duration_ms / 1000 for r in results],
    }

    return pl.DataFrame(data)


def print_summary(results: List[TestResult], df: Optional[pl.DataFrame] = None):
    """Print comprehensive test summary"""
    print()
    print("╔════════════════════════════════════════════════╗")
    print("║  Comprehensive Test Summary                    ║")
    print("╚════════════════════════════════════════════════╝")
    print()

    # Overall stats
    total_files = len(results)
    passed_files = sum(1 for r in results if r.status == 'passed')
    failed_files = sum(1 for r in results if r.status == 'failed')
    error_files = sum(1 for r in results if r.status == 'error')
    timeout_files = sum(1 for r in results if r.status == 'timeout')

    total_tests = sum(r.passed_count + r.failed_count for r in results)
    total_passed = sum(r.passed_count for r in results)
    total_failed = sum(r.failed_count for r in results)
    total_duration = sum(r.duration_ms for r in results)

    print(f"{Colors.BOLD}Overall Results:{Colors.NC}")
    print(f"  Test Files:  {total_files:4} total")
    print(f"               {Colors.GREEN}{passed_files:4} passed{Colors.NC}")
    if failed_files > 0:
        print(f"               {Colors.RED}{failed_files:4} failed{Colors.NC}")
    if error_files > 0:
        print(f"               {Colors.RED}{error_files:4} errors{Colors.NC}")
    if timeout_files > 0:
        print(f"               {Colors.YELLOW}{timeout_files:4} timeout{Colors.NC}")
    print()

    print(f"  Test Cases:  {total_tests:4} total")
    print(f"               {Colors.GREEN}{total_passed:4} passed{Colors.NC}")
    if total_failed > 0:
        print(f"               {Colors.RED}{total_failed:4} failed{Colors.NC}")
    print()

    print(f"  Duration:    {total_duration/1000:6.1f}s total")
    if total_tests > 0:
        print(f"               {total_duration/total_tests:6.1f}ms avg per test case")
    print()

    # Break down by test type
    test_types = set(r.test_type for r in results)
    if len(test_types) > 1:
        print(f"{Colors.BOLD}By Test Type:{Colors.NC}")
        for test_type in sorted(test_types):
            type_results = [r for r in results if r.test_type == test_type]
            type_files = len(type_results)
            type_passed = sum(1 for r in type_results if r.status == 'passed')
            type_tests = sum(r.passed_count + r.failed_count for r in type_results)
            type_duration = sum(r.duration_ms for r in type_results)

            status = f"{Colors.GREEN}✓{Colors.NC}" if type_passed == type_files else f"{Colors.RED}✗{Colors.NC}"
            print(f"  {status} {test_type:12} {type_passed:3}/{type_files:3} files, {type_tests:4} tests, {type_duration/1000:6.1f}s")
        print()

    # Polars analysis if available
    if df is not None:
        print(f"{Colors.BOLD}Detailed Analysis (via Polars):{Colors.NC}")
        print()

        # Top 5 slowest tests
        slowest = df.sort('duration_s', descending=True).head(5)
        print("  Slowest tests:")
        for row in slowest.iter_rows(named=True):
            print(f"    [{row['test_type']:12}] {row['test_file']:40} {row['duration_s']:6.1f}s")
        print()

        # Tests with most test cases
        most_tests = df.filter(pl.col('total_tests') > 0).sort('total_tests', descending=True).head(5)
        if len(most_tests) > 0:
            print("  Most comprehensive tests:")
            for row in most_tests.iter_rows(named=True):
                print(f"    [{row['test_type']:12}] {row['test_file']:40} {row['total_tests']:3} cases")
            print()

        # Aggregate stats by type
        if len(test_types) > 1:
            agg_stats = df.group_by('test_type').agg([
                pl.count().alias('files'),
                pl.sum('total_tests').alias('test_cases'),
                pl.sum('passed').alias('passed_cases'),
                pl.sum('failed').alias('failed_cases'),
                pl.sum('duration_s').alias('total_duration_s'),
            ]).sort('test_type')

            print("  Aggregate statistics:")
            for row in agg_stats.iter_rows(named=True):
                print(f"    {row['test_type']:12} {row['files']:3} files, "
                      f"{row['test_cases']:4} cases ({row['passed_cases']:4}✓ {row['failed_cases']:4}✗), "
                      f"{row['total_duration_s']:6.1f}s")
            print()

    # List failed/error files
    failed_results = [r for r in results if r.status in ['failed', 'error', 'timeout']]
    if failed_results:
        print(f"{Colors.YELLOW}Failed/Error Test Files:{Colors.NC}")
        for result in failed_results:
            icon = "✗" if result.status in ['failed', 'error'] else "⧗"
            print(f"  {Colors.RED}{icon}{Colors.NC} [{result.test_type:12}] {result.file_name}")
            if result.error_message:
                print(f"      {result.error_message}")
        print()

    # Success message or failure
    success = passed_files == total_files
    if success:
        print(f"{Colors.GREEN}{Colors.BOLD}✓ All tests passed!{Colors.NC}")
    else:
        print(f"{Colors.RED}{Colors.BOLD}✗ {failed_files + error_files + timeout_files} test file(s) failed or had errors{Colors.NC}")

    return success


def main():
    """Main test runner"""
    parser = argparse.ArgumentParser(description='EC4X Comprehensive Test Runner')
    parser.add_argument('--types', nargs='+', choices=['unit', 'integration', 'stress', 'balance', 'all'],
                       default=['all'], help='Test types to run (default: all)')
    parser.add_argument('--timeout', type=int, default=120, help='Timeout per test in seconds (default: 120)')
    parser.add_argument('--report', type=str, help='Path to save CSV report (default: test_report.csv)')
    args = parser.parse_args()

    print_header()

    project_root = Path(__file__).parent.parent

    # Determine which test types to run
    if 'all' in args.types:
        test_types = ['unit', 'integration', 'stress', 'balance']
    else:
        test_types = args.types

    # Find all test files
    all_test_files: Dict[str, List[Path]] = {}
    total_count = 0
    for test_type in test_types:
        files = find_test_files(test_type, project_root)
        if files:
            all_test_files[test_type] = files
            total_count += len(files)
            print(f"Found {len(files):3} {test_type} tests")

    if total_count == 0:
        print("No test files found!")
        sys.exit(1)

    print(f"\nTotal: {total_count} test files")
    print()

    # Run all tests
    results: List[TestResult] = []
    for test_type, test_files in all_test_files.items():
        print(f"{Colors.BOLD}Running {test_type.upper()} tests:{Colors.NC}")
        for i, test_file in enumerate(test_files, 1):
            result = run_test(test_file, test_type, timeout=args.timeout)
            results.append(result)
            print_progress(test_type, i, len(test_files), test_file.name, result)
        print()

    # Create dataframe if polars available
    df = create_dataframe(results)

    # Print summary
    success = print_summary(results, df)

    # Save report if polars available
    if df is not None:
        report_path = args.report if args.report else str(project_root / "test_report.csv")
        df.write_csv(report_path)
        print(f"\nDetailed report saved to: {report_path}")

    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
