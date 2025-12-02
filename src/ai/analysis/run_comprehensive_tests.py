#!/usr/bin/env python3
"""
Comprehensive balance test suite - Build once, test all configurations
Tests all 4 acts across 3 map sizes using direct simulation calls
"""

import subprocess
import multiprocessing
from pathlib import Path
from datetime import datetime
import json

# Configuration
TIMESTAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
RESULTS_DIR = Path(__file__).parent.parent.parent / "balance_results" / f"comprehensive_{TIMESTAMP}"
SIMULATION_BIN = Path(__file__).parent / "run_simulation"
NUM_GAMES = 100
NUM_WORKERS = min(16, multiprocessing.cpu_count())

# Map configurations
MAP_CONFIGS = [
    {"name": "small", "rings": 3, "players": 4},
    {"name": "medium", "rings": 4, "players": 4},
    {"name": "large", "rings": 5, "players": 4},
]

# Act configurations
ACT_CONFIGS = [
    {"name": "act1", "turns": 7, "description": "Land Grab"},
    {"name": "act2", "turns": 15, "description": "Rising Tensions"},
    {"name": "act3", "turns": 25, "description": "Total War"},
    {"name": "act4", "turns": 30, "description": "Endgame"},
]

# Colors
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'

def log(msg, color=Colors.NC):
    print(f"{color}{msg}{Colors.NC}")

def build_simulation():
    """Build simulation binary once"""
    log("=" * 70, Colors.BLUE)
    log("Building simulation binary...", Colors.BLUE)
    log("=" * 70, Colors.BLUE)

    result = subprocess.run(
        ["nimble", "buildBalance"],
        cwd=Path(__file__).parent.parent.parent,
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        log("BUILD FAILED!", Colors.RED)
        print(result.stdout)
        print(result.stderr)
        return False

    log("Build successful!", Colors.GREEN)
    return True

def run_test_batch(act_config, map_config):
    """Run one test configuration"""
    test_name = f"{act_config['name']}_{map_config['name']}"
    turns = act_config['turns']
    rings = map_config['rings']
    players = map_config['players']

    log("", Colors.NC)
    log("=" * 70, Colors.BLUE)
    log(f"Test: {test_name}", Colors.BLUE)
    log(f"Act: {act_config['name']} - {act_config['description']} ({turns} turns)", Colors.BLUE)
    log(f"Map: {map_config['name']} ({rings} rings, {players} players)", Colors.BLUE)
    log("=" * 70, Colors.BLUE)

    # Create test directory
    test_dir = RESULTS_DIR / test_name
    test_dir.mkdir(parents=True, exist_ok=True)

    # Run parallel test using the Python runner
    cmd = [
        "python3",
        "run_balance_test_parallel.py",
        "--workers", str(NUM_WORKERS),
        "--games", str(NUM_GAMES),
        "--turns", str(turns),
        "--rings", str(rings),
        "--players", str(players)
    ]

    result = subprocess.run(
        cmd,
        cwd=Path(__file__).parent.parent.parent,
        capture_output=True,
        text=True,
        timeout=600
    )

    # Save outputs
    (test_dir / "stdout.log").write_text(result.stdout)
    (test_dir / "stderr.log").write_text(result.stderr)

    # Parse results
    passed = result.returncode == 0
    completions = 0
    collapses = 0
    winners = {}

    for line in result.stdout.split('\n'):
        if "Total Games:" in line:
            try:
                completions = int(line.split(':')[1].strip())
            except:
                pass
        if "house-" in line and "(" in line:
            # Parse winner line like: "house-ordos   88 ( 91.7%)     0 ( 0.0%)"
            try:
                parts = line.split()
                if len(parts) >= 3:
                    house = parts[0]
                    wins = int(parts[1])
                    if wins > 0:
                        winners[house] = wins
            except:
                pass

    if passed:
        log(f"✓ Test PASSED: {completions} games completed, 0 collapses", Colors.GREEN)
    else:
        log(f"✗ Test FAILED: check logs in {test_dir}", Colors.RED)

    if winners:
        log("Winners:", Colors.BLUE)
        total_wins = sum(winners.values())
        for house, count in sorted(winners.items(), key=lambda x: x[1], reverse=True):
            pct = (count / total_wins * 100) if total_wins > 0 else 0
            log(f"  - {house}: {count} ({pct:.1f}%)", Colors.NC)

    return {
        "name": test_name,
        "act": act_config['name'],
        "turns": turns,
        "map_size": map_config['name'],
        "rings": rings,
        "players": players,
        "passed": passed,
        "completions": completions,
        "collapses": collapses,
        "winners": winners
    }

def main():
    log("=" * 70, Colors.BLUE)
    log("EC4X Comprehensive Balance Test Suite", Colors.BLUE)
    log("Travel Time Awareness - All Acts × All Map Sizes", Colors.BLUE)
    log("=" * 70, Colors.BLUE)
    log("", Colors.NC)

    # Create results directory
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    log(f"Results directory: {RESULTS_DIR}", Colors.BLUE)

    # Build once
    if not build_simulation():
        return 1

    # Run all tests
    summary = {
        "timestamp": TIMESTAMP,
        "tests": [],
        "total_tests": 0,
        "passed_tests": 0,
        "failed_tests": 0
    }

    for act_config in ACT_CONFIGS:
        for map_config in MAP_CONFIGS:
            summary["total_tests"] += 1
            result = run_test_batch(act_config, map_config)
            summary["tests"].append(result)

            if result["passed"]:
                summary["passed_tests"] += 1
            else:
                summary["failed_tests"] += 1

    # Write summary
    summary_json = RESULTS_DIR / "summary.json"
    summary_json.write_text(json.dumps(summary, indent=2))

    log("", Colors.NC)
    log("=" * 70, Colors.BLUE)
    log("Test Suite Complete", Colors.BLUE)
    log("=" * 70, Colors.BLUE)
    log(f"Total tests: {summary['total_tests']}", Colors.BLUE)
    log(f"Passed: {summary['passed_tests']}", Colors.GREEN)
    if summary['failed_tests'] > 0:
        log(f"Failed: {summary['failed_tests']}", Colors.RED)
    log("", Colors.NC)
    log(f"Summary: {summary_json}", Colors.BLUE)

    return 0 if summary['failed_tests'] == 0 else 1

if __name__ == "__main__":
    import sys
    sys.exit(main())
