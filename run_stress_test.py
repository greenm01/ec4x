#!/usr/bin/env python3
"""
EC4X Stress Test - Run 100,000 games to find edge cases and crashes

Strategy:
- Run short games (30 turns) for speed
- Use random seeds to maximize coverage
- Test different map sizes and player counts
- Log all crashes with stack traces
- Track crash frequency and patterns
"""

import subprocess
import sys
import time
import random
from datetime import datetime
from pathlib import Path

# Test configurations: (numPlayers, mapRings, turns, weight)
# Weight determines how often this config is tested
CONFIGS = [
    (4, 4, 30, 50),    # 50% - most common
    (6, 6, 30, 20),    # 20%
    (8, 8, 30, 15),    # 15%
    (10, 10, 30, 10),  # 10%
    (12, 12, 30, 5),   # 5%
]

TARGET_GAMES = 100000
PROGRESS_INTERVAL = 100  # Report every N games

def weighted_random_config():
    """Select a config based on weights"""
    total_weight = sum(w for _, _, _, w in CONFIGS)
    r = random.random() * total_weight
    cumulative = 0
    for config in CONFIGS:
        cumulative += config[3]
        if r <= cumulative:
            return config[:3]  # Return (players, rings, turns)
    return CONFIGS[0][:3]

def run_simulation(num_players, turns, seed, map_rings):
    """Run a single simulation and return success/failure"""
    cmd = ["./tests/balance/run_simulation", str(turns), str(seed), str(map_rings), str(num_players)]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd="/home/niltempus/dev/ec4x",
            timeout=60  # 60 second timeout
        )

        if result.returncode != 0:
            return False, result.stderr
        return True, None

    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"
    except Exception as e:
        return False, f"EXCEPTION: {e}"

def main():
    print("="*70)
    print("EC4X STRESS TEST - 100,000 Games")
    print("="*70)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()

    # Statistics
    total_games = 0
    successful_games = 0
    failed_games = 0
    crashes_by_config = {}
    crash_log = []
    start_time = time.time()

    # Create crash log file
    crash_log_path = Path("stress_test_crashes.log")
    crash_log_file = open(crash_log_path, "w")
    crash_log_file.write(f"EC4X Stress Test Crash Log - {datetime.now()}\n")
    crash_log_file.write("="*70 + "\n\n")
    crash_log_file.flush()

    try:
        for game_num in range(1, TARGET_GAMES + 1):
            # Select random configuration
            num_players, map_rings, turns = weighted_random_config()

            # Generate random seed
            seed = random.randint(1000, 999999)

            # Run simulation
            success, error = run_simulation(num_players, turns, seed, map_rings)

            total_games += 1

            if success:
                successful_games += 1
            else:
                failed_games += 1
                config_key = f"{num_players}p-{map_rings}r-{turns}t"
                crashes_by_config[config_key] = crashes_by_config.get(config_key, 0) + 1

                # Log crash details
                crash_entry = (
                    f"Game #{game_num} CRASHED\n"
                    f"  Config: {num_players} players, {map_rings} rings, {turns} turns\n"
                    f"  Seed: {seed}\n"
                    f"  Error:\n{error}\n"
                    f"{'-'*70}\n\n"
                )
                crash_log.append(crash_entry)
                crash_log_file.write(crash_entry)
                crash_log_file.flush()

            # Progress report
            if game_num % PROGRESS_INTERVAL == 0:
                elapsed = time.time() - start_time
                games_per_sec = total_games / elapsed
                eta_seconds = (TARGET_GAMES - total_games) / games_per_sec if games_per_sec > 0 else 0
                eta_hours = eta_seconds / 3600

                success_rate = (successful_games / total_games) * 100

                print(f"Progress: {game_num:,}/{TARGET_GAMES:,} games "
                      f"({success_rate:.2f}% success, {failed_games} crashes, "
                      f"{games_per_sec:.1f} games/sec, ETA: {eta_hours:.1f}h)")

                if failed_games > 0 and game_num % (PROGRESS_INTERVAL * 10) == 0:
                    print(f"  Crash distribution: {crashes_by_config}")

    except KeyboardInterrupt:
        print("\n\nStress test interrupted by user")

    finally:
        crash_log_file.close()

        # Final report
        elapsed = time.time() - start_time
        print("\n" + "="*70)
        print("STRESS TEST COMPLETE")
        print("="*70)
        print(f"Total Games: {total_games:,}")
        print(f"Successful: {successful_games:,} ({(successful_games/total_games)*100:.2f}%)")
        print(f"Failed: {failed_games:,} ({(failed_games/total_games)*100:.2f}%)")
        print(f"Elapsed Time: {elapsed/3600:.2f} hours")
        print(f"Average Speed: {total_games/elapsed:.1f} games/second")
        print()

        if failed_games > 0:
            print("Crash Distribution by Configuration:")
            for config, count in sorted(crashes_by_config.items(), key=lambda x: x[1], reverse=True):
                print(f"  {config}: {count} crashes ({(count/failed_games)*100:.1f}%)")
            print()
            print(f"Detailed crash log: {crash_log_path}")
            print(f"First few crashes:")
            for i, entry in enumerate(crash_log[:5], 1):
                print(f"\n--- Crash {i} ---")
                print(entry)
        else:
            print("🎉 NO CRASHES DETECTED! System is stable!")

if __name__ == "__main__":
    main()
