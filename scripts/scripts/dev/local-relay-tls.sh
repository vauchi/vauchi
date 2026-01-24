#!/bin/bash
# Local Relay Server with TLS for Mobile Testing
#
# Runs the Vauchi relay server with Caddy TLS proxy for testing
# iOS/Android apps that require wss:// connections.
#
# Prerequisites:
#   - Caddy: https://caddyserver.com/docs/install
#   - mkcert: https://github.com/FiloSottile/mkcert
#   - Run once: mkcert -install (adds local CA to system trust store)
#
# Usage:
#   ./local-relay-tls.sh           # Start relay + TLS proxy
#   ./local-relay-tls.sh --setup   # Setup only (install mkcert CA)

set -e

# Source common variables
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/_common.sh"

# Configuration
RELAY_PORT="${VAUCHI_RELAY_PORT:-8080}"
TLS_PORT="${VAUCHI_RELAY_TLS_PORT:-8443}"
HOST="127.0.0.1"

# Check for prerequisites
check_prereqs() {
    local missing=""

    if ! command -v caddy &>/dev/null; then
        missing="${missing}caddy "
    fi

    if ! command -v mkcert &>/dev/null; then
        missing="${missing}mkcert "
    fi

    if [ -n "$missing" ]; then
        echo "Missing prerequisites: $missing"
        echo ""
        echo "Install instructions:"
        echo "  macOS:   brew install caddy mkcert"
        echo "  Linux:   See https://caddyserver.com/docs/install"
        echo "           See https://github.com/FiloSottile/mkcert#installation"
        exit 1
    fi
}

# Setup local CA
setup_ca() {
    echo "=== Setting up local CA with mkcert ==="
    mkcert -install
    echo ""
    echo "Local CA installed. Certificate location:"
    echo "  $(mkcert -CAROOT)"
    echo ""
    echo "For Android Emulator, you may need to install the CA:"
    echo "  adb push \"\$(mkcert -CAROOT)/rootCA.pem\" /sdcard/"
    echo "  Then: Settings > Security > Install from storage"
}

# Print connection info
print_info() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' || ipconfig getifaddr en0 2>/dev/null || echo "YOUR_IP")

    echo "=== Vauchi Local Relay Server (TLS) ==="
    echo ""
    echo "Relay running at:  ws://${HOST}:${RELAY_PORT} (internal)"
    echo "TLS proxy at:      wss://localhost:${TLS_PORT}"
    echo ""
    echo "Use these URLs in your test instances:"
    echo ""
    echo "  iOS Simulator:     wss://localhost:${TLS_PORT}"
    echo "  Android Emulator:  wss://10.0.2.2:${TLS_PORT}"
    echo "  Physical device:   wss://${ip}:${TLS_PORT}"
    echo ""
    echo "Note: Physical devices need the local CA installed."
    echo "      Run with --setup to configure the CA."
    echo ""
    echo "Press Ctrl+C to stop both servers"
    echo ""
}

# Main
main() {
    check_prereqs

    # Handle --setup flag
    if [ "${1:-}" = "--setup" ]; then
        setup_ca
        exit 0
    fi

    print_info

    # Start relay in background
    echo "[1/2] Starting relay server..."
    cd "$PROJECT_ROOT"
    export RELAY_LISTEN_ADDR="${HOST}:${RELAY_PORT}"
    export RELAY_STORAGE_BACKEND="memory"
    RUST_LOG=info cargo run -p vauchi-relay &
    RELAY_PID=$!

    # Wait for relay to start
    sleep 2

    # Start Caddy TLS proxy
    echo "[2/2] Starting TLS proxy..."
    caddy run --config "$PROJECT_ROOT/relay/deploy/caddy/Caddyfile.local" &
    CADDY_PID=$!

    # Cleanup on exit
    cleanup() {
        echo ""
        echo "Shutting down..."
        kill $CADDY_PID 2>/dev/null || true
        kill $RELAY_PID 2>/dev/null || true
        wait
        echo "Done."
    }
    trap cleanup EXIT

    # Wait for both processes
    wait
}

main "$@"
