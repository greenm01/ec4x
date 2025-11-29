#!/usr/bin/env bash
## Integration Test Runner
## Runs all integration tests and reports summary

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "╔════════════════════════════════════════════════╗"
echo "║  EC4X Integration Test Suite Runner           ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

# Change to project root
cd "$(dirname "$0")/.."

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
declare -a FAILED_FILES

# Find all integration test files
TEST_FILES=$(find tests/integration -name "test_*.nim" -type f | sort)
TEST_COUNT=$(echo "$TEST_FILES" | wc -l)

echo "Found $TEST_COUNT integration test files"
echo ""

# Run each test
for test_file in $TEST_FILES; do
    test_name=$(basename "$test_file")
    echo -n "Testing $test_name ... "

    # Compile and run test, capture output
    if timeout 120 nim c -r --hints:off "$test_file" > /tmp/test_output.log 2>&1; then
        # Count passing tests
        ok_count=$(grep -c "\[OK\]" /tmp/test_output.log || echo "0")
        failed_count=$(grep -c "\[FAILED\]" /tmp/test_output.log || echo "0")

        TOTAL_TESTS=$((TOTAL_TESTS + ok_count + failed_count))
        PASSED_TESTS=$((PASSED_TESTS + ok_count))
        FAILED_TESTS=$((FAILED_TESTS + failed_count))

        if [ "$failed_count" -gt 0 ]; then
            echo -e "${RED}FAILED${NC} ($ok_count passed, $failed_count failed)"
            FAILED_FILES+=("$test_name")
        else
            echo -e "${GREEN}PASSED${NC} ($ok_count tests)"
        fi
    else
        echo -e "${RED}ERROR${NC} (compilation or runtime error)"
        FAILED_FILES+=("$test_name")
        # Check if it was a timeout
        if grep -q "timed out" /tmp/test_output.log 2>/dev/null; then
            echo "  (test timed out after 120 seconds)"
        fi
    fi
done

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║  Test Summary                                   ║"
echo "╚════════════════════════════════════════════════╝"
echo ""
echo "Total test cases: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
if [ "$FAILED_TESTS" -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
else
    echo "Failed: 0"
fi
echo ""

if [ ${#FAILED_FILES[@]} -gt 0 ]; then
    echo -e "${YELLOW}Failed test files:${NC}"
    for file in "${FAILED_FILES[@]}"; do
        echo "  - $file"
    done
    echo ""
    exit 1
else
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
fi
