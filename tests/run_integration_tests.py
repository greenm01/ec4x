#!/usr/bin/env python3
"""
EC4X Integration Test Runner
Runs all integration tests and generates comprehensive reports using polars
"""

import subprocess
import re
import sys
from pathlib import Path
from dataclasses import dataclass
from typing import List, Optional
import time
from datetime import datetime

try:
    import polars as pl
except ImportError:
    print("Warning: polars not installed. Install with: pip install polars")
    print("Falling back to basic reporting...")
    pl = None


@dataclass
class TestResult:
    """Result of a single test file execution"""
    file_name: str
    file_path: str
    status: str  # 'passed', 'failed', 'error', 'timeout'
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
    NC = '\033[0m'  # No Color


def print_header():
    """Print test runner header"""
    print("╔════════════════════════════════════════════════╗")
    print("║  EC4X Integration Test Suite Runner           ║")
    print("╚════════════════════════════════════════════════╝")
    print()


def find_test_files() -> List[Path]:
    """Find all integration test files"""
    project_root = Path(__file__).parent.parent
    test_dir = project_root / "tests" / "integration"

    if not test_dir.exists():
        print(f"Error: Integration test directory not found: {test_dir}")
        sys.exit(1)

    test_files = sorted(test_dir.glob("test_*.nim"))
    return test_files


def run_test(test_file: Path, timeout: int = 120) -> TestResult:
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
                error_msg = error_lines[0] if error_lines else "Unknown compilation error"
                return TestResult(
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
            file_name=test_file.name,
            file_path=str(test_file),
            status='error',
            passed_count=0,
            failed_count=0,
            duration_ms=duration_ms,
            error_message=str(e)
        )


def print_progress(current: int, total: int, test_name: str, result: TestResult):
    """Print progress for a single test"""
    progress = f"[{current}/{total}]"

    if result.status == 'passed':
        status_color = Colors.GREEN
        status_text = "PASSED"
        details = f"({result.passed_count} tests, {result.duration_ms:.0f}ms)"
    elif result.status == 'failed':
        status_color = Colors.RED
        status_text = "FAILED"
        details = f"({result.passed_count} passed, {result.failed_count} failed, {result.duration_ms:.0f}ms)"
    elif result.status == 'timeout':
        status_color = Colors.YELLOW
        status_text = "TIMEOUT"
        details = f"(exceeded {result.duration_ms/1000:.0f}s)"
    else:  # error
        status_color = Colors.RED
        status_text = "ERROR"
        details = f"({result.duration_ms:.0f}ms)"

    print(f"{progress} {test_name:45} {status_color}{status_text:8}{Colors.NC} {details}")

    if result.error_message and result.status != 'passed':
        print(f"    └─ {Colors.YELLOW}{result.error_message}{Colors.NC}")


def create_dataframe(results: List[TestResult]) -> Optional[pl.DataFrame]:
    """Create a polars DataFrame from test results"""
    if pl is None:
        return None

    data = {
        'test_file': [r.file_name for r in results],
        'status': [r.status for r in results],
        'passed': [r.passed_count for r in results],
        'failed': [r.failed_count for r in results],
        'total_tests': [r.passed_count + r.failed_count for r in results],
        'duration_ms': [r.duration_ms for r in results],
    }

    return pl.DataFrame(data)


