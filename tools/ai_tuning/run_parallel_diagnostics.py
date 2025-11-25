#!/usr/bin/env python3
"""
Parallel Diagnostic Runner for EC4X
Optimized for AMD Ryzen 9 7950X3D (16C/32T)
"""

import subprocess
import sys
import time
import random
import shutil
from pathlib import Path
from multiprocessing import Pool, cpu_count
from typing import Tuple
from datetime import datetime

# Configuration
DEFAULT_NUM_GAMES = 50
DEFAULT_TURNS_PER_GAME = 100
DEFAULT_NUM_JOBS = 16  # One per physical core on 7950X3D
OUTPUT_DIR = Path("balance_results/diagnostics")
RUN_SIMULATION_BIN = Path("tests/balance/run_simulation")

def archive_old_diagnostics() -> None:
    """Archive existing diagnostic results to restic backup with date-based organization."""
    if not OUTPUT_DIR.exists():
        return

    # Check if there are any CSV files to archive
    csv_files = list(OUTPUT_DIR.glob("*.csv"))
    if not csv_files:
        print("No existing diagnostic data to archive")
        return

    # Create restic repo if it doesn't exist
    restic_repo = Path.home() / ".ec4x_test_data"
    restic_repo.mkdir(exist_ok=True)

    env = {
        "RESTIC_REPOSITORY": str(restic_repo),
        "RESTIC_PASSWORD": ""  # No password for local test data
    }

    # Initialize repo if needed (will fail silently if already initialized)
    subprocess.run(["restic", "init"], env=env, capture_output=True)

    # Archive with current date tag
    date_tag = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    print(f"\nArchiving {len(csv_files)} existing diagnostic files to restic with tag: {date_tag}")

    result = subprocess.run(
        ["restic", "backup", str(OUTPUT_DIR), "--tag", f"diagnostics-{date_tag}"],
        env=env,
        capture_output=True,
        text=True
    )

    if result.returncode == 0:
        print(f"✓ Diagnostics archived to {restic_repo}")
        # Clean up after successful archive
        for csv_file in csv_files:
            csv_file.unlink()
        print(f"✓ Removed {len(csv_files)} old CSV files")
    else:
        print(f"⚠ Archive failed: {result.stderr[:200]}")
        print("  Removing old files anyway...")
        for csv_file in csv_files:
            csv_file.unlink()

def compile_simulation() -> bool:
    """
    Compile run_simulation with FORCE RECOMPILE to prevent stale binary bugs.

    Per UNKNOWN_UNKNOWNS_FINDINGS_2025-11-25.md:
    - ALWAYS recompile to ensure dependencies (ai_controller.nim, etc.) are fresh
    - Verify binary is less than 5 minutes old after compilation
    - This prevents the "stale binary meta-bug" that cost 4+ hours of debugging
    """
    nim_source = Path("tests/balance/run_simulation.nim")

    print("🔨 Force recompiling run_simulation (prevent stale binary bugs)...")
    try:
        result = subprocess.run(
            ["nim", "c", "-d:release", str(nim_source)],
            capture_output=True,
            text=True,
            check=True
        )

        # Verify binary is fresh (< 5 minutes old)
        if RUN_SIMULATION_BIN.exists():
            binary_age = time.time() - RUN_SIMULATION_BIN.stat().st_mtime
            if binary_age > 300:  # 5 minutes
                print(f"⚠ WARNING: Binary is {binary_age:.0f}s old - suspiciously stale!")
                print("  Compilation may have failed silently or used cached artifacts")
                return False
            print(f"✓ Compilation complete (binary age: {binary_age:.1f}s)")
        else:
            print("✗ Binary not found after compilation")
            return False

        return True
    except subprocess.CalledProcessError as e:
        print(f"✗ Compilation failed:\n{e.stderr}")
        return False

