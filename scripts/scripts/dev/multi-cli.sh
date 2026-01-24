#!/bin/bash
# Multi-Instance CLI Testing
#
# Launches multiple CLI instances with isolated data directories.
# Each instance acts as a separate "device" for testing exchanges and sync.

set -e

# Source common variables
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Use project-local tmp for test data
TEST_DATA_BASE="${VAUCHI_TEST_DATA:-$TEST_DATA_DIR}"

# Default relay (local)
RELAY="${VAUCHI_RELAY_URL:-ws://127.0.0.1:8080}"

usage() {
    echo "Usage: $0 <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  <instance> [cmd...]  Run CLI command for instance (creates isolated data)"
    echo "  clean                Clean all test data before starting fresh"
    echo "  list                 List existing test instances"
    echo ""
    echo "Instance data stored at: ${TEST_DATA_BASE}/<instance-name>"
    echo ""
    echo "Examples:"
    echo "  $0 alice init 'Alice Smith'     # Create Alice's identity"
    echo "  $0 bob init 'Bob Jones'         # Create Bob's identity"
    echo "  $0 alice exchange start         # Alice generates QR"
    echo "  $0 bob exchange complete <data> # Bob completes exchange"
    echo "  $0 alice sync                   # Alice syncs"
    echo "  $0 alice contacts list          # List Alice's contacts"
    echo "  $0 clean                        # Clean all test data"
    echo "  $0 list                         # List test instances"
    echo ""
    echo "Environment Variables:"
    echo "  VAUCHI_RELAY_URL    Relay server URL (default: ws://127.0.0.1:8080)"
    echo "  VAUCHI_TEST_DATA    Base directory for test data (default: $TEST_DATA_DIR)"
    echo ""
    echo "Quick Setup (run in separate terminals):"
    echo "  Terminal 1: ./scripts/dev/local-relay.sh"
    echo "  Terminal 2: $0 alice init 'Alice' && $0 alice exchange start"
    echo "  Terminal 3: $0 bob init 'Bob' && $0 bob exchange complete <alice-qr-data>"
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
shift

DATA_DIR="${TEST_DATA_BASE}/${INSTANCE_NAME}"
mkdir -p "$DATA_DIR"

echo "[${INSTANCE_NAME}] Data: ${DATA_DIR}"
echo "[${INSTANCE_NAME}] Relay: ${RELAY}"
echo ""

cd "$CODE_DIR"
cargo run -p vauchi-cli --quiet -- --data-dir "$DATA_DIR" --relay "$RELAY" "$@"
