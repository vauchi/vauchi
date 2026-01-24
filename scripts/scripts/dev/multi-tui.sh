#!/bin/bash
# Multi-Instance TUI Testing
#
# Launches TUI instances with isolated data directories.
# Run each instance in a separate terminal window.

set -e

# Source common variables
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Use project-local tmp for test data
TEST_DATA_BASE="${VAUCHI_TEST_DATA:-$TEST_DATA_DIR}"

# Default relay (local)
RELAY="${VAUCHI_RELAY_URL:-ws://127.0.0.1:8080}"

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  <instance>   Launch TUI with isolated data"
    echo "  clean        Clean all test data before starting fresh"
    echo "  list         List existing test instances"
    echo ""
    echo "Instance data stored at: ${TEST_DATA_BASE}/<instance-name>"
    echo ""
    echo "Examples (run each in separate terminal):"
    echo "  Terminal 1: ./scripts/dev/local-relay.sh"
    echo "  Terminal 2: $0 alice"
    echo "  Terminal 3: $0 bob"
    echo ""
    echo "Environment Variables:"
    echo "  VAUCHI_RELAY_URL    Relay server URL (default: ws://127.0.0.1:8080)"
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

echo "=== Vauchi TUI: ${INSTANCE_NAME} ==="
echo "Data: ${DATA_DIR}"
echo "Relay: ${RELAY}"
echo ""

cd "$CODE_DIR"
VAUCHI_DATA_DIR="$DATA_DIR" VAUCHI_RELAY_URL="$RELAY" cargo run -p vauchi-tui
