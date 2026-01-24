#!/bin/bash
# Coverage Verification Script
# 
# Enforces 90% minimum test coverage for vauchi-core
# Generates detailed coverage reports and identifies gaps
#
# Usage: ./coverage-verify.sh [options]
# Options:
#   --min-percent N    Minimum coverage percentage (default: 90)
#   --html             Generate HTML report
#   --json             Generate JSON report
#   --check-only       Only check coverage, don't generate reports
#   --crate CRATE      Check specific crate only
#   --fail-on-warn     Treat warnings as failures

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CODE_ROOT="$WORKSPACE_ROOT/core"

# Configuration
MIN_COVERAGE=90
GENERATE_HTML=false
GENERATE_JSON=false
CHECK_ONLY=false
SPECIFIC_CRATE=""
FAIL_ON_WARN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --min-percent)
            MIN_COVERAGE="$2"
            shift 2
            ;;
        --html)
            GENERATE_HTML=true
            shift
            ;;
        --json)
            GENERATE_JSON=true
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --crate)
            SPECIFIC_CRATE="$2"
            shift 2
            ;;
        --fail-on-warn)
            FAIL_ON_WARN=true
            shift
            ;;
        --help)
            echo "Coverage Verification Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --min-percent N    Minimum coverage percentage (default: 90)"
            echo "  --html             Generate HTML report"
            echo "  --json             Generate JSON report"
            echo "  --check-only       Only check coverage, don't generate reports"
            echo "  --crate CRATE      Check specific crate only"
            echo "  --fail-on-warn     Treat warnings as failures"
            echo "  --help             Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Coverage Verification                 ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# Check dependencies
check_dependencies() {
    if ! command -v cargo-llvm-cov &> /dev/null; then
        echo -e "${RED}Error: cargo-llvm-cov not found${NC}"
        echo "Install with: cargo install cargo-llvm-cov"
        exit 1
    fi
    
    if ! command -v bc &> /dev/null; then
        echo -e "${RED}Error: bc calculator not found${NC}"
        echo "Install with: sudo apt-get install bc (Ubuntu/Debian)"
        echo "Or: brew install bc (macOS)"
        exit 1
    fi
}

# Run coverage and parse results
run_coverage() {
    local crate_filter=""
    if [[ -n "$SPECIFIC_CRATE" ]]; then
        crate_filter="-p $SPECIFIC_CRATE"
    fi
    
    cd "$CODE_ROOT"
    
    echo -e "${BLUE}Running coverage analysis...${NC}"
    
    if [[ $CHECK_ONLY == true ]]; then
        # Just get text output for checking
        COVERAGE_OUTPUT=$(cargo llvm-cov --workspace $crate_filter --text 2>/dev/null)
    else
        # Generate reports
        local cov_args="--workspace $crate_filter"
        
        if [[ $GENERATE_HTML == true ]]; then
            cov_args="$cov_args --html --output-path target/llvm-cov/html"
        fi
        
        if [[ $GENERATE_JSON == true ]]; then
            cov_args="$cov_args --json --output-path target/llvm-cov/coverage.json"
        fi
        
        COVERAGE_OUTPUT=$(cargo llvm-cov $cov_args --text 2>/dev/null)
    fi
    
    cd - > /dev/null
    
    if [[ -z "$COVERAGE_OUTPUT" ]]; then
        echo -e "${RED}Error: Failed to generate coverage report${NC}"
        exit 1
    fi
}

# Extract coverage percentage from output
extract_coverage() {
    echo "$COVERAGE_OUTPUT" | grep -E '^\s*[0-9]+\.[0-9]+%' | tail -1 | grep -oE '[0-9]+\.[0-9]+' || echo "0"
}

# Parse detailed coverage by file
parse_file_coverage() {
    echo "$COVERAGE_OUTPUT" | grep -E '\.rs:' | while read line; do
        # Extract file path and percentage
        if [[ $line =~ ([^:]+):\ *([0-9]+\.[0-9]+)% ]]; then
            local file="${BASH_REMATCH[1]}"
            local percent="${BASH_REMATCH[2]}"
            echo "$file|$percent"
        fi
    done
}

