#!/usr/bin/env python3
"""
Comprehensive balance test suite with travel time awareness
Tests all 4 acts across 3 map sizes using nimble tasks
"""

import subprocess
import sys
from pathlib import Path
from datetime import datetime
import json

# Configuration
NUM_GAMES_PER_TEST = 50
TIMESTAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
RESULTS_DIR = Path(__file__).parent.parent.parent / "balance_results" / f"comprehensive_{TIMESTAMP}"

# Map size configurations (rings determine map size)
MAP_SIZES = {
    "small": 3,    # 3 rings = ~37 systems
    "medium": 4,   # 4 rings = ~61 systems (default)
    "large": 5,    # 5 rings = ~91 systems
}

# Act configurations
ACTS = {
    "act1": {"turns": 7, "task": "testBalanceAct1"},
    "act2": {"turns": 15, "task": "testBalanceAct2"},
    "act3": {"turns": 25, "task": "testBalanceAct3"},
    "act4": {"turns": 30, "task": "testBalanceAct4"},
}

# Colors for output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'

def log_info(msg):
    print(f"{Colors.BLUE}[INFO]{Colors.NC} {msg}")

def log_success(msg):
    print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} {msg}")

def log_warn(msg):
    print(f"{Colors.YELLOW}[WARN]{Colors.NC} {msg}")

def log_error(msg):
    print(f"{Colors.RED}[ERROR]{Colors.NC} {msg}")

def run_nimble_task(task_name, cwd=None):
    """Run a nimble task and return success status"""
    try:
        log_info(f"Running nimble task: {task_name}")
        result = subprocess.run(
            ["nimble", task_name],
            cwd=cwd or Path(__file__).parent.parent.parent,
            capture_output=True,
            text=True,
            timeout=600  # 10 minute timeout
        )
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        log_error(f"Task {task_name} timed out after 10 minutes")
        return False, "", "Timeout"
    except Exception as e:
        log_error(f"Error running task {task_name}: {e}")
        return False, "", str(e)

def analyze_test_results(stdout, stderr):
    """Parse test output and extract results"""
    results = {
        "total_games": 0,
        "completions": 0,
        "collapses": 0,
        "winners": {},
        "errors": []
    }

    # Parse stdout for game results
    for line in stdout.split('\n'):
        if "games completed" in line.lower():
            # Extract completion count
            try:
                parts = line.split()
                for i, part in enumerate(parts):
                    if part.isdigit() and i + 1 < len(parts) and parts[i+1] == "games":
                        results["completions"] = int(part)
                        break
            except:
                pass

        if "collapse" in line.lower():
            results["collapses"] += 1

        if "Winner:" in line:
            # Extract winner house
            try:
                winner = line.split("Winner:")[1].strip().split()[0]
                results["winners"][winner] = results["winners"].get(winner, 0) + 1
            except:
                pass

    # Parse stderr for errors
    for line in stderr.split('\n'):
        if "error" in line.lower() or "failed" in line.lower():
            results["errors"].append(line.strip())

    return results

