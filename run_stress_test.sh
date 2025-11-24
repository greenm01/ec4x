#!/bin/bash
# EC4X Stress Test - 100,000 games using GNU Parallel
# Maximizes CPU usage by running multiple games in parallel

set -euo pipefail

TARGET_GAMES=100000
NUM_CORES=$(nproc)
JOBS=$((NUM_CORES))  # Run as many jobs as cores

echo "======================================================================"
echo "EC4X STRESS TEST - $TARGET_GAMES Games"
echo "======================================================================"
echo "CPU Cores: $NUM_CORES"
echo "Parallel Jobs: $JOBS"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Create temp directory for results
RESULTS_DIR=$(mktemp -d)
trap "rm -rf $RESULTS_DIR" EXIT

echo "Results directory: $RESULTS_DIR"
echo ""

# Function to run a single game
run_game() {
    local game_num=$1
    local seed=$((1000 + game_num))

    # Weighted random config selection
    local rand=$((RANDOM % 100))
    local players rings turns

    if [ $rand -lt 50 ]; then
        players=4; rings=4; turns=30
    elif [ $rand -lt 70 ]; then
        players=6; rings=6; turns=30
    elif [ $rand -lt 85 ]; then
        players=8; rings=8; turns=30
    elif [ $rand -lt 95 ]; then
        players=10; rings=10; turns=30
    else
        players=12; rings=12; turns=30
    fi

    # Run simulation
    timeout 60 ./tests/balance/run_simulation $turns $seed $rings $players > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "SUCCESS" > "$RESULTS_DIR/$game_num.result"
    else
        echo "FAILED:${players}p-${rings}r:seed$seed" > "$RESULTS_DIR/$game_num.result"
    fi
}

export -f run_game
export RESULTS_DIR

# Generate game numbers and run in parallel
echo "Launching parallel simulations..."
seq 1 $TARGET_GAMES | \
    parallel --bar --jobs $JOBS --halt now,fail=1 \
    'run_game {}'

# Analyze results
echo ""
echo "======================================================================"
echo "Analyzing results..."
echo "======================================================================"

TOTAL=$(find "$RESULTS_DIR" -name "*.result" | wc -l)
SUCCESS=$(grep -l "SUCCESS" "$RESULTS_DIR"/*.result 2>/dev/null | wc -l)
FAILED=$((TOTAL - SUCCESS))

SUCCESS_RATE=$(awk "BEGIN {printf \"%.2f\", ($SUCCESS/$TOTAL)*100}")

echo "Total Games: $TOTAL"
echo "Successful: $SUCCESS ($SUCCESS_RATE%)"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Failed Game Details:"
    echo "--------------------------------------------------------------------"

    # Create crash log
    CRASH_LOG="stress_test_crashes.log"
    echo "EC4X Stress Test - $(date)" > $CRASH_LOG
    echo "Total: $TOTAL | Success: $SUCCESS | Failed: $FAILED" >> $CRASH_LOG
    echo "======================================================================" >> $CRASH_LOG
    echo "" >> $CRASH_LOG

    # Count crashes by configuration
    declare -A crash_counts

    for result_file in "$RESULTS_DIR"/*.result; do
        if ! grep -q "SUCCESS" "$result_file"; then
            game_num=$(basename "$result_file" .result)
            config=$(cat "$result_file" | cut -d: -f2)
            crash_counts[$config]=$((${crash_counts[$config]:-0} + 1))

            echo "Game #$game_num: $(cat $result_file)" >> $CRASH_LOG
        fi
    done

    # Print crash distribution
    echo ""
    echo "Crash Distribution:"
    for config in "${!crash_counts[@]}"; do
        count=${crash_counts[$config]}
        pct=$(awk "BEGIN {printf \"%.1f\", ($count/$FAILED)*100}")
        echo "  $config: $count crashes ($pct%)"
        echo "  $config: $count crashes ($pct%)" >> $CRASH_LOG
    done

    echo ""
    echo "Detailed crash log saved to: $CRASH_LOG"
else
    echo ""
    echo "🎉 NO CRASHES DETECTED! System is stable!"
fi

echo ""
echo "Completed: $(date '+%Y-%m-%d %H:%M:%S')"
