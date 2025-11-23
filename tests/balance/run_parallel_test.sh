#!/bin/bash
## Run Parallel Coevolution Test
##
## Usage: ./run_parallel_test.sh [jobs] [generations] [population] [games]

set -e

JOBS=${1:-4}          # Number of parallel runs
GENS=${2:-5}          # Generations per run
POP=${3:-5}           # Population per species
GAMES=${4:-3}         # Inter-species games per generation

RESULTS_DIR="balance_results/coevolution"
mkdir -p "$RESULTS_DIR"

echo "======================================================================="
echo "EC4X Parallel Coevolution Test"
echo "======================================================================="
echo ""
echo "Configuration:"
echo "  Parallel Jobs:    $JOBS"
echo "  Generations:      $GENS per run"
echo "  Population:       $POP per species (x4 species)"
echo "  Games/Gen:        $GAMES"
echo ""
echo "Total: $JOBS runs × $GENS gens × $GAMES games = $(($JOBS * $GENS * $GAMES)) game simulations"
echo ""
echo "Estimated time: ~$((JOBS * GENS * GAMES / 2)) minutes"
echo "======================================================================="
echo ""

# Clean old test runs
rm -f "$RESULTS_DIR"/run_*.json

# Function to run a single coevolution
run_coevolution() {
    local run_id=$1
    local output_file="$RESULTS_DIR/run_${run_id}.json"

    echo "[Run $run_id] Starting..."

    # Run coevolution (redirect stdout to log, keep json output)
    ./tests/balance/coevolution \
        --generations=$GENS \
        --population=$POP \
        --games=$GAMES \
        > "${output_file}.log" 2>&1

    # Move the generated result to our numbered output
    if [ -f "$RESULTS_DIR/coevolution_results.json" ]; then
        mv "$RESULTS_DIR/coevolution_results.json" "$output_file"
        echo "[Run $run_id] ✓ Complete"
    else
        echo "[Run $run_id] ✗ Failed - no output"
        return 1
    fi
}

export -f run_coevolution
export GENS POP GAMES RESULTS_DIR

# Run in parallel
echo "Starting $JOBS parallel runs..."
echo ""

seq 1 $JOBS | parallel -j $JOBS --bar run_coevolution {}

echo ""
echo "======================================================================="
echo "All runs complete! Compiling analysis..."
echo "======================================================================="
echo ""

# Compile and run analysis
if ! [ -f "tests/balance/analyze_results" ]; then
    echo "Compiling analysis tool..."
    nim c --hints:off --warnings:off -d:release -o:tests/balance/analyze_results tests/balance/analyze_results.nim
fi

./tests/balance/analyze_results

echo ""
echo "✅ Test complete!"
echo "Results in: $RESULTS_DIR/"
echo "Report:     $RESULTS_DIR/ANALYSIS_REPORT.md"
