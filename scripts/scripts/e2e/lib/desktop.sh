#!/bin/bash
# E2E Testing - Desktop Functions
#
# Desktop (Tauri) specific functions for E2E orchestration.
# Manages desktop app instances with isolated data directories.
#
# Prerequisites:
#   - Rust toolchain
#   - Tauri CLI: cargo install tauri-cli
#   - Node.js (for frontend build)
#   - Desktop app dependencies

# Source common utilities if not already loaded
if [ -z "$E2E_LIB_DIR" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# ═══════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════

DESKTOP_TEST_DATA_DIR="${DESKTOP_TEST_DATA_DIR:-$TMP_DIR/desktop-instances}"
DESKTOP_RELAY_URL="${DESKTOP_RELAY_URL:-ws://127.0.0.1:8080}"
DESKTOP_DIR="$PROJECT_ROOT/desktop"

# ═══════════════════════════════════════════════════════════════
# Build Management
# ═══════════════════════════════════════════════════════════════

# Build desktop app (development)
desktop_build_dev() {
    log_step "Building desktop app (dev)"
    cd "$DESKTOP_DIR"

    # Install frontend dependencies if needed
    if [ ! -d "node_modules" ]; then
        log_step "Installing frontend dependencies"
        npm install
    fi

    # Build frontend
    log_step "Building frontend"
    npm run build

    log_success "Desktop app ready for dev mode"
}

# Build desktop app (release)
desktop_build_release() {
    log_step "Building desktop app (release)"
    cd "$DESKTOP_DIR"

    # Install frontend dependencies if needed
    if [ ! -d "node_modules" ]; then
        log_step "Installing frontend dependencies"
        npm install
    fi

    cargo tauri build
    log_success "Desktop app built (release)"
}

# Check if desktop is ready for dev mode
desktop_is_ready() {
    if [ -d "$DESKTOP_DIR" ] && [ -f "$DESKTOP_DIR/src-tauri/Cargo.toml" ]; then
        return 0
    else
        return 1
    fi
}

# Find built desktop binary
desktop_find_binary() {
    local os_type
    os_type=$(uname -s)

    case "$os_type" in
        Linux)
            find "$DESKTOP_DIR/src-tauri/target/release/bundle" -name "*.AppImage" 2>/dev/null | head -1
            ;;
        Darwin)
            find "$DESKTOP_DIR/src-tauri/target/release/bundle" -name "*.app" -type d 2>/dev/null | head -1
            ;;
        *)
            echo ""
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# Instance Management
# ═══════════════════════════════════════════════════════════════

# Get data directory for an instance
desktop_instance_dir() {
    local instance="$1"
    echo "$DESKTOP_TEST_DATA_DIR/$instance"
}

# Create instance directory
desktop_create_instance() {
    local instance="$1"
    local data_dir
    data_dir=$(desktop_instance_dir "$instance")
    mkdir -p "$data_dir"
    log_success "Created desktop instance: $instance ($data_dir)"
}