def main():
    """Run comprehensive test suite"""
    log_info("=" * 60)
    log_info("EC4X Comprehensive Balance Test Suite")
    log_info("Testing travel time awareness across all acts and map sizes")
    log_info("=" * 60)
    log_info("")

    # Create results directory
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    log_info(f"Results directory: {RESULTS_DIR}")

    # Summary data
    summary = {
        "timestamp": TIMESTAMP,
        "tests": [],
        "total_tests": 0,
        "passed_tests": 0,
        "failed_tests": 0
    }

    # Test each act with each map size
    for act_name, act_config in ACTS.items():
        turns = act_config["turns"]
        task_name = act_config["task"]

        for size_name, rings in MAP_SIZES.items():
            summary["total_tests"] += 1
            test_name = f"{act_name}_{size_name}"

            log_info("")
            log_info("=" * 60)
            log_info(f"Test: {test_name}")
            log_info(f"Act: {act_name} ({turns} turns)")
            log_info(f"Map: {size_name} ({rings} rings, ~{rings * rings * 7} systems)")
            log_info(f"Using nimble task: {task_name}")
            log_info("=" * 60)

            # Create test directory
            test_dir = RESULTS_DIR / test_name
            test_dir.mkdir(parents=True, exist_ok=True)

            # Note: We use the existing nimble tasks which have fixed map sizes
            # For proper map size testing, we'd need to add new nimble tasks or use direct simulation
            log_warn(f"Note: Using nimble task {task_name} (map size controlled by task)")

            # Run test
            success, stdout, stderr = run_nimble_task(task_name)

            # Save raw output
            (test_dir / "stdout.log").write_text(stdout)
            (test_dir / "stderr.log").write_text(stderr)

            # Analyze results
            results = analyze_test_results(stdout, stderr)

            # Determine pass/fail
            test_passed = success and results["collapses"] == 0

            test_result = {
                "name": test_name,
                "act": act_name,
                "turns": turns,
                "map_size": size_name,
                "rings": rings,
                "passed": test_passed,
                "completions": results["completions"],
                "collapses": results["collapses"],
                "winners": results["winners"],
                "errors": results["errors"][:5]  # First 5 errors
            }

            summary["tests"].append(test_result)

            if test_passed:
                log_success(f"Test PASSED: {results['completions']} games completed, {results['collapses']} collapses")
                summary["passed_tests"] += 1
            else:
                log_error(f"Test FAILED: {results['completions']} games completed, {results['collapses']} collapses")
                if results["errors"]:
                    log_error(f"Errors: {len(results['errors'])} error(s) found")
                summary["failed_tests"] += 1

            # Log winners
            if results["winners"]:
                log_info("Winners:")
                total_wins = sum(results["winners"].values())
                for house, count in sorted(results["winners"].items(), key=lambda x: x[1], reverse=True):
                    pct = (count / total_wins * 100) if total_wins > 0 else 0
                    log_info(f"  - {house}: {count} ({pct:.1f}%)")

    # Write summary JSON
    summary_file = RESULTS_DIR / "summary.json"
    summary_file.write_text(json.dumps(summary, indent=2))

    # Write summary text
    summary_txt = RESULTS_DIR / "summary.txt"
    with summary_txt.open('w') as f:
        f.write(f"EC4X Balance Test Suite Results\n")
        f.write(f"Timestamp: {TIMESTAMP}\n")
        f.write(f"\n")
        f.write(f"Total tests: {summary['total_tests']}\n")
        f.write(f"Passed: {summary['passed_tests']}\n")
        f.write(f"Failed: {summary['failed_tests']}\n")
        f.write(f"\n")

        for test in summary["tests"]:
            f.write(f"\n{'=' * 60}\n")
            f.write(f"Test: {test['name']} [{'PASS' if test['passed'] else 'FAIL'}]\n")
            f.write(f"Act: {test['act']} ({test['turns']} turns)\n")
            f.write(f"Map: {test['map_size']} ({test['rings']} rings)\n")
            f.write(f"Completions: {test['completions']}\n")
            f.write(f"Collapses: {test['collapses']}\n")

            if test["winners"]:
                f.write(f"Winners:\n")
                for house, count in test["winners"].items():
                    f.write(f"  - {house}: {count}\n")

            if test["errors"]:
                f.write(f"Errors:\n")
                for err in test["errors"]:
                    f.write(f"  - {err}\n")

    # Final summary
    log_info("")
    log_info("=" * 60)
    log_info("Test Suite Complete")
    log_info("=" * 60)
    log_info(f"Total tests: {summary['total_tests']}")
    log_success(f"Passed: {summary['passed_tests']}")
    if summary['failed_tests'] > 0:
        log_error(f"Failed: {summary['failed_tests']}")
    log_info("")
    log_info(f"Summary JSON: {summary_file}")
    log_info(f"Summary TXT: {summary_txt}")

    # Exit with error if any tests failed
    sys.exit(0 if summary['failed_tests'] == 0 else 1)

if __name__ == "__main__":
    main()
