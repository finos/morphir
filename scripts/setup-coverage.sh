#!/usr/bin/env bash
# setup-coverage.sh - Set up and verify code coverage for all Go modules
#
# This script:
# 1. Discovers all Go modules in the repository
# 2. Verifies each module can run tests with coverage
# 3. Reports any issues with coverage setup
# 4. Shows summary of all covered modules
#
# Usage:
#   ./scripts/setup-coverage.sh           # Discover and verify all modules
#   ./scripts/setup-coverage.sh --check   # Check only, don't run tests
#   ./scripts/setup-coverage.sh --list    # List all discoverable modules

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
CHECK_ONLY=false
LIST_ONLY=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--check|--list]"
            exit 1
            ;;
    esac
done

# Discover all Go modules (directories containing go.mod)
discover_modules() {
    find "$REPO_ROOT" -name "go.mod" -type f \
        ! -path "*/vendor/*" \
        ! -path "*/.git/*" \
        ! -path "*/testdata/*" \
        -exec dirname {} \; | \
        sed "s|^$REPO_ROOT/||" | \
        sort
}

# Check if a module has any Go test files
has_tests() {
    local module_path="$1"
    find "$REPO_ROOT/$module_path" -name "*_test.go" -type f | head -1 | grep -q .
}

# Check if a module can run tests
can_run_tests() {
    local module_path="$1"
    cd "$REPO_ROOT/$module_path"
    go test -c ./... -o /dev/null 2>/dev/null
}

echo -e "${BLUE}=== Morphir Code Coverage Setup ===${NC}"
echo ""

# Discover all modules
echo -e "${BLUE}Discovering Go modules...${NC}"
MODULES=($(discover_modules))

if [ ${#MODULES[@]} -eq 0 ]; then
    echo -e "${RED}Error: No Go modules found in repository${NC}"
    exit 1
fi

echo -e "Found ${GREEN}${#MODULES[@]}${NC} Go modules"
echo ""

# List only mode
if [ "$LIST_ONLY" = true ]; then
    echo -e "${BLUE}All discoverable modules:${NC}"
    for module in "${MODULES[@]}"; do
        echo "  - $module"
    done
    exit 0
fi

# Categorize modules
TESTABLE_MODULES=()
NO_TEST_MODULES=()
FAILED_MODULES=()

echo -e "${BLUE}Analyzing modules...${NC}"
for module in "${MODULES[@]}"; do
    if has_tests "$module"; then
        if [ "$CHECK_ONLY" = false ]; then
            if can_run_tests "$module"; then
                TESTABLE_MODULES+=("$module")
                echo -e "  ${GREEN}✓${NC} $module"
            else
                FAILED_MODULES+=("$module")
                echo -e "  ${RED}✗${NC} $module (test compilation failed)"
            fi
        else
            TESTABLE_MODULES+=("$module")
            echo -e "  ${GREEN}✓${NC} $module (has tests)"
        fi
    else
        NO_TEST_MODULES+=("$module")
        echo -e "  ${YELLOW}○${NC} $module (no tests)"
    fi
done

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "  Testable modules:    ${GREEN}${#TESTABLE_MODULES[@]}${NC}"
echo -e "  Modules without tests: ${YELLOW}${#NO_TEST_MODULES[@]}${NC}"
if [ ${#FAILED_MODULES[@]} -gt 0 ]; then
    echo -e "  Failed modules:      ${RED}${#FAILED_MODULES[@]}${NC}"
fi

# Generate MODULES array for scripts
echo ""
echo -e "${BLUE}=== MODULES array for scripts ===${NC}"
echo "Copy this to scripts/test-junit.sh and scripts/test-coverage.sh:"
echo ""
echo "MODULES=("
for module in "${TESTABLE_MODULES[@]}"; do
    echo "    \"$module\""
done
echo ")"

# Run quick coverage test if not check-only
if [ "$CHECK_ONLY" = false ] && [ ${#TESTABLE_MODULES[@]} -gt 0 ]; then
    echo ""
    echo -e "${BLUE}=== Running coverage verification ===${NC}"

    mkdir -p "$REPO_ROOT/coverage"
    PASSED=0
    FAILED=0

    for module in "${TESTABLE_MODULES[@]}"; do
        MODULE_NAME=$(basename "$module")
        echo -n "  Testing $module... "

        if cd "$REPO_ROOT/$module" && \
           go test -coverprofile="$REPO_ROOT/coverage/${MODULE_NAME}.out" \
                   -covermode=atomic ./... >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
            ((PASSED++))
        else
            echo -e "${RED}FAILED${NC}"
            ((FAILED++))
        fi
    done

    echo ""
    echo -e "${BLUE}=== Coverage Verification Results ===${NC}"
    echo -e "  Passed: ${GREEN}$PASSED${NC}"
    if [ $FAILED -gt 0 ]; then
        echo -e "  Failed: ${RED}$FAILED${NC}"
    fi

    # Merge coverage
    if [ $PASSED -gt 0 ]; then
        echo ""
        echo -e "${BLUE}Merging coverage profiles...${NC}"
        cd "$REPO_ROOT"
        echo "mode: atomic" > coverage.out
        grep -h -v "^mode:" coverage/*.out >> coverage.out 2>/dev/null || true

        echo ""
        echo -e "${BLUE}Coverage Summary:${NC}"
        go tool cover -func=coverage.out | tail -1
    fi
fi

# Show next steps
echo ""
echo -e "${BLUE}=== Next Steps ===${NC}"
if [ ${#NO_TEST_MODULES[@]} -gt 0 ]; then
    echo "  1. Consider adding tests to modules without test coverage:"
    for module in "${NO_TEST_MODULES[@]}"; do
        echo "     - $module"
    done
fi
if [ ${#FAILED_MODULES[@]} -gt 0 ]; then
    echo "  2. Fix test compilation issues in:"
    for module in "${FAILED_MODULES[@]}"; do
        echo "     - $module"
    done
fi
echo ""
echo "  To view detailed coverage:"
echo "    go tool cover -html=coverage.out"
echo ""
echo "  To run full coverage with JUnit reports:"
echo "    mise run test-junit"
