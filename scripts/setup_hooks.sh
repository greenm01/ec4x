#!/usr/bin/env bash
#
# Setup git hooks for EC4X project
#
# This script installs pre-commit hooks that:
# - Run integration tests before allowing commits
# - Verify project builds successfully
# - Ensure code quality standards
#
# Usage:
#   bash scripts/setup_hooks.sh

set -e

HOOKS_DIR=".git/hooks"
HOOK_FILE="$HOOKS_DIR/pre-commit"

echo "EC4X Git Hooks Setup"
echo "===================="
echo ""

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "Error: Not in a git repository root"
    echo "Please run this script from the project root directory"
    exit 1
fi

# Create hooks directory if it doesn't exist
mkdir -p "$HOOKS_DIR"

# Create pre-commit hook
cat > "$HOOK_FILE" << 'EOF'
#!/usr/bin/env bash
#
# EC4X Pre-Commit Hook
#
# Runs before each commit to ensure code quality and test coverage
#

set -e

echo "Running pre-commit checks..."
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track overall success
ALL_PASSED=true

# Function to run a check
run_check() {
    local description="$1"
    local command="$2"

    echo -n "  $description... "

    if eval "$command" > /tmp/ec4x_hook_output 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo ""
        echo "Error output:"
        cat /tmp/ec4x_hook_output
        echo ""
        ALL_PASSED=false
        return 1
    fi
}

echo "1. Code Quality Checks"
echo "----------------------"

# Check for non-pure enums
if grep -rn "= enum" src/ --include="*.nim" | grep -v "{.pure.}" > /dev/null 2>&1; then
    echo -e "  ${RED}✗${NC} Found non-pure enums"
    grep -rn "= enum" src/ --include="*.nim" | grep -v "{.pure.}"
    echo ""
    echo "All enums must be {.pure.} per NEP-1 conventions"
    ALL_PASSED=false
else
    echo -e "  ${GREEN}✓${NC} All enums are pure"
fi

# Check for UPPER_SNAKE_CASE constants
if grep -rn "^[[:space:]]*[A-Z_][A-Z_0-9]*\*\?[[:space:]]*=" src/ --include="*.nim" | \
   grep -v "type\|proc\|var\|let" | \
   grep "const" > /dev/null 2>&1; then
    echo -e "  ${RED}✗${NC} Found UPPER_SNAKE_CASE constants"
    echo ""
    echo "Constants must use camelCase per NEP-1 conventions"
    ALL_PASSED=false
else
    echo -e "  ${GREEN}✓${NC} All constants use camelCase"
fi

echo ""
echo "2. Build Verification"
echo "---------------------"

# Verify project builds
run_check "Building project" "nimble build --verbosity:0"

echo ""
echo "3. Test Suite"
echo "-------------"

# Run a subset of critical integration tests
# (Running all 76+ tests would be too slow for pre-commit)
CRITICAL_TESTS=(
    "tests/integration/test_prestige.nim"
    "tests/integration/test_espionage.nim"
    "tests/integration/test_victory_conditions.nim"
)

for test in "${CRITICAL_TESTS[@]}"; do
    if [ -f "$test" ]; then
        test_name=$(basename "$test" .nim)
        run_check "Running $test_name" "nim c --hints:off -r $test"
    fi
done

echo ""
echo "========================================="

if [ "$ALL_PASSED" = true ]; then
    echo -e "${GREEN}✓ All pre-commit checks passed!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some checks failed${NC}"
    echo ""
    echo "Please fix the issues above before committing."
    echo ""
    echo "To bypass this hook (not recommended):"
    echo "  git commit --no-verify"
    echo ""
    exit 1
fi
EOF

# Make the hook executable
chmod +x "$HOOK_FILE"

echo "✓ Pre-commit hook installed at $HOOK_FILE"
echo ""
echo "The hook will run automatically before each commit."
echo ""
echo "What the hook checks:"
echo "  1. All enums are {.pure.}"
echo "  2. All constants use camelCase"
echo "  3. Project builds successfully"
echo "  4. Critical integration tests pass"
echo ""
echo "To bypass the hook (not recommended):"
echo "  git commit --no-verify"
echo ""
echo "Setup complete!"
