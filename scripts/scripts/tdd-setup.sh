#!/bin/bash
# TDD Setup Script
# 
# Configures the workspace for strict Test-Driven Development
# following the Red-Green-Refactor methodology.
#
# Usage: ./tdd-setup.sh [options]
# Options:
#   --strict    Enable strict TDD mode (fail commits without tests)
#   --coverage  Enable coverage verification (90% minimum)
#   --hooks      Install git hooks only
#   --check     Run TDD verification checks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CODE_ROOT="$WORKSPACE_ROOT/core"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
STRICT_TDD=false
COVERAGE_CHECK=false
INSTALL_HOOKS=false
RUN_CHECKS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --strict)
            STRICT_TDD=true
            shift
            ;;
        --coverage)
            COVERAGE_CHECK=true
            shift
            ;;
        --hooks)
            INSTALL_HOOKS=true
            shift
            ;;
        --check)
            RUN_CHECKS=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --strict    Enable strict TDD mode"
            echo "  --coverage  Enable coverage verification"
            echo "  --hooks     Install git hooks only"
            echo "  --check     Run TDD verification checks"
            echo "  --help      Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        TDD Setup Script                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    print_status "Checking dependencies..."
    
    local missing=()
    
    if ! command -v cargo &> /dev/null; then
        missing+=("cargo")
    fi
    
    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi
    
    if [[ $COVERAGE_CHECK == true ]] && ! command -v cargo-llvm-cov &> /dev/null; then
        missing+=("cargo-llvm-cov")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install missing tools:"
        for tool in "${missing[@]}"; do
            case $tool in
                "cargo-llvm-cov")
                    echo "  cargo install cargo-llvm-cov"
                    ;;
                *)
                    echo "  (install $tool)"
                    ;;
            esac
        done
        exit 1
    fi
    
    print_success "All dependencies found"
}

# Install enhanced git hooks
install_git_hooks() {
    print_status "Installing enhanced git hooks..."
    
    local hooks_dir="$WORKSPACE_ROOT/_dev-tools/hooks"
    local git_hooks_dir="$WORKSPACE_ROOT/.git/hooks"
    
    # Create enhanced pre-commit hook
    cat > "$hooks_dir/pre-commit-tdd" << 'EOF'
#!/bin/bash
# Enhanced TDD Pre-commit Hook
# Enforces strict test-first development

set -e

echo "=== TDD Pre-commit Checks ==="

# Get staged Rust files
STAGED_RS=$(git diff --cached --name-only --diff-filter=ACM | grep '\.rs$' || true)
STAGED_FEATURES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.feature$' || true)

# Check if we're modifying production code
STAGED_PROD=$(echo "$STAGED_RS" | grep -E '^.*/src/.*\.rs$' || true)

if [[ -n "$STAGED_PROD" ]]; then
    echo "[TDD] Production code changes detected"
    
    # Check if corresponding tests exist or are staged
    TESTS_REQUIRED=""
    for prod_file in $STAGED_PROD; do
        # Convert src/path/file.rs to tests/path/file_tests.rs
        test_file=$(echo "$prod_file" | sed 's|/src/|/tests/|' | sed 's|\.rs$|_tests.rs|')
        
        if [[ ! -f "$test_file" ]] && ! echo "$STAGED_RS" | grep -q "$test_file"; then
            TESTS_REQUIRED="$TESTS_REQUIRED $test_file"
        fi
    done
    
    if [[ -n "$TESTS_REQUIRED" ]]; then
        echo ""
        echo "VIOLATION: Production code changes without corresponding tests"
        echo "Missing test files:$TESTS_REQUIRED"
        echo ""
        echo "TDD Rule: Write failing tests FIRST, then implement code"
        echo "Options:"
        echo "  1. Stage the missing test files: git add <test_files>"
        echo "  2. Write tests for your changes"
        echo "  3. Bypass with: git commit --no-verify (not recommended)"
        exit 1
    fi
    
    echo "  Tests exist for production changes"
fi

# Check if we're adding new features without tests
if [[ -n "$STAGED_FEATURES" ]]; then
    echo "[TDD] Feature files added/modified"
    
    for feature_file in $STAGED_FEATURES; do
        # Extract feature name
        feature_name=$(basename "$feature_file" .feature)
        
        # Check if we have corresponding test coverage
        if ! find code -name "*${feature_name}*" -name "*.rs" | grep -q test; then
            echo ""
            echo "WARNING: Feature $feature_name added but no tests found"
            echo "Consider adding tests to cover the new scenarios"
        fi
    done
fi

echo "  TDD checks passed"
EOF

    # Create enhanced pre-push hook for coverage
    if [[ $COVERAGE_CHECK == true ]]; then
        cat > "$hooks_dir/pre-push-coverage" << 'EOF'
#!/bin/bash
# Coverage verification pre-push hook

set -e

echo "=== Coverage Check ==="

# Run coverage if cargo-llvm-cov is available
if command -v cargo-llvm-cov &> /dev/null; then
    cd code
    
    # Generate coverage report
    cargo llvm-cov --workspace --html --output-path target/llvm-cov/html 2>/dev/null
    
    # Extract coverage percentage
    COVERAGE=$(cargo llvm-cov --workspace --text 2>/dev/null | grep -E '^\s*[0-9]+\.[0-9]+%' | tail -1 | grep -oE '[0-9]+\.[0-9]+' || echo "0")
    
    cd - > /dev/null
    
    # Check minimum coverage (90%)
    MIN_COVERAGE=90
    if (( $(echo "$COVERAGE < $MIN_COVERAGE" | bc -l) )); then
        echo ""
        echo "COVERAGE VIOLATION: ${COVERAGE}% < ${MIN_COVERAGE}%"
        echo "Add more tests before pushing"
        echo "View report: code/target/llvm-cov/html/index.html"
        exit 1
    fi
    
    echo "  Coverage: ${COVERAGE}% (minimum: ${MIN_COVERAGE}%)"
else
    echo "  (cargo-llvm-cov not available, skipping coverage check)"
fi

echo "  Coverage check passed"
EOF
        chmod +x "$hooks_dir/pre-push-coverage"
    fi
    
    chmod +x "$hooks_dir/pre-commit-tdd"
    
    # Install hooks
    cp "$hooks_dir/pre-commit-tdd" "$git_hooks_dir/pre-commit"
    cp "$hooks_dir/pre-push-coverage" "$git_hooks_dir/pre-push" 2>/dev/null || true
    
    print_success "Git hooks installed"
}

