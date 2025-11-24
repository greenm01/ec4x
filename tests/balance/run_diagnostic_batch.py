#!/usr/bin/env python3
"""
Run batch diagnostic games for gap analysis
Usage: python3 run_diagnostic_batch.py [num_games] [turns_per_game] [num_players]
"""

import subprocess
import sys
import time
from pathlib import Path

def run_diagnostic_batch(num_games: int = 100, turns: int = 100, players: int = 4):
    """Run multiple diagnostic simulations with different seeds."""

    print("=" * 70)
    print("EC4X Diagnostic Batch Runner")
    print("=" * 70)
    print(f"Games to run: {num_games}")
    print(f"Turns per game: {turns}")
    print(f"Players per game: {players}")
    print()

    # Ensure output directory exists
    diagnostics_dir = Path("../../balance_results/diagnostics")
    diagnostics_dir.mkdir(parents=True, exist_ok=True)

    # Path to simulation binary (resolve to absolute path)
    script_dir = Path(__file__).parent
    sim_binary = (script_dir / "run_simulation").resolve()

    if not sim_binary.exists():
        print(f"ERROR: Simulation binary not found at {sim_binary}")
        print("Please compile first: nim c tests/balance/run_simulation.nim")
        return 1

    print("Starting batch run...")
    start_time = time.time()

    failed_games = []

    for i in range(1, num_games + 1):
        seed = 12345 + i

        if i % 10 == 0:
            elapsed = time.time() - start_time
            rate = i / elapsed if elapsed > 0 else 0
            eta = (num_games - i) / rate if rate > 0 else 0
            print(f"  Progress: {i}/{num_games} games ({rate:.1f} games/sec, ETA: {eta:.0f}s)...")

        try:
            # Run simulation (suppress stdout, capture stderr for errors)
            result = subprocess.run(
                [str(sim_binary), str(turns), str(seed), "0", str(players)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=300  # 5 minute timeout per game
            )

            if result.returncode != 0:
                failed_games.append((i, seed, result.stderr.decode()[:200]))

        except subprocess.TimeoutExpired:
            failed_games.append((i, seed, "TIMEOUT"))
            print(f"  WARNING: Game {i} (seed {seed}) timed out!")
        except Exception as e:
            failed_games.append((i, seed, str(e)))
            print(f"  ERROR: Game {i} (seed {seed}) failed: {e}")

    end_time = time.time()
    elapsed = end_time - start_time

    # Count generated CSV files
    csv_files = list(diagnostics_dir.glob("*.csv"))

    print()
    print("=" * 70)
    print("Batch run complete!")
    print(f"Games completed: {num_games - len(failed_games)}/{num_games}")
    print(f"Time elapsed: {elapsed:.1f}s ({elapsed/60:.1f} minutes)")
    print(f"Average: {elapsed/num_games:.2f}s per game")
    print(f"Output directory: {diagnostics_dir}")
    print(f"CSV files generated: {len(csv_files)}")

    if failed_games:
        print(f"\nFailed games: {len(failed_games)}")
        for game_num, seed, error in failed_games[:5]:  # Show first 5 failures
            print(f"  Game {game_num} (seed {seed}): {error}")
        if len(failed_games) > 5:
            print(f"  ... and {len(failed_games) - 5} more")

    print("=" * 70)

    return 0 if len(failed_games) == 0 else 1

if __name__ == "__main__":
    num_games = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    turns = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    players = int(sys.argv[3]) if len(sys.argv) > 3 else 4

    sys.exit(run_diagnostic_batch(num_games, turns, players))
