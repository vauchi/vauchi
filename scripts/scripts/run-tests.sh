#!/bin/bash
# Run tests across Vauchi repositories
# Supports running tests for code, android, and ios repos

set -e

# Configuration
WORKSPACE="${WORKSPACE:-$(pwd)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
header() { echo -e "${BLUE}=== $1 ===${NC}"; }

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [TARGET]

Run tests across Vauchi repositories.

Targets:
    code        Run Rust tests (cargo test)
    android     Run Android tests (gradle test)
    ios         Run iOS tests (xcodebuild test)
    all         Run all tests (default)

Options:
    -w, --workspace DIR    Workspace directory (default: current directory)
    -v, --verbose          Verbose output
    -h, --help             Show this help message

Examples:
    $(basename "$0")                    # Run all tests
    $(basename "$0") code               # Run only Rust tests
    $(basename "$0") code -v            # Verbose Rust tests
EOF
}

test_code() {
    local verbose=$1
    local code_dir="$WORKSPACE/code"

    if [[ ! -d "$code_dir" ]]; then
        warn "Code directory not found, skipping"
        return 1
    fi

    header "Rust Tests (code/)"
    cd "$code_dir"

    local flags=""
    [[ "$verbose" == "true" ]] && flags="-- --nocapture"

    cargo test --workspace $flags

    info "Rust tests passed!"
}

test_android() {
    local android_dir="$WORKSPACE/android"

    if [[ ! -d "$android_dir" ]]; then
        warn "Android directory not found, skipping"
        return 1
    fi

    header "Android Tests (android/)"
    cd "$android_dir"

    if [[ -f "gradlew" ]]; then
        ./gradlew test
    else
        warn "gradlew not found, skipping Android tests"
        return 1
    fi

    info "Android tests passed!"
}

test_ios() {
    local ios_dir="$WORKSPACE/ios"

    if [[ ! -d "$ios_dir" ]]; then
        warn "iOS directory not found, skipping"
        return 1
    fi

    # Check if on macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        warn "iOS tests require macOS, skipping"
        return 1
    fi

    header "iOS Tests (ios/)"
    cd "$ios_dir"

    xcodebuild test \
        -scheme Vauchi \
        -destination 'platform=iOS Simulator,name=iPhone 16' \
        -quiet

    info "iOS tests passed!"
}

# Parse arguments
TARGET="all"
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        code|android|ios|all)
            TARGET="$1"
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run tests
FAILED=0

case $TARGET in
    code)
        test_code "$VERBOSE" || FAILED=1
        ;;
    android)
        test_android || FAILED=1
        ;;
    ios)
        test_ios || FAILED=1
        ;;
    all)
        test_code "$VERBOSE" || FAILED=1
        test_android || FAILED=1
        test_ios || FAILED=1
        ;;
esac

if [[ $FAILED -eq 0 ]]; then
    info "All tests passed!"
else
    error "Some tests failed"
    exit 1
fi