# Create TDD workflow helper scripts
create_workflow_scripts() {
    print_status "Creating TDD workflow scripts..."
    
    # Create Red-Green-Refactor helper
    cat > "$WORKSPACE_ROOT/_dev-tools/scripts/tdd-red.sh" << 'EOF'
#!/bin/bash
# TDD Red Phase - Write failing test
# Usage: ./tdd-red.sh <test_name> <description>

set -e

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <test_name> <description>"
    echo "Example: $0 test_encrypt_valid_key \"Encryption should work with valid key\""
    exit 1
fi

TEST_NAME="$1"
DESCRIPTION="$2"

echo "=== TDD RED PHASE ==="
echo "Test: $TEST_NAME"
echo "Description: $DESCRIPTION"
echo ""

# Find appropriate test file based on current directory
CURRENT_DIR=$(pwd)
if [[ "$CURRENT_DIR" =~ .*/src/.* ]]; then
    # We're in src/, find corresponding test file
    TEST_FILE=$(echo "$CURRENT_DIR" | sed 's|/src/|/tests/|')/$(basename "$CURRENT_DIR")_tests.rs
else
    # Default to core tests
    TEST_FILE="code/vauchi-core/tests/$(basename "$CURRENT_DIR")_tests.rs"
fi

# Create test file if it doesn't exist
mkdir -p "$(dirname "$TEST_FILE")"
if [[ ! -f "$TEST_FILE" ]]; then
    cat > "$TEST_FILE" << 'TEST_EOF'
//! Tests for $(basename $(dirname "$TEST_FILE"))

use vauchi_core::prelude::*;

TEST_EOF
fi

# Add the failing test
cat >> "$TEST_FILE" << TEST_EOF

#[test]
fn $TEST_NAME() {
    // RED: This test should fail initially
    // TODO: Implement test for: $DESCRIPTION
    
    // Arrange
    // TODO: Set up test data
    
    // Act
    // TODO: Call function under test
    
    // Assert
    // TODO: Verify expected behavior
    unimplemented!("Test not yet implemented: $DESCRIPTION");
}
TEST_EOF

echo "Created failing test in: $TEST_FILE"
echo ""
echo "Next steps:"
echo "1. Run: cargo test -p vauchi-core $TEST_NAME"
echo "2. Confirm test fails (RED)"
echo "3. Implement minimal code to pass"
echo "4. Run: ./_dev-tools/scripts/tdd-green.sh $TEST_NAME"
EOF

    # Create Green phase helper
    cat > "$WORKSPACE_ROOT/_dev-tools/scripts/tdd-green.sh" << 'EOF'
#!/bin/bash
# TDD Green Phase - Make test pass
# Usage: ./tdd-green.sh <test_name>

set -e

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <test_name>"
    echo "Example: $0 test_encrypt_valid_key"
    exit 1
fi

TEST_NAME="$1"

echo "=== TDD GREEN PHASE ==="
echo "Making test pass: $TEST_NAME"
echo ""

# Run the specific test
cd code
cargo test -p vauchi-core "$TEST_NAME"

echo ""
echo "GREEN phase complete!"
echo "Next steps:"
echo "1. If test passes: ./_dev-tools/scripts/tdd-refactor.sh $TEST_NAME"
echo "2. If test fails: Implement minimal code to make it pass"
echo "3. Repeat until test passes"
EOF

    # Create Refactor phase helper
    cat > "$WORKSPACE_ROOT/_dev-tools/scripts/tdd-refactor.sh" << 'EOF'
#!/bin/bash
# TDD Refactor Phase - Improve code while keeping tests green
# Usage: ./tdd-refactor.sh <test_name>

set -e

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <test_name>"
    echo "Example: $0 test_encrypt_valid_key"
    exit 1
fi

TEST_NAME="$1"

echo "=== TDD REFACTOR PHASE ==="
echo "Refactoring with test: $TEST_NAME"
echo ""

# Run all tests to ensure we don't break anything
cd code
cargo test -p vauchi-core

echo ""
echo "REFACTOR phase complete!"
echo "Next steps:"
echo "1. Review code for improvements"
echo "2. Run tests again to ensure they still pass"
echo "3. Commit when satisfied"
echo "4. Start next RED phase"
EOF

    # Make scripts executable
    chmod +x "$WORKSPACE_ROOT/_dev-tools/scripts/tdd-red.sh"
    chmod +x "$WORKSPACE_ROOT/_dev-tools/scripts/tdd-green.sh"
    chmod +x "$WORKSPACE_ROOT/_dev-tools/scripts/tdd-refactor.sh"
    
    print_success "TDD workflow scripts created"
}