def run_single_game(args: Tuple[int, int, int]) -> Tuple[int, int, bool, str]:
    """
    Run a single simulation game.

    Args:
        args: (game_num, seed, turns)

    Returns:
        (game_num, seed, success, message)
    """
    game_num, seed, turns = args
    output_file = OUTPUT_DIR / f"game_{seed}.csv"

    try:
        # Run simulation and capture output
        result = subprocess.run(
            [str(RUN_SIMULATION_BIN), str(turns), str(seed)],
            capture_output=True,
            text=True,
            timeout=300,  # 5 minute timeout per game
            check=False
        )

        # Check if CSV was created and has content
        if output_file.exists() and output_file.stat().st_size > 0:
            return (game_num, seed, True, f"✓ Game {game_num} (seed {seed}) complete")
        else:
            error_msg = result.stderr[:200] if result.stderr else "No output file"
            return (game_num, seed, False, f"✗ Game {game_num} (seed {seed}) FAILED: {error_msg}")

    except subprocess.TimeoutExpired:
        return (game_num, seed, False, f"✗ Game {game_num} (seed {seed}) TIMEOUT")
    except Exception as e:
        return (game_num, seed, False, f"✗ Game {game_num} (seed {seed}) ERROR: {str(e)}")

def main():
    """Main entry point."""
    # Parse command line arguments
    num_games = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_NUM_GAMES
    turns_per_game = int(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_TURNS_PER_GAME
    num_jobs = int(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_NUM_JOBS

    print("=" * 70)
    print("EC4X Parallel Diagnostic Runner")
    print("=" * 70)
    print(f"Configuration:")
    print(f"  Games:           {num_games}")
    print(f"  Turns per game:  {turns_per_game}")
    print(f"  Parallel jobs:   {num_jobs}")
    print(f"  CPU cores:       {cpu_count()} logical cores detected")
    print(f"  Output:          {OUTPUT_DIR}")
    print("=" * 70)
    print()

    # Archive old diagnostics before starting new run
    archive_old_diagnostics()

    # Ensure output directory exists
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Compile simulation
    if not compile_simulation():
        print("\n✗ Cannot proceed without compiled binary")
        sys.exit(1)
    print()

    # Generate random seeds for each game
    print(f"Generating random seeds for {num_games} games...")
    random.seed()
    seeds = [random.randint(10000, 99999) for _ in range(num_games)]
    print("✓ Seeds generated")
    print()

    # Prepare game arguments
    game_args = [(i + 1, seed, turns_per_game) for i, seed in enumerate(seeds)]

    # Run simulations in parallel
    print(f"Starting parallel execution with {num_jobs} jobs...")
    print("=" * 70)
    start_time = time.time()

    success_count = 0
    failed_games = []

    with Pool(processes=num_jobs) as pool:
        for game_num, seed, success, message in pool.imap_unordered(run_single_game, game_args):
            print(message)
            if success:
                success_count += 1
            else:
                failed_games.append((game_num, seed))

    end_time = time.time()
    duration = int(end_time - start_time)

    print("=" * 70)
    print()

    # Summary
    print("=" * 70)
    print("Parallel Diagnostic Run Complete!")
    print("=" * 70)
    print(f"Results:")
    print(f"  Total games:     {num_games}")
    print(f"  Successful:      {success_count}")
    print(f"  Failed:          {num_games - success_count}")
    print(f"  Duration:        {duration}s ({duration // 60}m {duration % 60}s)")
    if duration > 0:
        print(f"  Avg per game:    {duration / num_games:.1f}s")
        print(f"  Throughput:      {num_games / (duration / 60):.1f} games/minute")
    else:
        print(f"  Avg per game:    <1s")
        print(f"  Throughput:      Very fast!")
    print(f"  Output:          {OUTPUT_DIR}")
    print("=" * 70)
    print()

    if success_count == num_games:
        print("✓ All games completed successfully!")
        print()
        print("Next steps:")
        print("  1. Analyze results: python3 tests/balance/analyze_phase2_gaps.py")
        print(f"  2. Review CSV files: ls -lh {OUTPUT_DIR}/")
        sys.exit(0)
    else:
        print(f"⚠ {len(failed_games)} games failed:")
        for game_num, seed in failed_games[:10]:  # Show first 10 failures
            print(f"    Game {game_num} (seed {seed})")
        if len(failed_games) > 10:
            print(f"    ... and {len(failed_games) - 10} more")
        sys.exit(1)

if __name__ == "__main__":
    main()
