#!/bin/bash
## API Documentation Generation Script for EC4X
##
## Generates HTML documentation using Nim's built-in nimdoc tool
## Usage: ./generate_docs.sh [module_path]

set -e

# Configuration
PROJECT_ROOT="/home/niltempus/dev/ec4x"
DOCS_OUTPUT="$PROJECT_ROOT/docs/api/engine"
SRC_ENGINE="$PROJECT_ROOT/src/engine"
SRC_TYPES="$PROJECT_ROOT/src/common/types"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== EC4X API Documentation Generator ===${NC}"

# Function to generate docs for a single module
generate_module_docs() {
    local module_path=$1
    local module_name=$(basename "$module_path" .nim)
    local output_file="$DOCS_OUTPUT/${module_name}.html"

    echo -e "${GREEN}Generating docs for: $module_name${NC}"

    nim doc --project --index:on \
        --git.url:https://github.com/niltempus/ec4x \
        --git.commit:main \
        --outdir:"$DOCS_OUTPUT" \
        "$module_path"

    if [ -f "$output_file" ]; then
        echo "  ✓ Generated: $output_file"
    else
        echo "  ✗ Failed to generate: $module_name"
    fi
}

# If specific module provided, generate only that
if [ $# -eq 1 ]; then
    generate_module_docs "$1"
    exit 0
fi

# Otherwise, generate all engine module docs
echo ""
echo "Generating documentation for all engine modules..."
echo ""

# Core types (foundation)
echo -e "${BLUE}--- Core Types ---${NC}"
generate_module_docs "$SRC_TYPES/core.nim"
generate_module_docs "$SRC_TYPES/units.nim"
generate_module_docs "$SRC_TYPES/combat.nim"
generate_module_docs "$SRC_TYPES/planets.nim"

# Engine modules
echo ""
echo -e "${BLUE}--- Engine Modules ---${NC}"
generate_module_docs "$SRC_ENGINE/ship.nim"
generate_module_docs "$SRC_ENGINE/squadron.nim"
generate_module_docs "$SRC_ENGINE/spacelift.nim"
generate_module_docs "$SRC_ENGINE/fleet.nim"
generate_module_docs "$SRC_ENGINE/gamestate.nim"
generate_module_docs "$SRC_ENGINE/starmap.nim"
generate_module_docs "$SRC_ENGINE/resolve.nim"

# Generate index
echo ""
echo -e "${BLUE}--- Generating Index ---${NC}"
nim buildIndex -o:"$DOCS_OUTPUT/theindex.html" "$DOCS_OUTPUT"

echo ""
echo -e "${GREEN}✓ Documentation generation complete!${NC}"
echo "View docs at: file://$DOCS_OUTPUT/index.html"
