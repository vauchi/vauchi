#!/bin/bash
# E2E Testing - iOS Functions
#
# iOS-specific functions for E2E orchestration.
# All functions run commands on the macOS VM via SSH.
#
# Prerequisites:
#   - macOS VM accessible via SSH (ssh -p 2222 user@localhost)
#   - Xcode and iOS Simulator installed on VM
#   - App built on VM

# Source common utilities if not already loaded
if [ -z "$E2E_LIB_DIR" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# ═══════════════════════════════════════════════════════════════
# Simulator Management
# ═══════════════════════════════════════════════════════════════

# Prompt user to select a simulator
ios_select_simulator() {
    log_step "Fetching available simulators..."
    local simulators
    simulators=$(ssh_mac "xcrun simctl list devices available | grep -E 'iPhone|iPad' | sed 's/^ *//' | head -10" 2>/dev/null || echo "")

    if [ -z "$simulators" ]; then
        log_error "No simulators available"
        return 1
    fi

    echo ""
    echo "Available iOS Simulators:"
    local i=1
    local sim_array=()
    while IFS= read -r sim; do
        # Extract just the name (before the parentheses)
        local sim_name
        sim_name=$(echo "$sim" | sed 's/ (.*$//')
        echo "  $i) $sim_name"
        sim_array+=("$sim_name")
        i=$((i + 1))
    done <<< "$simulators"

    echo ""
    read -p "Select simulator [1-$((i-1))]: " selection

    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -lt "$i" ]; then
        echo "${sim_array[$((selection-1))]}"
        return 0
    else
        return 1
    fi
}

# Boot iOS simulator
ios_boot() {
    local simulator="${1:-$IOS_SIMULATOR}"
    log_step "Booting iOS simulator: $simulator"

    # Check if simulator exists
    if ! ssh_mac "xcrun simctl list devices | grep -q '$simulator'"; then
        log_warn "Simulator '$simulator' not found"
        local selected
        selected=$(ios_select_simulator)
        if [ -n "$selected" ]; then
            simulator="$selected"
            log_info "Using simulator: $simulator"
        else
            log_error "No simulator selected"
            if confirm "Skip iOS deployment?"; then
                return 2
            fi
            return 1
        fi
    fi

    ssh_mac "xcrun simctl boot '$simulator' 2>/dev/null || true"

    # Wait for simulator to be ready
    local attempts=0
    while [ $attempts -lt 30 ]; do
        if ssh_mac "xcrun simctl list devices | grep '$simulator' | grep -q 'Booted'"; then
            log_success "Simulator booted"
            return 0
        fi
        sleep 1
        attempts=$((attempts + 1))
    done

    log_error "Simulator failed to boot"
    return 1
}

# Shutdown iOS simulator
ios_shutdown() {
    local simulator="${1:-$IOS_SIMULATOR}"
    log_step "Shutting down iOS simulator: $simulator"
    ssh_mac "xcrun simctl shutdown '$simulator' 2>/dev/null || true"
    log_success "Simulator shutdown"
}

# Get booted simulator device ID
ios_get_booted_udid() {
    ssh_mac "xcrun simctl list devices | grep 'Booted' | head -1 | sed 's/.*(\([A-Z0-9-]*\)).*/\1/'"
}

# Check if simulator is booted
ios_is_booted() {
    local simulator="${1:-$IOS_SIMULATOR}"
    if ssh_mac "xcrun simctl list devices | grep '$simulator' | grep -q 'Booted'"; then
        return 0
    else
        return 1
    fi
}

# List available simulators
ios_list_simulators() {
    ssh_mac "xcrun simctl list devices available"
}

# Reset simulator (erase all data)
ios_reset() {
    local simulator="${1:-$IOS_SIMULATOR}"
    log_step "Resetting iOS simulator: $simulator"
    ssh_mac "xcrun simctl shutdown '$simulator' 2>/dev/null || true"
    ssh_mac "xcrun simctl erase '$simulator'"
    log_success "Simulator reset"
}

# ═══════════════════════════════════════════════════════════════
# App Management
# ═══════════════════════════════════════════════════════════════

