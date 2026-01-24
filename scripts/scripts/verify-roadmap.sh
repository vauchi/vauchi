#!/usr/bin/env bash
# verify-roadmap.sh - Verify roadmap claims against actual project state
# Run this before marking anything "done" in the roadmap

set -uo pipefail
# Note: not using -e because check functions use eval and we handle failures manually

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check() {
    local name="$1"
    local condition="$2"
    local fix_hint="${3:-}"

    if eval "$condition" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}✗${NC} $name"
        [ -n "$fix_hint" ] && echo -e "  ${YELLOW}Fix:${NC} $fix_hint"
        FAIL=$((FAIL + 1))
    fi
}

warn_check() {
    local name="$1"
    local condition="$2"
    local note="${3:-}"

    if eval "$condition" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name"
        PASS=$((PASS + 1))
    else
        echo -e "${YELLOW}⚠${NC} $name"
        [ -n "$note" ] && echo -e "  ${YELLOW}Note:${NC} $note"
        WARN=$((WARN + 1))
    fi
}

count_pattern() {
    local pattern="$1"
    local path="$2"
    grep -r "$pattern" "$path" --include="*.rs" 2>/dev/null | wc -l | tr -d ' '
}

# Count production unwraps (excluding tests, doc comments, and mutex locks)
count_production_unwraps() {
    local path="$1"
    local count=0

    for file in $(find "$path" -name "*.rs" -type f 2>/dev/null); do
        # Get line where test module starts
        local test_start=$(grep -n "^#\[cfg(test)\]" "$file" 2>/dev/null | head -1 | cut -d: -f1)

        local content
        if [ -n "$test_start" ]; then
            content=$(head -n "$((test_start - 1))" "$file" 2>/dev/null)
        else
            content=$(cat "$file" 2>/dev/null)
        fi

        # Count unwraps excluding:
        # - Doc comments (//! or ///)
        # - Regular comments (//)
        # - Mutex locks (.lock().unwrap())
        local file_count=$(echo "$content" | \
            grep "\.unwrap()" | \
            grep -v "^\s*//" | \
            grep -v "\.lock()\.unwrap()" | \
            wc -l)

        count=$((count + file_count))
    done

    echo "$count"
}

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║      Roadmap Verification Report       ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
echo "=== Build & Tests ==="
# ============================================================

check "Rust workspace builds" \
    "cd $ROOT_DIR/code && cargo build --workspace 2>/dev/null"

check "All Rust tests pass" \
    "cd $ROOT_DIR/code && cargo test --workspace 2>/dev/null"

check "Clippy clean (no warnings)" \
    "cd $ROOT_DIR/code && cargo clippy --workspace -- -D warnings 2>/dev/null"

check "Code formatted" \
    "cd $ROOT_DIR/code && cargo fmt --all -- --check 2>/dev/null"

echo ""

# ============================================================
echo "=== Unwrap Cleanup (Claimed: Critical paths fixed) ==="
# ============================================================

# Use accurate counting (excludes test code, doc comments, mutex locks)
CRYPTO_UNWRAPS=$(count_production_unwraps "$ROOT_DIR/code/vauchi-core/src/crypto")
API_UNWRAPS=$(count_production_unwraps "$ROOT_DIR/code/vauchi-core/src/api")
CORE_UNWRAPS=$(count_production_unwraps "$ROOT_DIR/code/vauchi-core/src")

check "Zero production unwraps in crypto/ (found: $CRYPTO_UNWRAPS)" \
    "[ $CRYPTO_UNWRAPS -eq 0 ]" \
    "rg '\\.unwrap\\(\\)' code/vauchi-core/src/crypto/ (excluding tests)"

check "Zero production unwraps in api/ (found: $API_UNWRAPS)" \
    "[ $API_UNWRAPS -eq 0 ]" \
    "rg '\\.unwrap\\(\\)' code/vauchi-core/src/api/ (excluding tests/docs)"

warn_check "Core production unwraps under 20 (found: $CORE_UNWRAPS)" \
    "[ $CORE_UNWRAPS -lt 20 ]" \
    "Excludes tests, doc comments, and mutex locks"

echo ""

# ============================================================
echo "=== Recovery Feature (Claimed: Done on iOS + Android) ==="
# ============================================================

# Check if recovery tests exist and reference actual FFI
IOS_RECOVERY_TESTS=$(grep -r "recovery\|Recovery" "$ROOT_DIR/ios/VauchiTests/" --include="*.swift" 2>/dev/null | wc -l | tr -d ' ')
ANDROID_RECOVERY_TESTS=$(grep -r "recovery\|Recovery" "$ROOT_DIR/android/app/src/test/" --include="*.kt" 2>/dev/null | wc -l | tr -d ' ')

check "iOS has recovery tests (found: $IOS_RECOVERY_TESTS references)" \
    "[ $IOS_RECOVERY_TESTS -gt 5 ]" \
    "Add tests to ios/VauchiTests/VauchiRepositoryTests.swift"

