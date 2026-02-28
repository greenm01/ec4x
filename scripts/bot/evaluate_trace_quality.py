#!/usr/bin/env python3
"""Evaluate stability/reproducibility gates from bot traces."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any


def collect_traces(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    if path.is_dir():
        return sorted(path.glob("**/bot_trace_*.jsonl"))
    return []


def evaluate(path: Path) -> dict[str, Any]:
    files = collect_traces(path)
    sessions = 0
    turns = 0
    successes = 0
    retries = 0
    longest_streak = 0
    streak = 0
    error_classes: dict[str, int] = {}

    for file in files:
        for raw in file.read_text().splitlines():
            raw = raw.strip()
            if not raw:
                continue
            try:
                row = json.loads(raw)
            except json.JSONDecodeError:
                continue

            if row.get("kind") == "session_start":
                sessions += 1
                continue

            turns += 1
            if int(row.get("attempts", 1)) > 1:
                retries += 1

            if bool(row.get("ok", False)):
                successes += 1
                streak += 1
                longest_streak = max(longest_streak, streak)
            else:
                streak = 0

            err = str(row.get("errorClass", "unknown"))
            error_classes[err] = error_classes.get(err, 0) + 1

    success_rate = (successes / turns) if turns > 0 else 0.0
    retry_rate = (retries / turns) if turns > 0 else 0.0

    return {
        "files": len(files),
        "sessions": sessions,
        "turns": turns,
        "successes": successes,
        "successRate": success_rate,
        "retryTurns": retries,
        "retryRate": retry_rate,
        "longestConsecutiveSuccess": longest_streak,
        "errorClasses": error_classes,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate bot playtest stability gates"
    )
    parser.add_argument(
        "path",
        nargs="?",
        default="logs/bot",
        help="Trace file or directory (default: logs/bot)",
    )
    parser.add_argument(
        "--min-consecutive-success",
        type=int,
        default=20,
        help="Minimum required consecutive successful turns",
    )
    parser.add_argument(
        "--min-success-rate",
        type=float,
        default=0.75,
        help="Minimum required success rate across turn records",
    )
    parser.add_argument(
        "--max-retry-rate",
        type=float,
        default=0.50,
        help="Maximum allowed retry-turn ratio",
    )
    parser.add_argument(
        "--require-session-record",
        action="store_true",
        help="Require at least one session_start record",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print JSON summary output",
    )
    args = parser.parse_args()

    result = evaluate(Path(args.path))

    checks = {
        "hasTraces": result["files"] > 0,
        "consecutiveSuccess": result["longestConsecutiveSuccess"]
        >= args.min_consecutive_success,
        "successRate": result["successRate"] >= args.min_success_rate,
        "retryRate": result["retryRate"] <= args.max_retry_rate,
    }

    if args.require_session_record:
        checks["sessionStart"] = result["sessions"] > 0

    status = all(checks.values())
    result["checks"] = checks
    result["pass"] = status

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"Trace files: {result['files']}")
        print(f"Session records: {result['sessions']}")
        print(f"Turn records: {result['turns']}")
        print(f"Successes: {result['successes']}")
        print(f"Longest success streak: {result['longestConsecutiveSuccess']}")
        print(f"Success rate: {result['successRate']:.2%}")
        print(f"Retry rate: {result['retryRate']:.2%}")
        print("Error classes:", result["errorClasses"])
        print("Checks:", checks)
        print("PASS" if status else "FAIL")

    return 0 if status else 2


if __name__ == "__main__":
    sys.exit(main())
