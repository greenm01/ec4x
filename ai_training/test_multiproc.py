#!/usr/bin/env python3
"""Simple test of multiprocessing with wrapper script"""

import subprocess
import multiprocessing as mp
from pathlib import Path

def run_game(game_id):
    wrapper = "/home/niltempus/dev/ec4x/ai_training/run_game.sh"
    result = subprocess.run([wrapper, str(game_id)], capture_output=True, text=True, timeout=60)

    # Save log
    log_dir = Path("training_data/logs")
    log_dir.mkdir(parents=True, exist_ok=True)

    log_file = log_dir / f"game_{game_id:05d}.log"
    with open(log_file, 'w') as f:
        f.write(f"Game {game_id}\n")
        f.write(f"Return code: {result.returncode}\n\n")
        f.write("STDOUT:\n")
        f.write(result.stdout[:500] if result.stdout else "(empty)\n")
        f.write("\nSTDERR:\n")
        f.write(result.stderr[:500] if result.stderr else "(empty)\n")

    return (game_id, result.returncode)

if __name__ == "__main__":
    print("Testing wrapper with multiprocessing...")
    with mp.Pool(2) as pool:
        results = pool.map(run_game, [1, 2])

    for game_id, code in results:
        print(f"Game {game_id}: return code {code}")