check "Android has recovery tests (found: $ANDROID_RECOVERY_TESTS references)" \
    "[ $ANDROID_RECOVERY_TESTS -gt 5 ]" \
    "Add tests to android/app/src/test/"

# Check Rust recovery tests
RUST_RECOVERY_TESTS=$(grep -r "recovery\|Recovery" "$ROOT_DIR/code/vauchi-core/tests/" --include="*.rs" 2>/dev/null | wc -l | tr -d ' ')
check "Rust has recovery integration tests (found: $RUST_RECOVERY_TESTS references)" \
    "[ $RUST_RECOVERY_TESTS -gt 10 ]"

echo ""

# ============================================================
echo "=== Mobile Tests (Claimed: UNBLOCKED) ==="
# ============================================================

IOS_TEST_COUNT=$(find "$ROOT_DIR/ios" -name "*Test*.swift" 2>/dev/null | wc -l | tr -d ' ')
ANDROID_TEST_COUNT=$(find "$ROOT_DIR/android" -name "*Test*.kt" 2>/dev/null | wc -l | tr -d ' ')

warn_check "iOS test files >= 10 (found: $IOS_TEST_COUNT)" \
    "[ $IOS_TEST_COUNT -ge 10 ]" \
    "Target: 10+ test files for adequate coverage"

warn_check "Android test files >= 10 (found: $ANDROID_TEST_COUNT)" \
    "[ $ANDROID_TEST_COUNT -ge 10 ]" \
    "Target: 10+ test files for adequate coverage"

echo ""

# ============================================================
echo "=== Coverage (Mandatory: 90% for vauchi-core) ==="
# ============================================================

# Check if coverage can actually be measured
if command -v cargo-llvm-cov &>/dev/null || cargo llvm-cov --version &>/dev/null 2>&1; then
    warn_check "Coverage tooling installed" "true"
else
    check "Coverage tooling installed (cargo-llvm-cov)" \
        "false" \
        "cargo install cargo-llvm-cov"
fi

# Check for coverage artifacts
COVERAGE_FILES=$(find "$ROOT_DIR" -name "*.profraw" -o -name "lcov.info" -o -name "coverage.json" 2>/dev/null | wc -l | tr -d ' ')
warn_check "Coverage artifacts exist (found: $COVERAGE_FILES)" \
    "[ $COVERAGE_FILES -gt 0 ]" \
    "Run: just coverage"

echo ""

# ============================================================
echo "=== Feature Coverage (from feature-audit) ==="
# ============================================================

# Check critical features have some test coverage
VISIBILITY_TESTS=$(grep -r "visibility\|Visibility" "$ROOT_DIR/code/vauchi-core/tests/" --include="*.rs" 2>/dev/null | wc -l | tr -d ' ')
EXCHANGE_TESTS=$(grep -r "exchange\|Exchange" "$ROOT_DIR/code/vauchi-core/tests/" --include="*.rs" 2>/dev/null | wc -l | tr -d ' ')
SYNC_TESTS=$(grep -r "sync\|Sync" "$ROOT_DIR/code/vauchi-core/tests/" --include="*.rs" 2>/dev/null | wc -l | tr -d ' ')

warn_check "Visibility feature has tests (found: $VISIBILITY_TESTS)" \
    "[ $VISIBILITY_TESTS -gt 20 ]" \
    "visibility_labels.feature has 41 scenarios"

warn_check "Exchange feature has tests (found: $EXCHANGE_TESTS)" \
    "[ $EXCHANGE_TESTS -gt 20 ]" \
    "contact_exchange.feature has 27 scenarios"

warn_check "Sync feature has tests (found: $SYNC_TESTS)" \
    "[ $SYNC_TESTS -gt 20 ]" \
    "sync_updates.feature has 34 scenarios"

echo ""

# ============================================================
echo "=== Git State ==="
# ============================================================

UNCOMMITTED=$(cd "$ROOT_DIR/code" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
warn_check "No uncommitted changes in code/ (found: $UNCOMMITTED)" \
    "[ $UNCOMMITTED -eq 0 ]" \
    "Commit or stash changes before claiming done"

echo ""

# ============================================================
# Summary
# ============================================================
echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║              Summary                   ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Passed:${NC}   $PASS"
echo -e "  ${RED}Failed:${NC}   $FAIL"
echo -e "  ${YELLOW}Warnings:${NC} $WARN"
echo ""

if [ $FAIL -gt 0 ]; then
    echo -e "${RED}VERIFICATION FAILED${NC}"
    echo ""
    echo "Claims in roadmap do not match project state."
    echo "Either fix the issues or update the roadmap to reflect reality."
    exit 1
elif [ $WARN -gt 3 ]; then
    echo -e "${YELLOW}VERIFICATION PASSED WITH WARNINGS${NC}"
    echo ""
    echo "Roadmap claims are mostly accurate but some areas need attention."
    exit 0
else
    echo -e "${GREEN}VERIFICATION PASSED${NC}"
    exit 0
fi