# Find the app bundle on macOS VM
ios_find_app() {
    local app_path="${1:-$IOS_APP_PATH}"
    # Expand glob on remote
    ssh_mac "ls -d ~/$app_path 2>/dev/null | head -1"
}

# Install app to simulator
ios_install() {
    local app_path="${1:-}"

    if [ -z "$app_path" ]; then
        app_path=$(ios_find_app)
    fi

    if [ -z "$app_path" ]; then
        log_error "Could not find iOS app. Build the app first."
        return 1
    fi

    log_step "Installing iOS app: $app_path"
    local output
    output=$(ssh_mac "xcrun simctl install booted '$app_path'" 2>&1)

    if [ $? -ne 0 ] || echo "$output" | grep -qi "error"; then
        log_error "Failed to install iOS app"
        echo "$output" | sed 's/^/  /'
        echo ""
        log_info "Try rebuilding the app in Xcode (Cmd+B)"
        return 1
    fi

    log_success "App installed"
}

# Uninstall app from simulator
ios_uninstall() {
    local bundle_id="${1:-$IOS_BUNDLE_ID}"
    log_step "Uninstalling iOS app: $bundle_id"
    ssh_mac "xcrun simctl uninstall booted '$bundle_id' 2>/dev/null || true"
    log_success "App uninstalled"
}

# Launch app on simulator
ios_launch() {
    local bundle_id="${1:-$IOS_BUNDLE_ID}"
    log_step "Launching iOS app: $bundle_id"

    local output
    output=$(ssh_mac "xcrun simctl launch booted '$bundle_id'" 2>&1)

    if [ $? -ne 0 ] || echo "$output" | grep -qi "error"; then
        log_error "Failed to launch iOS app"
        echo "$output" | sed 's/^/  /'
        return 1
    fi

    log_success "App launched"
}

# Terminate app on simulator
ios_terminate() {
    local bundle_id="${1:-$IOS_BUNDLE_ID}"
    log_step "Terminating iOS app: $bundle_id"
    ssh_mac "xcrun simctl terminate booted '$bundle_id' 2>/dev/null || true"
    log_success "App terminated"
}

