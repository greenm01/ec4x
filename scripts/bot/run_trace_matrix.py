#!/usr/bin/env python3
"""Evaluate scenario-matrix trace coverage and stability gates."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any


def parse_trace(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {
            "exists": False,
            "turns": 0,
            "successes": 0,
            "longestConsecutiveSuccess": 0,
            "featureTags": set(),
            "errorClasses": {},
        }

    turns = 0
    successes = 0
    longest_streak = 0
    streak = 0
    tags: set[str] = set()
    error_classes: dict[str, int] = {}

    for raw in path.read_text().splitlines():
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
        ok = bool(row.get("ok", False))
        if ok:
            successes += 1
            streak += 1
            longest_streak = max(longest_streak, streak)
        else:
            streak = 0

        error_class = str(row.get("errorClass", "unknown"))
        error_classes[error_class] = error_classes.get(error_class, 0) + 1

        for tag in row.get("featureTags", []):
            tags.add(str(tag))

    return {
        "exists": True,
        "turns": turns,
        "successes": successes,
        "longestConsecutiveSuccess": longest_streak,
        "featureTags": tags,
        "errorClasses": error_classes,
    }


def evaluate_scenario(root: Path, scenario: dict[str, Any]) -> dict[str, Any]:
    name = str(scenario.get("name", "unnamed"))
    trace_rel = str(scenario.get("trace", ""))
    trace_path = (root / trace_rel).resolve()

    required_tags = [str(tag) for tag in scenario.get("requiredTags", [])]
    min_turns = int(scenario.get("minTurns", 1))
    min_streak = int(scenario.get("minConsecutiveSuccess", 1))

    stats = parse_trace(trace_path)
    missing = [tag for tag in required_tags if tag not in stats["featureTags"]]

    passed = (
        stats["exists"]
        and stats["turns"] >= min_turns
        and stats["longestConsecutiveSuccess"] >= min_streak
        and len(missing) == 0
    )

    return {
        "name": name,
        "trace": str(trace_path),
        "passed": passed,
        "turns": stats["turns"],
        "successes": stats["successes"],
        "longestConsecutiveSuccess": stats["longestConsecutiveSuccess"],
        "requiredTags": required_tags,
        "missingTags": missing,
        "errorClasses": stats["errorClasses"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run trace-based scenario matrix checks"
    )
    parser.add_argument(
        "--matrix",
        default="scripts/bot/scenario_matrix.json",
        help="Scenario matrix JSON path",
    )
    parser.add_argument(
        "--root",
        default=".",
        help="Root directory for relative trace paths",
    )
    parser.add_argument(
        "--report",
        default="",
        help="Optional JSON report output path",
    )
    args = parser.parse_args()

    matrix_path = Path(args.matrix)
    if not matrix_path.exists():
        print(f"Matrix file not found: {matrix_path}")
        return 1

    try:
        matrix = json.loads(matrix_path.read_text())
    except json.JSONDecodeError as exc:
        print(f"Invalid matrix JSON: {exc}")
        return 1

    scenarios = matrix.get("scenarios", [])
    if not isinstance(scenarios, list) or len(scenarios) == 0:
        print("Matrix contains no scenarios")
        return 1

    root = Path(args.root).resolve()
    results = [evaluate_scenario(root, item) for item in scenarios]

    passed = sum(1 for item in results if item["passed"])
    print(f"Scenarios passed: {passed}/{len(results)}")
    for item in results:
        status = "PASS" if item["passed"] else "FAIL"
        missing = ",".join(item["missingTags"]) if item["missingTags"] else "none"
        print(
            f"- {status} {item['name']}: turns={item['turns']}, "
            f"streak={item['longestConsecutiveSuccess']}, missing={missing}"
        )

    if args.report:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            json.dumps({"matrix": str(matrix_path), "results": results}, indent=2)
        )

    return 0 if passed == len(results) else 2


if __name__ == "__main__":
    sys.exit(main())
