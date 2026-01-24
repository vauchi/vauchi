#!/bin/bash
# E2E Testing - TUI Functions
#
# TUI-specific functions for E2E orchestration.
# Manages TUI instances with isolated data directories for testing.
#
# Prerequisites:
#   - Rust toolchain
#   - TUI built: cargo build -p vauchi-tui

# Source common utilities if not already loaded
if [ -z "$E2E_LIB_DIR" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# ═══════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════

TUI_TEST_DATA_DIR="${TUI_TEST_DATA_DIR:-$TMP_DIR/tui-instances}"
# Use configured relay URL, falling back to production relay
TUI_RELAY_URL="${TUI_RELAY_URL:-${RELAY_URL:-wss://relay.vauchi.app}}"

# ═══════════════════════════════════════════════════════════════
# Build Management
# ═══════════════════════════════════════════════════════════════

# Build TUI binary
tui_build() {
    log_step "Building TUI"
    cd "$PROJECT_ROOT/tui"
    cargo build --target-dir "$PROJECT_ROOT/target"
    log_success "TUI built"
}

# Check if TUI is built
tui_is_built() {
    # Check shared target first, then local tui target
    if [ -f "$PROJECT_ROOT/target/debug/vauchi-tui" ]; then
        return 0
    elif [ -f "$PROJECT_ROOT/tui/target/debug/vauchi-tui" ]; then
        return 0
    else
        return 1
    fi
}

# Get TUI binary path
tui_binary() {
    # Prefer shared target, fall back to local
    if [ -f "$PROJECT_ROOT/target/debug/vauchi-tui" ]; then
        echo "$PROJECT_ROOT/target/debug/vauchi-tui"
    else
        echo "$PROJECT_ROOT/tui/target/debug/vauchi-tui"
    fi
}

# ═══════════════════════════════════════════════════════════════
# Instance Management
# ═══════════════════════════════════════════════════════════════

# Get data directory for an instance
tui_instance_dir() {
    local instance="$1"
    echo "$TUI_TEST_DATA_DIR/$instance"
}

# Create instance directory
tui_create_instance() {
    local instance="$1"
    local data_dir
    data_dir=$(tui_instance_dir "$instance")
    mkdir -p "$data_dir"
    log_success "Created TUI instance: $instance ($data_dir)"
}

# List existing instances
tui_list_instances() {
    log_subheader "TUI Instances"
    if [ -d "$TUI_TEST_DATA_DIR" ]; then
        local instances
        instances=$(ls -1 "$TUI_TEST_DATA_DIR" 2>/dev/null || echo "")
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

# Clean all TUI instances
tui_clean_instances() {
    log_step "Cleaning TUI instances"
    rm -rf "$TUI_TEST_DATA_DIR"/*
    mkdir -p "$TUI_TEST_DATA_DIR"
    log_success "TUI instances cleaned"
}

# ═══════════════════════════════════════════════════════════════
# Running TUI
# ═══════════════════════════════════════════════════════════════

# Prompt user for instance name
tui_prompt_instance() {
    local existing
    existing=$(ls -1 "$TUI_TEST_DATA_DIR" 2>/dev/null || echo "")

    echo ""
    if [ -n "$existing" ]; then
        echo "Existing TUI instances:"
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

# Launch TUI for an instance (interactive)
tui_launch() {
    local instance="$1"

    # Prompt if no instance provided
    if [ -z "$instance" ]; then
        instance=$(tui_prompt_instance) || return 1
    fi

    local data_dir
    data_dir=$(tui_instance_dir "$instance")
    mkdir -p "$data_dir"

    local relay_url="${TUI_RELAY_URL}"
    if [ "${USE_LOCAL_RELAY:-false}" = "true" ]; then
        relay_url="ws://127.0.0.1:${LOCAL_RELAY_PORT:-8080}"
    fi

    local tui_bin
    tui_bin=$(tui_binary)

    if [ ! -f "$tui_bin" ]; then
        log_error "TUI not built."
        if confirm "Build TUI now?"; then
            tui_build || return 1
        else
            return 1
        fi
    fi

    log_info "Launching TUI instance: $instance"
    log_info "Data directory: $data_dir"
    log_info "Relay: $relay_url"
    echo ""

    VAUCHI_DATA_DIR="$data_dir" VAUCHI_RELAY_URL="$relay_url" "$tui_bin"
}

# Launch TUI in a new terminal (for multi-instance testing)
tui_launch_terminal() {
    local instance="$1"
    local data_dir
    data_dir=$(tui_instance_dir "$instance")
    mkdir -p "$data_dir"

    local relay_url="${TUI_RELAY_URL}"
    if [ "${USE_LOCAL_RELAY:-false}" = "true" ]; then
        relay_url="ws://127.0.0.1:${LOCAL_RELAY_PORT:-8080}"
    fi

    local tui_bin
    tui_bin=$(tui_binary)

    if [ ! -f "$tui_bin" ]; then
        log_error "TUI not built. Run: just build"
        return 1
    fi

    local title="Vauchi TUI: $instance"

    log_step "Launching TUI in new terminal: $instance"

    # Try various terminal emulators (using explicit command invocation to avoid quoting issues)
    if command -v alacritty &>/dev/null; then
        alacritty --title "$title" -e env VAUCHI_DATA_DIR="$data_dir" VAUCHI_RELAY_URL="$relay_url" "$tui_bin" &
    elif command -v gnome-terminal &>/dev/null; then
        gnome-terminal --title="$title" -- env VAUCHI_DATA_DIR="$data_dir" VAUCHI_RELAY_URL="$relay_url" "$tui_bin" &
    elif command -v konsole &>/dev/null; then
        konsole --title "$title" -e env VAUCHI_DATA_DIR="$data_dir" VAUCHI_RELAY_URL="$relay_url" "$tui_bin" &
    elif command -v xterm &>/dev/null; then
        xterm -title "$title" -e env VAUCHI_DATA_DIR="$data_dir" VAUCHI_RELAY_URL="$relay_url" "$tui_bin" &
    elif command -v kitty &>/dev/null; then
        kitty --title "$title" env VAUCHI_DATA_DIR="$data_dir" VAUCHI_RELAY_URL="$relay_url" "$tui_bin" &
    else
        log_error "No supported terminal emulator found"
        log_info "Run manually: VAUCHI_DATA_DIR='$data_dir' VAUCHI_RELAY_URL='$relay_url' $tui_bin"
        return 1
    fi

    log_success "TUI launched in new terminal"
}

# ═══════════════════════════════════════════════════════════════
# Status
# ═══════════════════════════════════════════════════════════════

# Check TUI status
tui_status() {
    log_subheader "TUI Status"

    # Check if built
    if tui_is_built; then
        status_ok "TUI binary built"
    else
        status_warn "TUI not built (run: just build)"
    fi

    # Check Rust
    if command -v cargo &>/dev/null; then
        status_ok "Rust toolchain available"
    else
        status_fail "Rust not installed"
    fi

    # List instances
    tui_list_instances
}

# ═══════════════════════════════════════════════════════════════
# Multi-Instance Setup
# ═══════════════════════════════════════════════════════════════

# Launch multiple TUI instances for testing
tui_launch_multi() {
    local instances=("${@:-alice bob}")

    log_header "Launching Multiple TUI Instances"

    # Build if needed
    if ! tui_is_built; then
        tui_build
    fi

    for instance in "${instances[@]}"; do
        tui_launch_terminal "$instance"
        sleep 1  # Give each terminal time to start
    done

    log_success "Launched ${#instances[@]} TUI instances"
    echo ""
    echo "Each instance has isolated data. Use them to test:"
    echo "  1. Create identities"
    echo "  2. Exchange contacts via QR"
    echo "  3. Update cards and verify sync"
}