# Create TDD verification script
create_verification_script() {
    print_status "Creating TDD verification script..."
    
    cat > "$WORKSPACE_ROOT/_dev-tools/scripts/tdd-verify.sh" << 'EOF'
#!/bin/bash
# TDD Verification Script
# Verifies TDD compliance across the codebase

set -e

echo "=== TDD Verification ==="

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODE_ROOT="$WORKSPACE_ROOT/core"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VIOLATIONS=0

# 1. Check for production code without tests
echo "[1/4] Checking production code coverage..."

for crate_dir in "$CODE_ROOT"/*/; do
    if [[ -d "$crate_dir/src" ]]; then
        crate_name=$(basename "$crate_dir")
        src_files=$(find "$crate_dir/src" -name "*.rs" -not -path "*/target/*")
        
        for src_file in $src_files; do
            # Skip main.rs and lib.rs for now (focus on modules)
            if [[ "$(basename "$src_file")" =~ ^(main|lib)\.rs$ ]]; then
                continue
            fi
            
            # Look for corresponding test file
            rel_path=${src_file#$crate_dir/src/}
            test_file="$crate_dir/tests/${rel_path%.rs}_tests.rs"
            
            if [[ ! -f "$test_file" ]]; then
                echo -e "  ${RED}MISSING TEST${NC}: $src_file"
                VIOLATIONS=$((VIOLATIONS + 1))
            fi
        done
    fi
done

# 2. Check for inline tests without justification
echo "[2/4] Checking inline test justification..."

for crate_dir in "$CODE_ROOT"/*/; do
    src_files=$(find "$crate_dir/src" -name "*.rs" -not -path "*/target/*")
    
    for src_file in $src_files; do
        if grep -q '#\[cfg(test)\]' "$src_file"; then
            if ! grep -B5 '#\[cfg(test)\]' "$src_file" | grep -q 'INLINE_TEST_REQUIRED:'; then
                echo -e "  ${RED}INLINE TEST${NC}: $src_file (needs INLINE_TEST_REQUIRED marker)"
                VIOLATIONS=$((VIOLATIONS + 1))
            fi
        fi
    done
done

# 3. Check feature-to-test mapping
echo "[3/4] Checking feature coverage..."

FEATURES_DIR="$WORKSPACE_ROOT/features"
if [[ -d "$FEATURES_DIR" ]]; then
    for feature_file in "$FEATURES_DIR"/*.feature; do
        if [[ -f "$feature_file" ]]; then
            feature_name=$(basename "$feature_file" .feature)
            
            # Look for tests related to this feature
            feature_tests=$(find "$CODE_ROOT" -name "*${feature_name}*" -name "*.rs" | wc -l)
            
            if [[ $feature_tests -eq 0 ]]; then
                echo -e "  ${YELLOW}UNTESTED FEATURE${NC}: $feature_name"
            fi
        fi
    done
fi

# 4. Check test quality (basic metrics)
echo "[4/4] Checking test quality..."

total_tests=0
passing_tests=0

for crate_dir in "$CODE_ROOT"/*/; do
    if [[ -d "$crate_dir/tests" || -d "$crate_dir/src" ]]; then
        cd "$crate_dir"
        
        # Count tests
        test_count=$(find . -name "*.rs" -exec grep -l '#\[test\]' {} \; 2>/dev/null | wc -l)
        total_tests=$((total_tests + test_count))
        
        cd - > /dev/null
    fi
done

echo ""
echo "=== Results ==="
echo "Total violations: $VIOLATIONS"
echo "Total test files: $total_tests"

if [[ $VIOLATIONS -eq 0 ]]; then
    echo -e "${GREEN}✓ TDD compliance verified${NC}"
    exit 0
else
    echo -e "${RED}✗ TDD violations found${NC}"
    echo ""
    echo "Fix violations and run again"
    exit 1
fi
EOF

    chmod +x "$WORKSPACE_ROOT/_dev-tools/scripts/tdd-verify.sh"
    
    print_success "TDD verification script created"
}

