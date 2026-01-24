#!/bin/bash
# Local Relay Server for Manual Testing
#
# Runs the Vauchi relay server locally for testing sync between devices.
# This allows all local instances to communicate without using the production relay.

set -e

# Source common variables (sets CODE_DIR, PROJECT_ROOT, etc.)
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Default port and host
PORT="${VAUCHI_RELAY_PORT:-8080}"
HOST="${VAUCHI_RELAY_HOST:-127.0.0.1}"

echo "=== Vauchi Local Relay Server ==="
echo ""
echo "Starting relay server at ws://${HOST}:${PORT}"
echo "Use this URL in your test instances:"
echo "  CLI:     vauchi --relay ws://${HOST}:${PORT} ..."
echo "  TUI:     VAUCHI_RELAY_URL=ws://${HOST}:${PORT} cargo run -p vauchi-tui"
echo "  Desktop: Set relay URL in settings"
echo ""
echo "Press Ctrl+C to stop"
echo ""

cd "$CODE_DIR"
# Relay uses environment variables for configuration
export RELAY_LISTEN_ADDR="${HOST}:${PORT}"
export RELAY_STORAGE_BACKEND="memory"  # Use memory storage for local testing
RUST_LOG=info cargo run -p vauchi-relay
