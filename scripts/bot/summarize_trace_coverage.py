#!/usr/bin/env python3
"""Summarize bot feature-family coverage from trace JSONL logs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

FAMILIES = [
    "zero_turn",
    "fleet",
    "build",
    "repair",
    "scrap",
    "diplomacy",
    "population_transfer",
    "terraform",
    "colony_management",
    "espionage",
    "research",
    "investment",
]


def trace_files(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    if path.is_dir():
        return sorted(path.glob("**/bot_trace_*.jsonl"))
    return []


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Summarize feature coverage from bot traces"
    )
    parser.add_argument(
        "path",
        nargs="?",
        default="logs/bot",
        help="Trace file or directory (default: logs/bot)",
    )
    parser.add_argument(
        "--require-all",
        action="store_true",
        help="Exit non-zero if any command family is missing",
    )
    args = parser.parse_args()

    paths = trace_files(Path(args.path))
    if not paths:
        print("No trace files found")
        return 1

    seen = set()
    turns = 0
    successes = 0

    for file in paths:
        for raw in file.read_text().splitlines():
            raw = raw.strip()
            if not raw:
                continue
            try:
                row = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if row.get("kind") == "session_start":
                continue
            turns += 1
            if row.get("ok"):
                successes += 1
            for tag in row.get("featureTags", []):
                if tag in FAMILIES:
                    seen.add(tag)

    missing = [tag for tag in FAMILIES if tag not in seen]

    print(f"Trace files: {len(paths)}")
    print(f"Turn records: {turns}")
    print(f"Successful turns: {successes}")
    print(f"Families covered: {len(seen)}/{len(FAMILIES)}")
    print("Covered:", ", ".join(sorted(seen)) if seen else "none")
    print("Missing:", ", ".join(missing) if missing else "none")

    if args.require_all and missing:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
