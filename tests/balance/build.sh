#!/usr/bin/env bash
# Balance Test Build Script
# Ensures clean rebuild of simulation binary before testing

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BINARY="$SCRIPT_DIR/run_simulation"

echo "======================================================================="
echo "EC4X Balance Test Build"
echo "======================================================================="
echo ""

# Clean old binary
if [[ -f "$BINARY" ]]; then
    echo "Removing old binary..."
    rm -f "$BINARY"
fi

# Rebuild with latest source
echo "Building simulation binary..."
cd "$SCRIPT_DIR"
nim c -d:release run_simulation.nim

echo ""
echo "======================================================================="
echo "Build complete: $BINARY"
echo "======================================================================="