# Analyze coverage gaps
analyze_coverage_gaps() {
    echo ""
    echo -e "${BLUE}=== Coverage Analysis ===${NC}"
    echo ""
    
    # Find files below threshold
    local low_coverage_files=()
    local uncovered_files=()
    
    while IFS='|' read -r file percent; do
        if [[ -n "$file" && -n "$percent" ]]; then
            # Convert to float for comparison
            if (( $(echo "$percent < $MIN_COVERAGE" | bc -l) )); then
                if (( $(echo "$percent == 0" | bc -l) )); then
                    uncovered_files+=("$file")
                else
                    low_coverage_files+=("$file ($percent%)")
                fi
            fi
        fi
    done < <(parse_file_coverage)
    
    # Report uncovered files
    if [[ ${#uncovered_files[@]} -gt 0 ]]; then
        echo -e "${RED}Uncovered files (0%):${NC}"
        for file in "${uncovered_files[@]}"; do
            echo "  - $file"
        done
        echo ""
    fi
    
    # Report low coverage files
    if [[ ${#low_coverage_files[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Low coverage files (< ${MIN_COVERAGE}%):${NC}"
        for file in "${low_coverage_files[@]}"; do
            echo "  - $file"
        done
        echo ""
    fi
    
    # Return counts for summary
    echo ${#uncovered_files[@]} ${#low_coverage_files[@]}
}

# Generate recommendations
generate_recommendations() {
    local uncovered_count="$1"
    local low_coverage_count="$2"
    
    echo -e "${CYAN}=== Recommendations ===${NC}"
    echo ""
    
    if [[ $uncovered_count -gt 0 ]]; then
        echo "1. Add tests for uncovered files:"
        echo "   - Use: ./_dev-tools/scripts/tdd-template.sh unit <test_name>"
        echo "   - Focus on critical paths first"
        echo ""
    fi
    
    if [[ $low_coverage_count -gt 0 ]]; then
        echo "2. Improve coverage for low-coverage files:"
        echo "   - Add edge case tests"
        echo "   - Add error condition tests"
        echo "   - Review for untested branches"
        echo ""
    fi
    
    echo "3. Maintain TDD discipline:"
    echo "   - Write tests FIRST (Red phase)"
    echo "   - Implement minimal code (Green phase)"
    echo "   - Refactor while green"
    echo ""
    
    echo "4. Feature coverage:"
    echo "   - Run: ./_dev-tools/scripts/feature-audit.sh"
    echo "   - Ensure all Gherkin scenarios have tests"
    echo ""
    
    if [[ $FAIL_ON_WARN == true && ($uncovered_count -gt 0 || $low_coverage_count -gt 0) ]]; then
        echo -e "${RED}5. CRITICAL: Coverage below threshold - fixes required${NC}"
    else
        echo -e "${GREEN}5. Coverage goals met or above threshold${NC}"
    fi
}

# Generate HTML report summary
generate_html_summary() {
    if [[ $GENERATE_HTML == true ]]; then
        local html_path="$CODE_ROOT/target/llvm-cov/html/index.html"
        if [[ -f "$html_path" ]]; then
            echo ""
            echo -e "${GREEN}HTML report generated:${NC}"
            echo "  File: $html_path"
            echo "  Open with: xdg-open $html_path (Linux)"
            echo "           open $html_path (macOS)"
        fi
    fi
}

# Main execution
main() {
    check_dependencies
    
    echo "Configuration:"
    echo "  Minimum coverage: ${MIN_COVERAGE}%"
    echo "  Target crate: ${SPECIFIC_CRATE:-"all"}"
    echo "  Report types: $([ $GENERATE_HTML == true ] && echo "HTML ")$([ $GENERATE_JSON == true ] && echo "JSON ")$([ $CHECK_ONLY == true ] && echo "check-only" || echo "text")"
    echo ""
    
    # Run coverage analysis
    run_coverage
    
    # Extract main coverage percentage
    local total_coverage=$(extract_coverage)
    
    echo -e "${BLUE}=== Coverage Results ===${NC}"
    echo ""
    echo "Total coverage: ${total_coverage}%"
    echo "Target: ${MIN_COVERAGE}%"
    
    # Determine pass/fail
    if (( $(echo "$total_coverage >= $MIN_COVERAGE" | bc -l) )); then
        echo -e "${GREEN}✓ COVERAGE TARGET MET${NC}"
        COVERAGE_PASSED=true
    else
        echo -e "${RED}✗ COVERAGE TARGET MISSED${NC}"
        COVERAGE_PASSED=false
    fi
    
    # Analyze gaps
    local gap_counts=($(analyze_coverage_gaps))
    local uncovered_count="${gap_counts[-2]}"
    local low_coverage_count="${gap_counts[-1]}"
    
    # Generate recommendations
    generate_recommendations "$uncovered_count" "$low_coverage_count"
    
    # Generate report summary
    generate_html_summary
    
    # Final status
    echo ""
    echo -e "${CYAN}=== Summary ===${NC}"
    echo "Coverage: ${total_coverage}% (target: ${MIN_COVERAGE}%)"
    echo "Uncovered files: $uncovered_count"
    echo "Low coverage files: $low_coverage_count"
    
    if [[ $COVERAGE_PASSED == true && $uncovered_count -eq 0 ]]; then
        echo -e "${GREEN}Status: PASSED${NC}"
        exit 0
    elif [[ $COVERAGE_PASSED == true && $FAIL_ON_WARN != true ]]; then
        echo -e "${YELLOW}Status: PASSED (with warnings)${NC}"
        exit 0
    else
        echo -e "${RED}Status: FAILED${NC}"
        exit 1
    fi
}

main "$@"