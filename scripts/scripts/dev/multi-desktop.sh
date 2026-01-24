#!/bin/bash
# Multi-Instance Desktop Testing
#
# Launches Tauri desktop instances with isolated data directories.
# Note: On macOS, you may need to use different bundle identifiers or
# override the app data path via environment variables.

set -e

# Source common variables
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Use project-local tmp for test data
TEST_DATA_BASE="${VAUCHI_TEST_DATA:-$TEST_DATA_DIR}"

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  <instance>   Launch Desktop app with isolated data"
    echo "  clean        Clean all test data before starting fresh"
    echo "  list         List existing test instances"
    echo ""
    echo "Instance data stored at: ${TEST_DATA_BASE}/<instance-name>"
    echo ""
    echo "Note: Desktop apps may have single-instance restrictions on macOS."
    echo "For multi-instance testing, consider:"
    echo "  1. Running one instance in dev mode, another as built app"
    echo "  2. Using different user accounts"
    echo "  3. Testing Desktop + CLI/TUI combinations"
    echo ""
    echo "Examples:"
    echo "  Terminal 1: ./scripts/dev/local-relay.sh"
    echo "  Terminal 2: $0 alice"
    echo "  Terminal 3: ./scripts/dev/multi-cli.sh bob ..."
    echo ""
    echo "Environment Variables:"
    echo "  VAUCHI_TEST_DATA    Base directory for test data (default: $TEST_DATA_DIR)"
    exit 1
}

# Ensure directories exist
ensure_dirs

if [ -z "$1" ]; then
    usage
fi

# Handle special commands
case "$1" in
    clean)
        echo "Cleaning test data directory: $TEST_DATA_BASE"
        rm -rf "$TEST_DATA_BASE"/*
        echo "Done."
        exit 0
        ;;
    list)
        echo "Test instances in $TEST_DATA_BASE:"
        if [ -d "$TEST_DATA_BASE" ]; then
            ls -1 "$TEST_DATA_BASE" 2>/dev/null || echo "  (none)"
        else
            echo "  (none)"
        fi
        exit 0
        ;;
    -h|--help|help)
        usage
        ;;
esac

INSTANCE_NAME="$1"
DATA_DIR="${TEST_DATA_BASE}/${INSTANCE_NAME}"
mkdir -p "$DATA_DIR"

echo "=== Vauchi Desktop: ${INSTANCE_NAME} ==="
echo "Data: ${DATA_DIR}"
echo ""
echo "Note: Set the data directory in the app's settings or via environment."
echo ""

cd "$CODE_DIR/vauchi-desktop"

# Set custom data directory via environment
# The Tauri app should respect this environment variable
export VAUCHI_DATA_DIR="$DATA_DIR"

# Run in development mode
cargo tauri dev
