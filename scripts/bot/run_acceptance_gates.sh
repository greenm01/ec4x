#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TRACE_PATH=${1:-"$ROOT_DIR/logs/bot"}
MATRIX_PATH=${2:-"$ROOT_DIR/scripts/bot/scenario_matrix.example.json"}

echo "[gates] trace path: $TRACE_PATH"
echo "[gates] matrix path: $MATRIX_PATH"

python3 "$ROOT_DIR/scripts/bot/summarize_trace_coverage.py" \
  "$TRACE_PATH" --require-all

python3 "$ROOT_DIR/scripts/bot/evaluate_trace_quality.py" \
  "$TRACE_PATH" \
  --require-session-record \
  --min-consecutive-success 20 \
  --min-success-rate 0.75 \
  --max-retry-rate 0.50

python3 "$ROOT_DIR/scripts/bot/run_trace_matrix.py" \
  --root "$ROOT_DIR" \
  --matrix "$MATRIX_PATH" \
  --report "$ROOT_DIR/logs/bot/matrix_report.json"

echo "[gates] all acceptance gates passed"
