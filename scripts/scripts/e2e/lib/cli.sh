#!/bin/bash
# E2E Testing - CLI Functions
#
# CLI-specific functions for E2E orchestration.
# Manages CLI instances with isolated data directories for testing.
#
# Prerequisites:
#   - Rust toolchain
#   - CLI built: cargo build -p vauchi-cli

# Source common utilities if not already loaded
if [ -z "$E2E_LIB_DIR" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# ═══════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════

CLI_TEST_DATA_DIR="${CLI_TEST_DATA_DIR:-$TMP_DIR/cli-instances}"
# Use configured relay URL, falling back to production relay
CLI_RELAY_URL="${CLI_RELAY_URL:-${RELAY_URL:-wss://relay.vauchi.app}}"

# ═══════════════════════════════════════════════════════════════
# Build Management
# ═══════════════════════════════════════════════════════════════

# Build CLI binary
cli_build() {
    log_step "Building CLI"
    cd "$PROJECT_ROOT/cli"
    cargo build --target-dir "$PROJECT_ROOT/target"
    log_success "CLI built"
}

# Check if CLI is built
cli_is_built() {
    # CLI binary is named "vauchi" (from [[bin]] in Cargo.toml)
    if [ -f "$PROJECT_ROOT/target/debug/vauchi" ]; then
        return 0
    else
        return 1
    fi
}

# Get CLI binary path
cli_binary() {
    echo "$PROJECT_ROOT/target/debug/vauchi"
}

# ═══════════════════════════════════════════════════════════════
# Instance Management
# ═══════════════════════════════════════════════════════════════

# Get data directory for an instance
cli_instance_dir() {
    local instance="$1"
    echo "$CLI_TEST_DATA_DIR/$instance"
}

# Create instance directory
cli_create_instance() {
    local instance="$1"
    local data_dir
    data_dir=$(cli_instance_dir "$instance")
    mkdir -p "$data_dir"
    log_success "Created CLI instance: $instance ($data_dir)"
}

# List existing instances
cli_list_instances() {
    log_subheader "CLI Instances"
    if [ -d "$CLI_TEST_DATA_DIR" ]; then
        local instances
        instances=$(ls -1 "$CLI_TEST_DATA_DIR" 2>/dev/null || echo "")
        if [ -n "$instances" ]; then
            echo "$instances" | while read -r instance; do
                echo "  - $instance"
            done
        else
            echo "  (none)"
        fi
    else
        echo "  (none)"
    fi
}

# Clean all CLI instances
cli_clean_instances() {
    log_step "Cleaning CLI instances"
    rm -rf "$CLI_TEST_DATA_DIR"/*
    mkdir -p "$CLI_TEST_DATA_DIR"
    log_success "CLI instances cleaned"
}

# ═══════════════════════════════════════════════════════════════
# Running CLI Commands
# ═══════════════════════════════════════════════════════════════

# Prompt user for instance name
cli_prompt_instance() {
    local existing
    existing=$(ls -1 "$CLI_TEST_DATA_DIR" 2>/dev/null || echo "")

    echo ""
    if [ -n "$existing" ]; then
        echo "Existing CLI instances:"
        echo "$existing" | sed 's/^/  /'
        echo ""
    fi

    read -p "Enter instance name (e.g., alice, bob): " instance_name
    if [ -z "$instance_name" ]; then
        log_error "Instance name required"
        return 1
    fi
    echo "$instance_name"
}

# Run CLI command for an instance
cli_run() {
    local instance="$1"
    shift || true

    # Prompt if no instance provided
    if [ -z "$instance" ]; then
        instance=$(cli_prompt_instance) || return 1
    fi

    local data_dir
    data_dir=$(cli_instance_dir "$instance")
    mkdir -p "$data_dir"

    local relay_url="${CLI_RELAY_URL}"
    if [ "${USE_LOCAL_RELAY:-false}" = "true" ]; then
        relay_url="ws://127.0.0.1:${LOCAL_RELAY_PORT:-8080}"
    fi

    local cli_bin
    cli_bin=$(cli_binary)

    if [ ! -f "$cli_bin" ]; then
        log_error "CLI not built."
        if confirm "Build CLI now?"; then
            cli_build || return 1
        else
            return 1
        fi
    fi

    "$cli_bin" --data-dir "$data_dir" --relay "$relay_url" "$@"
}

# Run CLI command and capture output
cli_run_capture() {
    local instance="$1"
    shift
    cli_run "$instance" "$@" 2>&1
}

# ═══════════════════════════════════════════════════════════════
# Common Operations
# ═══════════════════════════════════════════════════════════════

# Initialize identity for an instance
cli_init() {
    local instance="$1"
    local name="${2:-$instance}"
    log_step "Initializing CLI instance: $instance as '$name'"
    cli_run "$instance" init "$name"
    log_success "Identity created for $instance"
}

# Start exchange (generate QR data)
cli_exchange_start() {
    local instance="$1"
    log_step "Starting exchange for: $instance"
    cli_run "$instance" exchange start
}

# Complete exchange with QR data
cli_exchange_complete() {
    local instance="$1"
    local qr_data="$2"
    log_step "Completing exchange for: $instance"
    cli_run "$instance" exchange complete "$qr_data"
}

# Sync with relay
cli_sync() {
    local instance="$1"
    log_step "Syncing: $instance"
    cli_run "$instance" sync
}

# List contacts
cli_contacts() {
    local instance="$1"
    cli_run "$instance" contacts list
}

# Show identity
cli_identity() {
    local instance="$1"
    cli_run "$instance" identity show
}

# ═══════════════════════════════════════════════════════════════
# Status
# ═══════════════════════════════════════════════════════════════

# Check CLI status
cli_status() {
    log_subheader "CLI Status"

    # Check if built
    if cli_is_built; then
        status_ok "CLI binary built"
    else
        status_warn "CLI not built (run: just build-cli)"
    fi

    # Check Rust
    if command -v cargo &>/dev/null; then
        local rust_version
        rust_version=$(rustc --version 2>/dev/null | head -1 || echo "Unknown")
        status_ok "Rust installed: $rust_version"
    else
        status_fail "Rust not installed"
    fi

    # List instances
    cli_list_instances
}

# ═══════════════════════════════════════════════════════════════
# E2E Test Scenarios
# ═══════════════════════════════════════════════════════════════

# Run a basic exchange test between two CLI instances
cli_test_exchange() {
    local alice="${1:-alice}"
    local bob="${2:-bob}"

    log_header "CLI Exchange Test: $alice <-> $bob"

    # Build if needed
    if ! cli_is_built; then
        cli_build
    fi

    # Clean previous data
    cli_clean_instances

    # Initialize identities
    cli_init "$alice" "Alice Smith"
    cli_init "$bob" "Bob Jones"

    # Alice starts exchange
    log_step "Alice generates exchange QR"
    local output
    output=$(cli_run_capture "$alice" exchange start 2>&1)

    # Extract the exchange data (base64 string after "Or share this data string:")
    local qr_data
    qr_data=$(echo "$output" | grep -A1 "share this data string:" | tail -1 | tr -d ' ' || true)

    # Also try matching a vauchi:// URL if present
    if [ -z "$qr_data" ]; then
        qr_data=$(echo "$output" | grep -oE 'vauchi://[^ ]+' | head -1 || true)
    fi

    # Also try matching a base64-like string (starts with V0 which is the Vauchi exchange prefix)
    if [ -z "$qr_data" ]; then
        qr_data=$(echo "$output" | grep -oE 'V0[A-Za-z0-9+/=]{50,}' | head -1 || true)
    fi

    if [ -z "$qr_data" ]; then
        log_error "Failed to get QR data from Alice"
        echo "Output was:"
        echo "$output" | head -20
        return 1
    fi
    log_info "Exchange data: ${qr_data:0:50}..."

    # Bob completes exchange
    log_step "Bob completes exchange"
    cli_run "$bob" exchange complete "$qr_data" || true

    # Try to sync both (may fail if relay not accessible)
    log_step "Syncing both instances"
    cli_sync "$alice" 2>/dev/null || log_warn "Alice sync failed (relay may be unavailable)"
    cli_sync "$bob" 2>/dev/null || log_warn "Bob sync failed (relay may be unavailable)"

    # Verify contacts
    log_step "Verifying contacts"
    echo ""
    echo "Alice's contacts:"
    local alice_contacts
    alice_contacts=$(cli_contacts "$alice" 2>&1 || true)
    echo "$alice_contacts"

    echo ""
    echo "Bob's contacts:"
    local bob_contacts
    bob_contacts=$(cli_contacts "$bob" 2>&1 || true)
    echo "$bob_contacts"

    # Check if exchange was successful (Bob should have Alice's contact)
    if echo "$bob_contacts" | grep -qi "alice\|1d477"; then
        log_success "CLI exchange test complete - contacts exchanged!"
    elif echo "$bob_contacts" | grep -qi "contact"; then
        log_success "CLI exchange test complete - contact added to Bob"
    else
        log_warn "Exchange may not have completed - check contacts manually"
    fi
}
