#!/usr/bin/env python3
"""
EC4X Stress Test Runner
Runs all stress tests with configurable intensity levels
"""

import subprocess
import sys
import time
from pathlib import Path
from dataclasses import dataclass
from typing import List, Optional
import argparse

try:
    import polars as pl
except ImportError:
    print("Warning: polars not installed. Install with: pip install polars")
    print("Falling back to basic reporting...")
    pl = None


@dataclass
class StressTestResult:
    """Result of a stress test execution"""
    test_name: str
    test_file: str
    status: str  # 'passed', 'failed', 'timeout', 'error'
    duration_s: float
    iterations: Optional[int] = None
    games_run: Optional[int] = None
    errors_found: Optional[int] = None
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
    """Print stress test header"""
    print("╔════════════════════════════════════════════════╗")
    print("║  EC4X Stress Test Suite Runner                ║")
    print("╚════════════════════════════════════════════════╝")
    print()


def find_stress_tests() -> List[Path]:
    """Find all stress test files"""
    stress_dir = Path(__file__).parent
    return sorted(stress_dir.glob("test_*.nim"))


def run_stress_test(test_file: Path, quick_mode: bool = False, timeout: int = 600) -> StressTestResult:
    """Run a single stress test"""
    test_name = test_file.stem
    start_time = time.time()

    print(f"\n{Colors.BOLD}Running: {test_name}{Colors.NC}")
    print(f"  File: {test_file.name}")
    if quick_mode:
        print(f"  Mode: {Colors.YELLOW}Quick (reduced iterations){Colors.NC}")
    else:
        print(f"  Mode: {Colors.CYAN}Full (may take 10-30 minutes){Colors.NC}")
    print()

    try:
        # Build command with quick mode flag if needed
        compile_args = ["nim", "c", "-r", "--hints:off"]
        if quick_mode:
            compile_args.append("-d:STRESS_QUICK")
        compile_args.append(str(test_file))

        # Run the stress test
        result = subprocess.run(
            compile_args,
            capture_output=True,
            text=True,
            timeout=timeout
        )

        duration_s = time.time() - start_time
        output = result.stdout + result.stderr

        # Parse output for metrics
        iterations = None
        games_run = None
        errors_found = None

        # Look for common patterns in stress test output
        for line in output.split('\n'):
            if 'iterations' in line.lower() or 'turns' in line.lower():
                # Try to extract iteration count
                import re
                match = re.search(r'(\d+)\s+(?:iterations|turns)', line.lower())
                if match:
                    iterations = int(match.group(1))
            if 'games' in line.lower():
                match = re.search(r'(\d+)\s+games', line.lower())
                if match:
                    games_run = int(match.group(1))
            if 'error' in line.lower() or 'fail' in line.lower():
                match = re.search(r'(\d+)\s+(?:errors?|failures?)', line.lower())
                if match:
                    errors_found = int(match.group(1))

        if result.returncode != 0:
            # Extract error message
            error_lines = [l for l in output.split('\n') if 'Error:' in l or 'FAILED' in l]
            error_msg = error_lines[0][:200] if error_lines else "Test execution failed"

            return StressTestResult(
                test_name=test_name,
                test_file=str(test_file),
                status='failed' if errors_found and errors_found > 0 else 'error',
                duration_s=duration_s,
                iterations=iterations,
                games_run=games_run,
                errors_found=errors_found,
                error_message=error_msg
            )

        # Success
        status = 'passed'
        if errors_found and errors_found > 0:
            status = 'failed'

        return StressTestResult(
            test_name=test_name,
            test_file=str(test_file),
            status=status,
            duration_s=duration_s,
            iterations=iterations,
            games_run=games_run,
            errors_found=errors_found
        )

    except subprocess.TimeoutExpired:
        duration_s = timeout
        return StressTestResult(
            test_name=test_name,
            test_file=str(test_file),
            status='timeout',
            duration_s=duration_s,
            error_message=f"Test timed out after {timeout}s"
        )
    except Exception as e:
        duration_s = time.time() - start_time
        return StressTestResult(
            test_name=test_name,
            test_file=str(test_file),
            status='error',
            duration_s=duration_s,
            error_message=str(e)[:200]
        )


