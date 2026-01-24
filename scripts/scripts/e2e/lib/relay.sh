#!/bin/bash
# E2E Testing - Relay Functions
#
# Relay server management for E2E testing.
# Supports both production relay and local TLS relay.
#
# Prerequisites for local relay:
#   - Caddy: https://caddyserver.com/docs/install
#   - mkcert: https://github.com/FiloSottile/mkcert

# Source common utilities if not already loaded
if [ -z "$E2E_LIB_DIR" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# ═══════════════════════════════════════════════════════════════
# Relay URL Resolution
# ═══════════════════════════════════════════════════════════════

# Get the active relay URL based on configuration
relay_get_url() {
    if [ "${USE_LOCAL_RELAY:-false}" = "true" ]; then
        echo "wss://localhost:${LOCAL_RELAY_TLS_PORT:-8443}"
    else
        echo "${RELAY_URL:-wss://relay.vauchi.app}"
    fi
}

# Get relay URL for Android emulator (special handling for localhost)
relay_get_url_android() {
    if [ "${USE_LOCAL_RELAY:-false}" = "true" ]; then
        # Android emulator uses 10.0.2.2 for host machine
        echo "wss://10.0.2.2:${LOCAL_RELAY_TLS_PORT:-8443}"
    else
        echo "${RELAY_URL:-wss://relay.vauchi.app}"
    fi
}

# Get relay URL for iOS simulator
relay_get_url_ios() {
    if [ "${USE_LOCAL_RELAY:-false}" = "true" ]; then
        echo "wss://localhost:${LOCAL_RELAY_TLS_PORT:-8443}"
    else
        echo "${RELAY_URL:-wss://relay.vauchi.app}"
    fi
}

# ═══════════════════════════════════════════════════════════════
# Health Checks
# ═══════════════════════════════════════════════════════════════

# Check relay health
relay_check_health() {
    local relay_url="${1:-$(relay_get_url)}"

    # Convert wss:// to https:// for health check
    local health_url
    health_url=$(echo "$relay_url" | sed 's|^wss://|https://|; s|^ws://|http://|')
    health_url="${health_url}/health"

    log_step "Checking relay health: $health_url"

    if curl -sf -o /dev/null --connect-timeout 5 "$health_url" 2>/dev/null; then
        log_success "Relay healthy"
        return 0
    else
        log_error "Relay not responding"
        return 1
    fi
}

# Check production relay
relay_check_production() {
    log_step "Checking production relay"
    if curl -sf -o /dev/null --connect-timeout 5 "https://relay.vauchi.app/health" 2>/dev/null; then
        log_success "Production relay healthy"
        return 0
    else
        log_error "Production relay not responding"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Local Relay Management
# ═══════════════════════════════════════════════════════════════

# PID file for local relay
LOCAL_RELAY_PID_FILE="$TMP_DIR/.local_relay.pid"
LOCAL_CADDY_PID_FILE="$TMP_DIR/.local_caddy.pid"

# Check prerequisites for local relay
relay_check_local_prereqs() {
    local missing=""

    if ! command -v caddy &>/dev/null; then
        missing="${missing}caddy "
    fi

    if ! command -v mkcert &>/dev/null; then
        missing="${missing}mkcert "
    fi

    if [ -n "$missing" ]; then
        log_error "Missing prerequisites: $missing"
        echo ""
        echo "Install instructions:"
        echo "  Arch:    sudo pacman -S caddy && yay -S mkcert"
        echo "  Ubuntu:  sudo apt install caddy && brew install mkcert"
        echo "  macOS:   brew install caddy mkcert"
        return 1
    fi

    return 0
}

# Setup local CA for TLS
relay_setup_local_ca() {
    log_header "Setting up Local CA"

    if ! relay_check_local_prereqs; then
        return 1
    fi

    log_step "Installing local CA with mkcert"
    mkcert -install

    echo ""
    log_success "Local CA installed"
    echo "  CA location: $(mkcert -CAROOT)"
    echo ""
    echo "For Android Emulator, install the CA:"
    echo "  adb push \"\$(mkcert -CAROOT)/rootCA.pem\" /sdcard/"
    echo "  Then: Settings > Security > Install from storage"
}

# Check if local relay is running
relay_local_is_running() {
    if [ -f "$LOCAL_RELAY_PID_FILE" ]; then
        local pid
        pid=$(cat "$LOCAL_RELAY_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Start local relay with TLS
relay_start_local() {
    log_header "Starting Local TLS Relay"

    if ! relay_check_local_prereqs; then
        return 1
    fi

    # Check if already running
    if relay_local_is_running; then
        log_info "Local relay already running"
        return 0
    fi

    ensure_dirs

    local relay_port="${LOCAL_RELAY_PORT:-8080}"
    local tls_port="${LOCAL_RELAY_TLS_PORT:-8443}"

    # Start relay in background
    log_step "Starting relay server on port $relay_port"
    cd "$PROJECT_ROOT"
    RELAY_LISTEN_ADDR="127.0.0.1:$relay_port" \
    RELAY_STORAGE_BACKEND="memory" \
    RUST_LOG=info \
    cargo run -p vauchi-relay &>"$LOGS_DIR/relay.log" &
    local relay_pid=$!
    echo "$relay_pid" > "$LOCAL_RELAY_PID_FILE"
    register_bg_pid $relay_pid

    # Wait for relay to start
    if wait_for_port "127.0.0.1" "$relay_port" 30; then
        log_success "Relay started (PID: $relay_pid)"
    else
        log_error "Relay failed to start"
        return 1
    fi

    # Check for Caddyfile
    local caddyfile="$PROJECT_ROOT/relay/deploy/caddy/Caddyfile.local"
    if [ ! -f "$caddyfile" ]; then
        log_warn "Caddyfile not found: $caddyfile"
        log_info "Creating minimal Caddyfile"
        mkdir -p "$(dirname "$caddyfile")"
        cat > "$caddyfile" <<EOF
{
    auto_https disable_redirects
}

:$tls_port {
    tls internal
    reverse_proxy localhost:$relay_port
}
EOF
    fi

    # Start Caddy TLS proxy
    log_step "Starting TLS proxy on port $tls_port"
    caddy run --config "$caddyfile" &>"$LOGS_DIR/caddy.log" &
    local caddy_pid=$!
    echo "$caddy_pid" > "$LOCAL_CADDY_PID_FILE"
    register_bg_pid $caddy_pid

    # Wait for Caddy
    if wait_for_port "127.0.0.1" "$tls_port" 10; then
        log_success "TLS proxy started (PID: $caddy_pid)"
    else
        log_error "TLS proxy failed to start"
        return 1
    fi

    relay_print_local_info
}

# Stop local relay
relay_stop_local() {
    log_step "Stopping local relay"

    if [ -f "$LOCAL_CADDY_PID_FILE" ]; then
        local pid
        pid=$(cat "$LOCAL_CADDY_PID_FILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$LOCAL_CADDY_PID_FILE"
    fi

    if [ -f "$LOCAL_RELAY_PID_FILE" ]; then
        local pid
        pid=$(cat "$LOCAL_RELAY_PID_FILE")
        kill "$pid" 2>/dev/null || true
        rm -f "$LOCAL_RELAY_PID_FILE"
    fi

    log_success "Local relay stopped"
}

# Print connection info for local relay
relay_print_local_info() {
    local tls_port="${LOCAL_RELAY_TLS_PORT:-8443}"
    local ip
    ip=$(get_local_ip)

    echo ""
    log_info "═══════════════════════════════════════════════════════════════"
    log_info "  Local TLS Relay Connection Info"
    log_info "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  iOS Simulator:     wss://localhost:$tls_port"
    echo "  Android Emulator:  wss://10.0.2.2:$tls_port"
    echo "  Physical device:   wss://$ip:$tls_port"
    echo ""
    echo "  Note: Physical devices need the local CA installed."
    echo "        Run: just e2e-relay-setup"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# Status
# ═══════════════════════════════════════════════════════════════

# Check relay status
relay_status() {
    log_subheader "Relay Status"

    # Current configuration
    local relay_url
    relay_url=$(relay_get_url)
    echo "  Configured URL: $relay_url"
    echo "  USE_LOCAL_RELAY: ${USE_LOCAL_RELAY:-false}"
    echo ""

    # Check production relay
    if curl -sf -o /dev/null --connect-timeout 5 "https://relay.vauchi.app/health" 2>/dev/null; then
        status_ok "Production relay (relay.vauchi.app)"
    else
        status_fail "Production relay (relay.vauchi.app)"
    fi

    # Check local relay if configured
    if [ "${USE_LOCAL_RELAY:-false}" = "true" ]; then
        if relay_local_is_running; then
            status_ok "Local relay running"

            # Check TLS endpoint
            local tls_port="${LOCAL_RELAY_TLS_PORT:-8443}"
            if curl -sf -o /dev/null --connect-timeout 5 -k "https://localhost:$tls_port/health" 2>/dev/null; then
                status_ok "Local TLS proxy (port $tls_port)"
            else
                status_fail "Local TLS proxy (port $tls_port)"
            fi
        else
            status_pending "Local relay not running"
        fi
    fi

    # Check prerequisites for local relay
    if command -v caddy &>/dev/null; then
        status_ok "Caddy installed"
    else
        status_pending "Caddy not installed (optional, for local TLS)"
    fi

    if command -v mkcert &>/dev/null; then
        status_ok "mkcert installed"
    else
        status_pending "mkcert not installed (optional, for local TLS)"
    fi
}