# Check if app is installed
ios_is_installed() {
    local bundle_id="${1:-$IOS_BUNDLE_ID}"
    if ssh_mac "xcrun simctl get_app_container booted '$bundle_id' 2>/dev/null" | grep -q "/"; then
        return 0
    else
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Screenshots and UI
# ═══════════════════════════════════════════════════════════════

# Take screenshot of simulator
ios_screenshot() {
    local output="${1:-ios_screenshot_$(timestamp).png}"
    local remote_path="/tmp/ios_screenshot_$(timestamp).png"

    log_step "Taking iOS screenshot"
    ssh_mac "xcrun simctl io booted screenshot '$remote_path'"
    scp_from_mac "$remote_path" "$output"
    ssh_mac "rm -f '$remote_path'"
    log_success "Screenshot saved: $output"
    echo "$output"
}

# Get accessibility hierarchy (for UI inspection)
ios_accessibility_dump() {
    local output="${1:-}"

    log_step "Getting iOS accessibility dump"
    local dump
    dump=$(ssh_mac "xcrun simctl ui booted accessibility 2>/dev/null || echo 'Accessibility dump not available'")

    if [ -n "$output" ]; then
        echo "$dump" > "$output"
        log_success "Accessibility dump saved: $output"
    else
        echo "$dump"
    fi
}

# ═══════════════════════════════════════════════════════════════
# Logs
# ═══════════════════════════════════════════════════════════════

# Get app logs from simulator
ios_logs() {
    local bundle_id="${1:-$IOS_BUNDLE_ID}"
    local lines="${2:-100}"

    log_step "Getting iOS app logs"
    ssh_mac "xcrun simctl spawn booted log stream --predicate 'subsystem == \"$bundle_id\"' --level debug 2>/dev/null | head -$lines" || \
    ssh_mac "xcrun simctl spawn booted log show --predicate 'subsystem == \"$bundle_id\"' --last ${lines}m 2>/dev/null | tail -$lines"
}

# Save logs to file
ios_save_logs() {
    local output="${1:-$LOGS_DIR/ios_logs_$(timestamp).txt}"
    local bundle_id="${2:-$IOS_BUNDLE_ID}"

    ensure_dirs
    ios_logs "$bundle_id" 500 > "$output"
    log_success "iOS logs saved: $output"
}

# ═══════════════════════════════════════════════════════════════
# Deep Links and Data
# ═══════════════════════════════════════════════════════════════

# Open URL/deep link in app
ios_open_url() {
    local url="$1"
    log_step "Opening URL on iOS: $url"
    ssh_mac "xcrun simctl openurl booted '$url'"
}

# Set clipboard content
ios_set_clipboard() {
    local content="$1"
    log_step "Setting iOS clipboard"
    ssh_mac "xcrun simctl pbcopy booted" <<< "$content"
}

# Get clipboard content
ios_get_clipboard() {
    ssh_mac "xcrun simctl pbpaste booted"
}

# ═══════════════════════════════════════════════════════════════
# Status Checks
# ═══════════════════════════════════════════════════════════════

# Check iOS setup status
ios_status() {
    log_subheader "iOS Status"

    # Check SSH connectivity
    if check_ssh_mac; then
        status_ok "macOS VM reachable via SSH"
    else
        status_fail "macOS VM not reachable (ssh -p $MACOS_SSH_PORT $MACOS_SSH_USER@$MACOS_SSH_HOST)"
        return 1
    fi

    # Check Xcode
    if ssh_mac "which xcrun" &>/dev/null; then
        local xcode_version
        xcode_version=$(ssh_mac "xcodebuild -version 2>/dev/null | head -1" || echo "Unknown")
        status_ok "Xcode installed: $xcode_version"
    else
        status_fail "Xcode not found"
    fi

    # Check simulator
    if ios_is_booted; then
        status_ok "Simulator running: $IOS_SIMULATOR"
    else
        status_pending "Simulator not running: $IOS_SIMULATOR"
    fi

    # Check app
    local app_path
    app_path=$(ios_find_app 2>/dev/null || echo "")
    if [ -n "$app_path" ]; then
        status_ok "App found: $app_path"
    else
        status_warn "App not found (build required)"
    fi

    # Check if app is installed
    if ios_is_booted; then
        if ios_is_installed; then
            status_ok "App installed on simulator"
        else
            status_pending "App not installed on simulator"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# Full Deploy Flow
# ═══════════════════════════════════════════════════════════════

# Deploy iOS app (boot simulator, install, launch)
ios_deploy() {
    log_header "Deploying iOS App"

    # Check SSH first
    if ! check_ssh_mac; then
        log_error "Cannot connect to macOS VM"
        echo ""
        echo "Make sure macOS VM is running and SSH is enabled:"
        echo "  ssh -p ${MACOS_SSH_PORT:-2222} ${MACOS_SSH_USER:-user}@${MACOS_SSH_HOST:-localhost}"
        echo ""
        if confirm "Skip iOS deployment?"; then
            return 0
        fi
        return 1
    fi

    # Boot simulator
    if ! ios_is_booted; then
        local boot_result
        ios_boot
        boot_result=$?
        if [ $boot_result -eq 2 ]; then
            log_info "Skipping iOS deployment"
            return 0
        elif [ $boot_result -ne 0 ]; then
            return 1
        fi
    else
        log_info "Simulator already running"
    fi

    # Find and install app
    local app_path
    app_path=$(ios_find_app)
    if [ -z "$app_path" ]; then
        log_error "iOS app not found."
        echo ""
        echo "Build it on the Mac with Xcode:"
        echo "  1. Open ios/Vauchi.xcodeproj"
        echo "  2. Select simulator target"
        echo "  3. Build (Cmd+B)"
        echo ""
        if confirm "Skip iOS deployment?"; then
            return 0
        fi
        return 1
    fi

    ios_install "$app_path" || return 1

    # Launch app
    ios_launch || return 1

    log_success "iOS deployment complete"
}