def print_summary(results: List[TestResult], df: Optional[pl.DataFrame] = None):
    """Print comprehensive test summary"""
    print()
    print("╔════════════════════════════════════════════════╗")
    print("║  Test Summary                                   ║")
    print("╚════════════════════════════════════════════════╝")
    print()

    total_files = len(results)
    passed_files = sum(1 for r in results if r.status == 'passed')
    failed_files = sum(1 for r in results if r.status == 'failed')
    error_files = sum(1 for r in results if r.status == 'error')
    timeout_files = sum(1 for r in results if r.status == 'timeout')

    total_tests = sum(r.passed_count + r.failed_count for r in results)
    total_passed = sum(r.passed_count for r in results)
    total_failed = sum(r.failed_count for r in results)
    total_duration = sum(r.duration_ms for r in results)

    print(f"{Colors.BOLD}Test Files:{Colors.NC}")
    print(f"  Total:   {total_files}")
    print(f"  {Colors.GREEN}Passed:  {passed_files}{Colors.NC}")
    if failed_files > 0:
        print(f"  {Colors.RED}Failed:  {failed_files}{Colors.NC}")
    else:
        print(f"  Failed:  0")
    if error_files > 0:
        print(f"  {Colors.RED}Errors:  {error_files}{Colors.NC}")
    if timeout_files > 0:
        print(f"  {Colors.YELLOW}Timeout: {timeout_files}{Colors.NC}")
    print()

    print(f"{Colors.BOLD}Test Cases:{Colors.NC}")
    print(f"  Total:   {total_tests}")
    print(f"  {Colors.GREEN}Passed:  {total_passed}{Colors.NC}")
    if total_failed > 0:
        print(f"  {Colors.RED}Failed:  {total_failed}{Colors.NC}")
    else:
        print(f"  Failed:  0")
    print()

    print(f"{Colors.BOLD}Performance:{Colors.NC}")
    print(f"  Total duration: {total_duration/1000:.1f}s")
    if total_tests > 0:
        print(f"  Average per test case: {total_duration/total_tests:.0f}ms")
    print()

    # Polars analysis if available
    if df is not None:
        print(f"{Colors.BOLD}Polars Analysis:{Colors.NC}")
        print()

        # Top 5 slowest tests
        slowest = df.sort('duration_ms', descending=True).head(5)
        print("  Slowest test files:")
        for row in slowest.iter_rows(named=True):
            print(f"    {row['test_file']:45} {row['duration_ms']/1000:6.1f}s")
        print()

        # Tests with most test cases
        most_tests = df.sort('total_tests', descending=True).head(5)
        print("  Most comprehensive tests:")
        for row in most_tests.iter_rows(named=True):
            if row['total_tests'] > 0:
                print(f"    {row['test_file']:45} {row['total_tests']:3} tests")
        print()

        # Status distribution
        status_counts = df.group_by('status').agg(pl.count()).sort('count', descending=True)
        print("  Status distribution:")
        for row in status_counts.iter_rows(named=True):
            print(f"    {row['status']:10} {row['count']:3} files")
        print()

    # List failed files
    failed_results = [r for r in results if r.status in ['failed', 'error', 'timeout']]
    if failed_results:
        print(f"{Colors.YELLOW}Failed/Error Test Files:{Colors.NC}")
        for result in failed_results:
            print(f"  {Colors.RED}✗{Colors.NC} {result.file_name}")
            if result.error_message:
                print(f"      {result.error_message}")
        print()

    # Success message or failure
    if passed_files == total_files:
        print(f"{Colors.GREEN}{Colors.BOLD}✓ All tests passed!{Colors.NC}")
        return True
    else:
        print(f"{Colors.RED}✗ Some tests failed or had errors{Colors.NC}")
        return False


def main():
    """Main test runner"""
    print_header()

    # Find test files
    test_files = find_test_files()
    print(f"Found {len(test_files)} integration test files")
    print()

    # Run tests
    results: List[TestResult] = []
    for i, test_file in enumerate(test_files, 1):
        result = run_test(test_file)
        results.append(result)
        print_progress(i, len(test_files), test_file.name, result)

    # Create dataframe if polars available
    df = create_dataframe(results)

    # Print summary
    success = print_summary(results, df)

    # Save report if polars available
    if df is not None:
        report_path = Path(__file__).parent.parent / "test_report.csv"
        df.write_csv(str(report_path))
        print(f"Detailed report saved to: {report_path}")
        print()

    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