def print_result(result: StressTestResult):
    """Print stress test result"""
    print(f"\n{Colors.BOLD}Result for {result.test_name}:{Colors.NC}")

    if result.status == 'passed':
        print(f"  Status:   {Colors.GREEN}✓ PASSED{Colors.NC}")
    elif result.status == 'failed':
        print(f"  Status:   {Colors.RED}✗ FAILED{Colors.NC}")
    elif result.status == 'timeout':
        print(f"  Status:   {Colors.YELLOW}⧗ TIMEOUT{Colors.NC}")
    else:
        print(f"  Status:   {Colors.RED}✗ ERROR{Colors.NC}")

    print(f"  Duration: {result.duration_s:.1f}s ({result.duration_s/60:.1f} min)")

    if result.iterations:
        print(f"  Iterations: {result.iterations:,}")
    if result.games_run:
        print(f"  Games:    {result.games_run:,}")
    if result.errors_found is not None:
        color = Colors.RED if result.errors_found > 0 else Colors.GREEN
        print(f"  Errors:   {color}{result.errors_found}{Colors.NC}")

    if result.error_message:
        print(f"  Message:  {Colors.YELLOW}{result.error_message}{Colors.NC}")

    print()


def print_summary(results: List[StressTestResult], total_time: float):
    """Print comprehensive summary"""
    print("\n" + "="*60)
    print(f"{Colors.BOLD}Stress Test Summary{Colors.NC}")
    print("="*60 + "\n")

    passed = sum(1 for r in results if r.status == 'passed')
    failed = sum(1 for r in results if r.status == 'failed')
    errors = sum(1 for r in results if r.status == 'error')
    timeouts = sum(1 for r in results if r.status == 'timeout')
    total = len(results)

    print(f"Tests Run:     {total}")
    print(f"  {Colors.GREEN}Passed:      {passed}{Colors.NC}")
    if failed > 0:
        print(f"  {Colors.RED}Failed:      {failed}{Colors.NC}")
    if errors > 0:
        print(f"  {Colors.RED}Errors:      {errors}{Colors.NC}")
    if timeouts > 0:
        print(f"  {Colors.YELLOW}Timeouts:    {timeouts}{Colors.NC}")

    print(f"\nTotal Duration: {total_time:.1f}s ({total_time/60:.1f} min)")

    # Aggregate metrics
    total_iterations = sum(r.iterations for r in results if r.iterations)
    total_games = sum(r.games_run for r in results if r.games_run)
    total_errors = sum(r.errors_found for r in results if r.errors_found)

    if total_iterations > 0:
        print(f"Total Iterations: {total_iterations:,}")
    if total_games > 0:
        print(f"Total Games:    {total_games:,}")
    if total_errors is not None:
        color = Colors.RED if total_errors > 0 else Colors.GREEN
        print(f"Total Errors:   {color}{total_errors}{Colors.NC}")

    # List failed tests
    failed_tests = [r for r in results if r.status in ['failed', 'error', 'timeout']]
    if failed_tests:
        print(f"\n{Colors.YELLOW}Failed Tests:{Colors.NC}")
        for result in failed_tests:
            print(f"  {Colors.RED}✗{Colors.NC} {result.test_name}")
            if result.error_message:
                print(f"      {result.error_message[:100]}")

    print()
    if passed == total:
        print(f"{Colors.GREEN}{Colors.BOLD}✓ All stress tests passed!{Colors.NC}")
        return True
    else:
        print(f"{Colors.RED}{Colors.BOLD}✗ Some stress tests failed{Colors.NC}")
        return False


def main():
    """Main stress test runner"""
    parser = argparse.ArgumentParser(description='EC4X Stress Test Runner')
    parser.add_argument('--quick', action='store_true',
                       help='Run in quick mode (reduced iterations)')
    parser.add_argument('--timeout', type=int, default=600,
                       help='Timeout per test in seconds (default: 600 = 10 min)')
    parser.add_argument('--tests', nargs='+',
                       help='Specific tests to run (e.g., test_state_corruption test_pathological_inputs)')
    args = parser.parse_args()

    print_header()

    # Find stress tests
    all_tests = find_stress_tests()

    # Filter if specific tests requested
    if args.tests:
        test_names = set(args.tests)
        all_tests = [t for t in all_tests if t.stem in test_names]

    if not all_tests:
        print("No stress tests found!")
        sys.exit(1)

    print(f"Found {len(all_tests)} stress test(s)")
    if args.quick:
        print(f"{Colors.YELLOW}Running in QUICK mode (reduced iterations){Colors.NC}")
    else:
        print(f"{Colors.CYAN}Running in FULL mode (may take 10-30 minutes per test){Colors.NC}")
    print(f"Timeout: {args.timeout}s ({args.timeout/60:.1f} min) per test")
    print()

    # Run all stress tests
    results: List[StressTestResult] = []
    start_time = time.time()

    for test_file in all_tests:
        result = run_stress_test(test_file, quick_mode=args.quick, timeout=args.timeout)
        results.append(result)
        print_result(result)

    total_time = time.time() - start_time

    # Print summary
    success = print_summary(results, total_time)

    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
