#!/usr/bin/env bash
# Unified Balance Test Runner - ONE SOURCE OF TRUTH
# Ensures: clean build → test execution with proper alignment

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default values
WORKERS=16
GAMES=100
TURNS=30
FORCE_REBUILD=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --workers)
      WORKERS="$2"
      shift 2
      ;;
    --games)
      GAMES="$2"
      shift 2
      ;;
    --turns)
      TURNS="$2"
      shift 2
      ;;
    --rebuild)
      FORCE_REBUILD=true
      shift
      ;;
    --help|-h)
      echo "Usage: run_test.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --workers N    Number of parallel workers (default: 16)"
      echo "  --games N      Number of games to simulate (default: 100)"
      echo "  --turns N      Number of turns per game (default: 30)"
      echo "  --rebuild      Force clean rebuild before testing"
      echo "  --help, -h     Show this help message"
      echo ""
      echo "Examples:"
      echo "  run_test.sh --turns 7 --games 100          # Act 1 validation"
      echo "  run_test.sh --turns 15 --games 100         # Act 2 validation"
      echo "  run_test.sh --turns 30 --games 100         # Full game test"
      echo "  run_test.sh --rebuild --turns 30           # Force rebuild first"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo "======================================================================="
echo "EC4X UNIFIED BALANCE TEST"
echo "======================================================================="
echo "Configuration:"
echo "  Workers:      $WORKERS"
echo "  Games:        $GAMES"
echo "  Turns:        $TURNS"
echo "  Force Rebuild: $FORCE_REBUILD"
echo "======================================================================="
echo ""

# Step 1: Ensure binary is up to date
BINARY="$SCRIPT_DIR/run_simulation"
if [[ "$FORCE_REBUILD" == "true" ]] || [[ ! -f "$BINARY" ]]; then
  echo "[1/2] Building simulation binary..."
  "$SCRIPT_DIR/build.sh"
  echo ""
else
  echo "[1/2] Using existing binary (use --rebuild to force clean build)"
  echo ""
fi

# Step 2: Run parallel tests
echo "[2/2] Running parallel balance tests..."
cd "$SCRIPT_DIR/../.."  # Go to project root
python3 tests/balance/run_balance_test_parallel.py \
  --workers "$WORKERS" \
  --games "$GAMES" \
  --turns "$TURNS"

echo ""
echo "======================================================================="
echo "Test complete!"
echo "Results: balance_results/parallel_test_*.json"
echo "Diagnostics: balance_results/diagnostics/*.csv"
echo "======================================================================="
