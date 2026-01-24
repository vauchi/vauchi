#!/bin/bash
# Feature Audit Script
#
# This script analyzes the gap between:
# 1. Gherkin feature scenarios in features/*.feature
# 2. Actual test implementations in tests/
#
# It generates a report showing which features need test coverage.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# _dev-tools/scripts -> workspace root
WORKSPACE_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CODE_ROOT="$WORKSPACE_ROOT/core"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║        Vauchi Feature Audit            ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
echo ""

cd "$WORKSPACE_ROOT"

# === Count Feature Scenarios ===
echo -e "${BLUE}=== Feature Scenarios ===${NC}"
echo ""

TOTAL_SCENARIOS=0
declare -A FEATURE_COUNTS

FEATURES_DIR="$WORKSPACE_ROOT/features"
FUTURE_DIR="$FEATURES_DIR/future"

if [[ ! -d "$FEATURES_DIR" ]]; then
    echo -e "${RED}Error: features/ directory not found${NC}"
    exit 1
fi

printf "%-40s %8s %8s\n" "Feature" "Scenarios" "Status"
printf "%s\n" "────────────────────────────────────────────────────────────"

# Main features
for feature_file in "$FEATURES_DIR"/*.feature; do
    if [[ -f "$feature_file" ]]; then
        filename=$(basename "$feature_file" .feature)
        # Count Scenario: and Scenario Outline: lines
        count=$(grep -cE '^\s*(Scenario:|Scenario Outline:)' "$feature_file" 2>/dev/null || echo "0")
        FEATURE_COUNTS["$filename"]=$count
        TOTAL_SCENARIOS=$((TOTAL_SCENARIOS + count))

        # Determine status (heuristic based on known implementation state)
        status="${GREEN}Active${NC}"
        if [[ "$filename" == "visibility_labels" ]]; then
            status="${RED}0% done${NC}"
        elif [[ "$filename" == "social_profile_validation" ]]; then
            status="${YELLOW}Low priority${NC}"
        fi

        printf "%-40s %8d %b\n" "$filename" "$count" "$status"
    fi
done

# Future features
echo ""
echo -e "${CYAN}Future (planned):${NC}"
if [[ -d "$FUTURE_DIR" ]]; then
    for feature_file in "$FUTURE_DIR"/*.feature; do
        if [[ -f "$feature_file" ]]; then
            filename=$(basename "$feature_file" .feature)
            count=$(grep -cE '^\s*(Scenario:|Scenario Outline:)' "$feature_file" 2>/dev/null || echo "0")
            FEATURE_COUNTS["future/$filename"]=$count
            printf "  %-38s %8d ${YELLOW}Planned${NC}\n" "$filename" "$count"
        fi
    done
fi

echo ""
printf "%s\n" "────────────────────────────────────────────────────────────"
printf "%-40s %8d\n" "TOTAL MAIN SCENARIOS" "$TOTAL_SCENARIOS"

# === Count Test Functions ===
echo ""
echo -e "${BLUE}=== Test Coverage by Crate ===${NC}"
echo ""

printf "%-25s %10s %10s\n" "Crate" "Tests" "Files"
printf "%s\n" "──────────────────────────────────────────────"

TOTAL_TESTS=0
TOTAL_TEST_FILES=0

for crate_dir in vauchi-core vauchi-cli vauchi-tui vauchi-relay vauchi-mobile vauchi-desktop/src-tauri; do
    crate_name=$(basename "$crate_dir")
    tests_dir="$CODE_ROOT/$crate_dir/tests"
    src_dir="$CODE_ROOT/$crate_dir/src"

    if [[ -d "$tests_dir" ]]; then
        # Count #[test] annotations in tests/
        test_count=$(grep -rh '#\[test\]' "$tests_dir" 2>/dev/null | wc -l | tr -d ' ')
        file_count=$(find "$tests_dir" -name "*.rs" -type f 2>/dev/null | wc -l | tr -d ' ')
    else
        test_count=0
        file_count=0
    fi

    # Also count inline tests in src/ (if any)
    if [[ -d "$src_dir" ]]; then
        inline_tests=$(grep -rh '#\[test\]' "$src_dir" 2>/dev/null | wc -l | tr -d ' ')
        test_count=$((test_count + inline_tests))
    fi

    TOTAL_TESTS=$((TOTAL_TESTS + test_count))
    TOTAL_TEST_FILES=$((TOTAL_TEST_FILES + file_count))

    # Color based on count
    if [[ $test_count -eq 0 ]]; then
        color=$RED
    elif [[ $test_count -lt 10 ]]; then
        color=$YELLOW
    else
        color=$GREEN
    fi

    printf "%-25s %b%10d%b %10d\n" "$crate_name" "$color" "$test_count" "$NC" "$file_count"
done

echo ""
printf "%s\n" "──────────────────────────────────────────────"
printf "%-25s %10d %10d\n" "TOTAL" "$TOTAL_TESTS" "$TOTAL_TEST_FILES"

# === Feature-to-Test Mapping ===
echo ""
echo -e "${BLUE}=== Feature-to-Test Mapping ===${NC}"
echo ""

# Map feature names to test patterns
declare -A FEATURE_TEST_PATTERNS
FEATURE_TEST_PATTERNS["identity_management"]="identity|init|export|import"
FEATURE_TEST_PATTERNS["contact_card_management"]="card|field|contact_card"
FEATURE_TEST_PATTERNS["contact_exchange"]="exchange|qr|x3dh"
FEATURE_TEST_PATTERNS["contacts_management"]="contact|contacts"
FEATURE_TEST_PATTERNS["device_management"]="device|link"
FEATURE_TEST_PATTERNS["sync_updates"]="sync|delta|update"
FEATURE_TEST_PATTERNS["security"]="crypto|encrypt|sign|security"
FEATURE_TEST_PATTERNS["visibility_control"]="visibility|visible"
FEATURE_TEST_PATTERNS["visibility_labels"]="label"
FEATURE_TEST_PATTERNS["relay_network"]="relay|network|transport|websocket"
FEATURE_TEST_PATTERNS["social_profile_validation"]="social|profile|validation"
FEATURE_TEST_PATTERNS["contact_actions"]="action"

printf "%-30s %10s %12s %10s\n" "Feature" "Scenarios" "Est. Tests" "Coverage"
printf "%s\n" "───────────────────────────────────────────────────────────────"

for feature in "${!FEATURE_COUNTS[@]}"; do
    # Skip future features
    [[ "$feature" == future/* ]] && continue

    scenarios=${FEATURE_COUNTS[$feature]}
    pattern=${FEATURE_TEST_PATTERNS[$feature]:-"$feature"}

    # Count tests matching the pattern
    if [[ -d "$CODE_ROOT/vauchi-core/tests" ]]; then
        matched_tests=$(grep -rlE "fn test_.*($pattern)" "$CODE_ROOT/vauchi-core/tests" 2>/dev/null | wc -l | tr -d ' ')
    else
        matched_tests=0
    fi

    # Estimate coverage percentage
    if [[ $scenarios -gt 0 ]]; then
        # Rough estimate: 2-3 tests per scenario is good coverage
        coverage_pct=$((matched_tests * 100 / (scenarios * 2)))
        [[ $coverage_pct -gt 100 ]] && coverage_pct=100
    else
        coverage_pct=0
    fi

    # Color based on coverage
    if [[ $coverage_pct -ge 80 ]]; then
        color=$GREEN
    elif [[ $coverage_pct -ge 40 ]]; then
        color=$YELLOW
    else
        color=$RED
    fi

    printf "%-30s %10d %12d %b%9d%%%b\n" "$feature" "$scenarios" "$matched_tests" "$color" "$coverage_pct" "$NC"
done

# === Gaps Report ===
echo ""
echo -e "${BLUE}=== Priority Gaps ===${NC}"
echo ""

echo -e "${RED}CRITICAL (0% coverage):${NC}"
echo "  - visibility_labels.feature (41 scenarios) - Core feature not implemented"
echo ""

echo -e "${YELLOW}HIGH (needs tests):${NC}"
echo "  - vauchi-cli: 0 tests (uses MockTransport)"
echo "  - vauchi-tui: 0 tests (sync is stubbed)"
echo "  - vauchi-desktop: 0 tests"
echo ""

echo -e "${CYAN}MEDIUM (verify coverage):${NC}"
echo "  - contact_exchange (QR done, BLE/NFC planned)"
echo "  - relay_network (~47% implemented)"
echo ""

# === Summary ===
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║             Summary                    ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Total feature scenarios: $TOTAL_SCENARIOS"
echo "Total test functions:    $TOTAL_TESTS"
echo ""
echo "Estimated ratio: $(echo "scale=2; $TOTAL_TESTS / $TOTAL_SCENARIOS" | bc) tests/scenario"
echo "(Target: 2-3 tests per scenario for good coverage)"