# List existing instances
desktop_list_instances() {
    log_subheader "Desktop Instances"
    if [ -d "$DESKTOP_TEST_DATA_DIR" ]; then
        local instances
        instances=$(ls -1 "$DESKTOP_TEST_DATA_DIR" 2>/dev/null || echo "")
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

# Clean all desktop instances
desktop_clean_instances() {
    log_step "Cleaning desktop instances"
    rm -rf "$DESKTOP_TEST_DATA_DIR"/*
    mkdir -p "$DESKTOP_TEST_DATA_DIR"
    log_success "Desktop instances cleaned"
}

# ═══════════════════════════════════════════════════════════════
# Running Desktop App
# ═══════════════════════════════════════════════════════════════

# Prompt user for instance name
desktop_prompt_instance() {
    local existing
    existing=$(ls -1 "$DESKTOP_TEST_DATA_DIR" 2>/dev/null || echo "")

    echo ""
    if [ -n "$existing" ]; then
        echo "Existing Desktop instances:"
        echo "$existing" | sed 's/^/  /'
        echo ""
    fi

    read -p "Enter instance name (e.g., alice, bob, default): " instance_name
    if [ -z "$instance_name" ]; then
        instance_name="default"
    fi
    echo "$instance_name"
}

# Launch desktop in dev mode for an instance
desktop_launch_dev() {
    local instance="$1"

    # Prompt if no instance provided
    if [ -z "$instance" ]; then
        instance=$(desktop_prompt_instance) || return 1
    fi

    local data_dir
    data_dir=$(desktop_instance_dir "$instance")
    mkdir -p "$data_dir"

    local relay_url="${DESKTOP_RELAY_URL}"
    if [ "${USE_LOCAL_RELAY:-false}" = "true" ]; then
        relay_url="ws://127.0.0.1:${LOCAL_RELAY_PORT:-8080}"
    fi

    if ! desktop_is_ready; then
        log_error "Desktop app not found at $DESKTOP_DIR"
        echo ""
        echo "Make sure you have cloned the desktop repo:"
        echo "  just clone-repos"
        return 1
    fi

    log_info "Launching desktop instance: $instance (dev mode)"
    log_info "Data directory: $data_dir"
    log_info "Relay: $relay_url"
    echo ""

    cd "$DESKTOP_DIR"
    VAUCHI_DATA_DIR="$data_dir" VAUCHI_RELAY_URL="$relay_url" cargo tauri dev
}

# Launch desktop (built binary) for an instance
desktop_launch() {
    local instance="$1"

    # Prompt if no instance provided
    if [ -z "$instance" ]; then
        instance=$(desktop_prompt_instance) || return 1
    fi

    local data_dir
    data_dir=$(desktop_instance_dir "$instance")
    mkdir -p "$data_dir"

    local relay_url="${DESKTOP_RELAY_URL}"
    if [ "${USE_LOCAL_RELAY:-false}" = "true" ]; then
        relay_url="ws://127.0.0.1:${LOCAL_RELAY_PORT:-8080}"
    fi

    local binary
    binary=$(desktop_find_binary)

    if [ -z "$binary" ]; then
        log_warn "Built binary not found, falling back to dev mode"
        desktop_launch_dev "$instance"
        return
    fi

    log_info "Launching desktop instance: $instance"
    log_info "Binary: $binary"
    log_info "Data directory: $data_dir"
    log_info "Relay: $relay_url"
    echo ""

    local os_type
    os_type=$(uname -s)

    case "$os_type" in
        Linux)
            VAUCHI_DATA_DIR="$data_dir" VAUCHI_RELAY_URL="$relay_url" "$binary" &
            ;;
        Darwin)
            VAUCHI_DATA_DIR="$data_dir" VAUCHI_RELAY_URL="$relay_url" open "$binary" --args &
            ;;
        *)
            log_error "Unsupported OS: $os_type"
            return 1
            ;;
    esac

    log_success "Desktop launched"
}

# ═══════════════════════════════════════════════════════════════
# Status
# ═══════════════════════════════════════════════════════════════

# Check desktop status
desktop_status() {
    log_subheader "Desktop Status"

    # Check desktop directory
    if desktop_is_ready; then
        status_ok "Desktop project found"
    else
        status_fail "Desktop project not found at $DESKTOP_DIR"
        return
    fi

    # Check Tauri CLI
    if command -v cargo-tauri &>/dev/null || cargo tauri --version &>/dev/null 2>&1; then
        status_ok "Tauri CLI available"
    else
        status_warn "Tauri CLI not installed (run: cargo install tauri-cli)"
    fi

    # Check Node.js
    if command -v node &>/dev/null; then
        local node_version
        node_version=$(node --version 2>/dev/null || echo "Unknown")
        status_ok "Node.js installed: $node_version"
    else
        status_warn "Node.js not installed"
    fi

    # Check for built binary
    local binary
    binary=$(desktop_find_binary)
    if [ -n "$binary" ]; then
        status_ok "Built binary found: $binary"
    else
        status_pending "Release binary not built"
    fi

    # List instances
    desktop_list_instances
}

# ═══════════════════════════════════════════════════════════════
# Multi-Instance Notes
# ═══════════════════════════════════════════════════════════════

# Print multi-instance instructions
desktop_multi_info() {
    log_header "Desktop Multi-Instance Testing"

    echo "Desktop apps may have single-instance restrictions."
    echo ""
    echo "Recommended approaches for multi-instance testing:"
    echo ""
    echo "1. Desktop + CLI/TUI combination:"
    echo "   Terminal 1: just e2e-desktop-dev alice"
    echo "   Terminal 2: just e2e-cli bob init 'Bob'"
    echo ""
    echo "2. Dev mode + Built app:"
    echo "   Terminal 1: just e2e-desktop-dev alice"
    echo "   Terminal 2: just e2e-desktop bob  (uses built binary)"
    echo ""
    echo "3. Different data directories with environment:"
    echo "   VAUCHI_DATA_DIR=/tmp/alice cargo tauri dev"
    echo "   VAUCHI_DATA_DIR=/tmp/bob   cargo tauri dev"
    echo ""
}
