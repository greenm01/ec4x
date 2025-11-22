#!/usr/bin/env python3
"""
Parallel Training Data Generation for EC4X

Runs multiple game simulations in parallel to generate training data efficiently.
Uses 80% of system resources (25 of 32 threads on Ryzen 9 7950X3D).
"""

import subprocess
import multiprocessing as mp
import time
import json
from pathlib import Path
from datetime import datetime
import sys

# Configuration
TOTAL_GAMES = 50  # Generate 50 games for training
PARALLEL_JOBS = 25  # Use 80% of 32 threads
OUTPUT_DIR = Path("training_data")
SIMULATOR_PATH = Path("../tests/balance/generate_training_data")
LOG_DIR = OUTPUT_DIR / "logs"

def run_single_game(game_id: int) -> tuple[int, bool, str]:
    """Run a single game simulation and return result."""
    start_time = time.time()

    try:
        # Use wrapper script to ensure correct working directory
        # Multiprocessing doesn't reliably inherit cwd, so use a shell script
        wrapper_script = "/home/niltempus/dev/ec4x/ai_training/run_game.sh"

        result = subprocess.run(
            [wrapper_script, str(game_id)],
            capture_output=True,
            text=True,
            timeout=600  # 10 minute timeout per game
        )

        elapsed = time.time() - start_time
        success = result.returncode == 0

        # Log output
        log_file = LOG_DIR / f"game_{game_id:05d}.log"
        with open(log_file, 'w') as f:
            f.write(f"Game {game_id}\n")
            f.write(f"Return code: {result.returncode}\n")
            f.write(f"Duration: {elapsed:.2f}s\n\n")
            f.write("STDOUT:\n")
            f.write(result.stdout)
            f.write("\nSTDERR:\n")
            f.write(result.stderr)

        if success:
            return (game_id, True, f"{elapsed:.1f}s")
        else:
            # Extract error message
            error_msg = "unknown error"
            if "ERROR:" in result.stdout:
                error_lines = [line for line in result.stdout.split('\n') if 'ERROR' in line]
                if error_lines:
                    error_msg = error_lines[0][:50]
            return (game_id, False, error_msg)

    except subprocess.TimeoutExpired:
        return (game_id, False, "timeout (>10 min)")
    except Exception as e:
        return (game_id, False, str(e)[:50])

def merge_batch_files():
    """Merge all generated batch files into a single training dataset."""
    print("\n" + "="*70)
    print("Merging all batch files into combined dataset...")
    print("="*70)

    all_examples = []
    batch_files = sorted(OUTPUT_DIR.glob("game_*/batches/batch_001.json"))

    for batch_file in batch_files:
        try:
            with open(batch_file) as f:
                examples = json.load(f)
                all_examples.extend(examples)
        except Exception as e:
            print(f"Warning: Failed to load {batch_file}: {e}")

    # Create combined dataset
    combined = {
        "metadata": {
            "generated": datetime.now().isoformat(),
            "num_games": len(batch_files),
            "num_examples": len(all_examples),
            "engine_version": "0.1.0",
            "data_version": "v1",
            "generation_method": "parallel_80pct_cpu"
        },
        "examples": all_examples
    }

    output_file = OUTPUT_DIR / "training_dataset_combined.json"
    with open(output_file, 'w') as f:
        json.dump(combined, f, indent=2)

    file_size_mb = output_file.stat().st_size / (1024 * 1024)

    print(f"\n✓ Combined dataset saved: {output_file}")
    print(f"  Games: {len(batch_files)}")
    print(f"  Training examples: {len(all_examples)}")
    print(f"  File size: {file_size_mb:.1f} MB")
    print(f"  Examples per game: {len(all_examples) / max(len(batch_files), 1):.1f}")

def main():
    print("="*70)
    print("EC4X Parallel Training Data Generation")
    print("="*70)
    print(f"Configuration:")
    print(f"  Total games: {TOTAL_GAMES}")
    print(f"  Parallel jobs: {PARALLEL_JOBS} (80% of {mp.cpu_count()} cores)")
    print(f"  Output directory: {OUTPUT_DIR}")
    print(f"  Simulator: {SIMULATOR_PATH}")
    print("="*70)
    print()

    # Create directories
    OUTPUT_DIR.mkdir(exist_ok=True)
    LOG_DIR.mkdir(exist_ok=True)

    # Check simulator exists
    if not SIMULATOR_PATH.exists():
        print(f"ERROR: Simulator not found at {SIMULATOR_PATH}")
        print("Run: cd /home/niltempus/dev/ec4x && nim c -d:release tests/balance/generate_training_data.nim")
        sys.exit(1)

    # Generate game IDs
    game_ids = list(range(1, TOTAL_GAMES + 1))

    start_time = time.time()
    completed = 0
    failed = 0

    # Run games in parallel
    with mp.Pool(processes=PARALLEL_JOBS) as pool:
        print(f"Starting {TOTAL_GAMES} game simulations with {PARALLEL_JOBS} parallel workers...")
        print()

        # Process games
        for game_id, success, info in pool.imap_unordered(run_single_game, game_ids):
            if success:
                completed += 1
                status = f"✓ {info}"
            else:
                failed += 1
                status = f"✗ {info}"

            # Progress update
            total_done = completed + failed
            elapsed = time.time() - start_time
            games_per_sec = total_done / elapsed if elapsed > 0 else 0
            remaining_games = TOTAL_GAMES - total_done
            eta_sec = remaining_games / games_per_sec if games_per_sec > 0 else 0

            print(f"[{total_done:4d}/{TOTAL_GAMES}] Game {game_id:5d}: {status} "
                  f"(✓{completed} ✗{failed}) "
                  f"[{games_per_sec:.2f} games/sec, ETA: {eta_sec/60:.1f} min]")

    # Final statistics
    elapsed = time.time() - start_time

    print()
    print("="*70)
    print("Generation Complete!")
    print("="*70)
    print(f"  Total games: {TOTAL_GAMES}")
    print(f"  Successful: {completed} ({100*completed/TOTAL_GAMES:.1f}%)")
    print(f"  Failed: {failed} ({100*failed/TOTAL_GAMES:.1f}%)")
    print(f"  Duration: {elapsed:.1f}s ({elapsed/60:.1f} minutes)")
    print(f"  Speed: {TOTAL_GAMES/elapsed:.2f} games/second")
    print()

    if completed > 0:
        # Merge all batch files
        merge_batch_files()
    else:
        print("ERROR: No games completed successfully. Check logs in", LOG_DIR)
        sys.exit(1)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nInterrupted by user. Partial results may be available in", OUTPUT_DIR)
        sys.exit(130)