# Main execution
main() {
    cd "$WORKSPACE_ROOT"
    
    if [[ $INSTALL_HOOKS == true || $STRICT_TDD == true ]]; then
        check_dependencies
        install_git_hooks
        create_workflow_scripts
        create_verification_script
        
        if [[ $STRICT_TDD == true ]]; then
            print_success "Strict TDD mode enabled"
            echo ""
            echo "TDD Rules now enforced:"
            echo "  ✓ Production code requires corresponding tests"
            echo "  ✓ Inline tests need justification markers"
            echo "  ✓ Feature files need test coverage"
            if [[ $COVERAGE_CHECK == true ]]; then
                echo "  ✓ 90% minimum coverage on push"
            fi
            echo ""
            echo "Workflow helpers available:"
            echo "  ./_dev-tools/scripts/tdd-red.sh    # Write failing test"
            echo "  ./_dev-tools/scripts/tdd-green.sh  # Make test pass"
            echo "  ./_dev-tools/scripts/tdd-refactor.sh # Refactor code"
            echo "  ./_dev-tools/scripts/tdd-verify.sh  # Check compliance"
        fi
    fi
    
    if [[ $RUN_CHECKS == true ]]; then
        "$WORKSPACE_ROOT/_dev-tools/scripts/tdd-verify.sh"
    fi
    
    if [[ $INSTALL_HOOKS == false && $STRICT_TDD == false && $RUN_CHECKS == false ]]; then
        echo "No action specified. Use --help for options."
        echo ""
        echo "Quick setup:"
        echo "  $0 --strict --coverage    # Enable full TDD mode"
        echo "  $0 --hooks                 # Install hooks only"
        echo "  $0 --check                 # Run verification"
    fi
}

main "$@"