#!/bin/bash
# E2E Testing - Android Functions
#
# Android-specific functions for E2E orchestration.
# All functions run locally (Android emulator on Linux).
#
# Prerequisites:
#   - Android SDK with emulator and adb
#   - AVD created (e.g., Pixel_7)
#   - APK built

# Source common utilities if not already loaded
if [ -z "$E2E_LIB_DIR" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# ═══════════════════════════════════════════════════════════════
# ADB Utilities
# ═══════════════════════════════════════════════════════════════

# Check if adb is available
android_check_adb() {
    if command -v adb &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Get connected emulator device ID
android_get_emulator_id() {
    adb devices | grep "emulator-" | head -1 | awk '{print $1}'
}

# Check if an emulator is running
android_is_running() {
    local device_id
    device_id=$(android_get_emulator_id)
    if [ -n "$device_id" ]; then
        return 0
    else
        return 1
    fi
}

# Wait for device to be ready
android_wait_for_device() {
    local timeout="${1:-60}"
    log_step "Waiting for Android device (timeout: ${timeout}s)"

    if timeout "$timeout" adb wait-for-device; then
        # Wait for boot to complete
        local attempts=0
        while [ $attempts -lt 30 ]; do
            if adb shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; then
                log_success "Device ready"
                return 0
            fi
            sleep 2
            attempts=$((attempts + 1))
        done
    fi

    log_error "Device not ready"
    return 1
}

# ═══════════════════════════════════════════════════════════════
# Emulator Management
# ═══════════════════════════════════════════════════════════════

# Prompt user to select an AVD
android_select_avd() {
    local available_avds
    available_avds=$(android_list_avds 2>/dev/null || echo "")

    if [ -z "$available_avds" ]; then
        return 1
    fi

    echo ""
    echo "Available AVDs:"
    local i=1
    local avd_array=()
    while IFS= read -r avd; do
        echo "  $i) $avd"
        avd_array+=("$avd")
        i=$((i + 1))
    done <<< "$available_avds"

    echo ""
    read -p "Select AVD [1-$((i-1))]: " selection

    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -lt "$i" ]; then
        echo "${avd_array[$((selection-1))]}"
        return 0
    else
        return 1
    fi
}

# Boot Android emulator
android_boot() {
    local avd="${1:-$ANDROID_AVD_NAME}"
    log_step "Booting Android emulator: $avd"

    # Check if already running
    if android_is_running; then
        log_info "Emulator already running"
        return 0
    fi

    # Check if AVD exists
    local available_avds
    available_avds=$(android_list_avds 2>/dev/null || echo "")
    if [ -z "$available_avds" ]; then
        log_error "No AVDs available."
        echo ""
        echo "Create one with Android Studio or command line:"
        echo "  sdkmanager 'system-images;android-34;google_apis;x86_64'"
        echo "  avdmanager create avd -n Pixel_7 -k 'system-images;android-34;google_apis;x86_64'"
        echo ""
        if confirm "Skip Android emulator for now?"; then
            return 2  # Special return code for "skip"
        fi
        return 1
    fi

    if ! echo "$available_avds" | grep -q "^${avd}$"; then
        log_warn "AVD '$avd' not found."
        echo ""
        local selected_avd
        selected_avd=$(android_select_avd)
        if [ -n "$selected_avd" ]; then
            avd="$selected_avd"
            log_info "Using AVD: $avd"
        else
            log_error "No AVD selected"
            return 1
        fi
    fi

    # Create log file for emulator output
    local emu_log="$LOGS_DIR/emulator_$(timestamp).log"
    mkdir -p "$LOGS_DIR"

    # Start emulator in background with error logging
    # Use xcb Qt platform for X11/Wayland compatibility (configurable in config.env)
    local qt_platform="${ANDROID_QT_PLATFORM:-xcb}"
    log_info "Starting emulator (this may take a while)..."
    log_info "Log file: $emu_log"
    QT_QPA_PLATFORM="$qt_platform" emulator -avd "$avd" -no-snapshot-load -no-boot-anim -gpu auto 2>&1 | tee "$emu_log" &
    local emulator_pid=$!
    register_bg_pid $emulator_pid

    # Give it a moment to fail fast if there's an immediate error
    sleep 3
    if ! kill -0 "$emulator_pid" 2>/dev/null; then
        log_error "Emulator process exited immediately"
        echo ""
        echo "Last lines from emulator log:"
        tail -20 "$emu_log" 2>/dev/null | sed 's/^/  /'
        echo ""
        log_info "Common fixes:"
        echo "  1. Try with software rendering: emulator -avd $avd -gpu swiftshader_indirect"
        echo "  2. Check KVM permissions: sudo usermod -aG kvm \$USER (then re-login)"
        echo "  3. Recreate AVD with compatible system image"
        echo "  4. Run Android Studio to update emulator components"
        return 1
    fi

    # Wait for device
    if android_wait_for_device 120; then
        log_success "Emulator booted"
        return 0
    else
        log_error "Failed to boot emulator (timeout)"
        log_info "Check log: $emu_log"
        return 1
    fi
}

# Boot emulator with software rendering (fallback for graphics issues)
android_boot_sw() {
    local avd="${1:-$ANDROID_AVD_NAME}"
    log_step "Booting Android emulator with software rendering: $avd"

    if android_is_running; then
        log_info "Emulator already running"
        return 0
    fi

    local emu_log="$LOGS_DIR/emulator_$(timestamp).log"
    mkdir -p "$LOGS_DIR"

    local qt_platform="${ANDROID_QT_PLATFORM:-xcb}"
    log_info "Using software rendering (slower but more compatible)"
    QT_QPA_PLATFORM="$qt_platform" emulator -avd "$avd" -no-snapshot-load -no-boot-anim -gpu swiftshader_indirect 2>&1 | tee "$emu_log" &
    local emulator_pid=$!
    register_bg_pid $emulator_pid

    sleep 3
    if ! kill -0 "$emulator_pid" 2>/dev/null; then
        log_error "Emulator failed even with software rendering"
        tail -20 "$emu_log" 2>/dev/null | sed 's/^/  /'
        return 1
    fi

    if android_wait_for_device 180; then
        log_success "Emulator booted (software rendering)"
        return 0
    else
        log_error "Failed to boot emulator (timeout)"
        return 1
    fi
}

# Shutdown Android emulator
android_shutdown() {
    log_step "Shutting down Android emulator"
    local device_id
    device_id=$(android_get_emulator_id)

    if [ -n "$device_id" ]; then
        adb -s "$device_id" emu kill 2>/dev/null || true
        log_success "Emulator shutdown"
    else
        log_info "No emulator running"
    fi
}

# List available AVDs
android_list_avds() {
    emulator -list-avds 2>/dev/null
}

# Reset emulator (wipe data)
android_reset() {
    local avd="${1:-$ANDROID_AVD_NAME}"
    log_step "Resetting Android emulator: $avd"
    android_shutdown
    emulator -avd "$avd" -wipe-data -no-snapshot-load &>/dev/null &
    android_wait_for_device 90
    log_success "Emulator reset"
}

# ═══════════════════════════════════════════════════════════════
# App Management
# ═══════════════════════════════════════════════════════════════

# Find APK file
android_find_apk() {
    local apk_path="${1:-$PROJECT_ROOT/$ANDROID_APK_PATH}"
    if [ -f "$apk_path" ]; then
        echo "$apk_path"
    else
        # Try to find any debug APK
        find "$PROJECT_ROOT/android" -name "*.apk" -path "*/debug/*" 2>/dev/null | head -1
    fi
}

# Install APK to emulator
android_install() {
    local apk_path="${1:-}"

    if [ -z "$apk_path" ]; then
        apk_path=$(android_find_apk)
    fi

    if [ -z "$apk_path" ] || [ ! -f "$apk_path" ]; then
        log_error "Could not find APK. Build the app first."
        return 1
    fi

    log_step "Installing Android app: $apk_path"
    local output
    output=$(adb install -r "$apk_path" 2>&1)

    if echo "$output" | grep -q "Success"; then
        log_success "App installed"
    else
        log_error "Failed to install APK"
        echo "$output" | sed 's/^/  /'
        return 1
    fi
}

# Uninstall app from emulator
android_uninstall() {
    local package="${1:-$ANDROID_PACKAGE}"
    log_step "Uninstalling Android app: $package"
    adb uninstall "$package" 2>/dev/null || true
    log_success "App uninstalled"
}

# Launch app on emulator
android_launch() {
    local package="${1:-$ANDROID_PACKAGE}"
    local activity="${ANDROID_ACTIVITY:-.MainActivity}"
    log_step "Launching Android app: $package"

    local output
    output=$(adb shell am start -n "$package/$activity" 2>&1)

    if echo "$output" | grep -q "Error"; then
        log_error "Failed to launch app"
        echo "$output" | sed 's/^/  /'
        return 1
    fi

    log_success "App launched"
}

# Force stop app on emulator
android_stop() {
    local package="${1:-$ANDROID_PACKAGE}"
    log_step "Stopping Android app: $package"
    adb shell am force-stop "$package"
    log_success "App stopped"
}

# Check if app is installed
android_is_installed() {
    local package="${1:-$ANDROID_PACKAGE}"
    if adb shell pm list packages 2>/dev/null | grep -q "$package"; then
        return 0
    else
        return 1
    fi
}

# Clear app data
android_clear_data() {
    local package="${1:-$ANDROID_PACKAGE}"
    log_step "Clearing Android app data: $package"
    adb shell pm clear "$package"
    log_success "App data cleared"
}

# ═══════════════════════════════════════════════════════════════
# Screenshots and UI
# ═══════════════════════════════════════════════════════════════

# Take screenshot of emulator
android_screenshot() {
    local output="${1:-android_screenshot_$(timestamp).png}"

    log_step "Taking Android screenshot"
    adb shell screencap -p /sdcard/screenshot.png
    adb pull /sdcard/screenshot.png "$output"
    adb shell rm /sdcard/screenshot.png
    log_success "Screenshot saved: $output"
    echo "$output"
}

# Get UI hierarchy (for inspection)
android_ui_dump() {
    local output="${1:-}"

    log_step "Getting Android UI dump"
    adb shell uiautomator dump /sdcard/ui_dump.xml
    local dump
    dump=$(adb shell cat /sdcard/ui_dump.xml)
    adb shell rm /sdcard/ui_dump.xml

    if [ -n "$output" ]; then
        echo "$dump" > "$output"
        log_success "UI dump saved: $output"
    else
        echo "$dump"
    fi
}

# ═══════════════════════════════════════════════════════════════
# Logs
# ═══════════════════════════════════════════════════════════════

# Get app logs from logcat
android_logs() {
    local package="${1:-$ANDROID_PACKAGE}"
    local lines="${2:-100}"

    log_step "Getting Android app logs"
    # Get PID of app
    local pid
    pid=$(adb shell pidof "$package" 2>/dev/null || echo "")

    if [ -n "$pid" ]; then
        adb logcat -d --pid="$pid" | tail -"$lines"
    else
        adb logcat -d | grep -i "$package" | tail -"$lines"
    fi
}

# Save logs to file
android_save_logs() {
    local output="${1:-$LOGS_DIR/android_logs_$(timestamp).txt}"
    local package="${2:-$ANDROID_PACKAGE}"

    ensure_dirs
    android_logs "$package" 500 > "$output"
    log_success "Android logs saved: $output"
}

# Clear logcat
android_clear_logs() {
    adb logcat -c
}

# ═══════════════════════════════════════════════════════════════
# Deep Links and Data
# ═══════════════════════════════════════════════════════════════

# Open URL/deep link in app
android_open_url() {
    local url="$1"
    log_step "Opening URL on Android: $url"
    adb shell am start -a android.intent.action.VIEW -d "'$url'"
}

# Set clipboard content
android_set_clipboard() {
    local content="$1"
    log_step "Setting Android clipboard"
    # Use input text as clipboard workaround
    adb shell "am broadcast -a clipper.set -e text '$content'" 2>/dev/null || \
    adb shell "input text '$content'"
}

# Send text input
android_input_text() {
    local text="$1"
    # Escape spaces for adb
    text="${text// /%s}"
    adb shell input text "$text"
}

# Send key event
android_key_event() {
    local key="$1"
    adb shell input keyevent "$key"
}

# ═══════════════════════════════════════════════════════════════
# Status Checks
# ═══════════════════════════════════════════════════════════════

# Check Android setup status
android_status() {
    log_subheader "Android Status"

    # Check adb
    if android_check_adb; then
        status_ok "adb installed"
    else
        status_fail "adb not found"
        return 1
    fi

    # Check emulator
    if command -v emulator &>/dev/null; then
        status_ok "emulator installed"
    else
        status_fail "emulator not found"
    fi

    # List AVDs
    local avds
    avds=$(android_list_avds 2>/dev/null || echo "")
    if [ -n "$avds" ]; then
        status_ok "AVDs available: $(echo "$avds" | tr '\n' ' ')"
    else
        status_warn "No AVDs configured"
    fi

    # Check running emulator
    if android_is_running; then
        local device_id
        device_id=$(android_get_emulator_id)
        status_ok "Emulator running: $device_id"
    else
        status_pending "Emulator not running"
    fi

    # Check APK
    local apk_path
    apk_path=$(android_find_apk 2>/dev/null || echo "")
    if [ -n "$apk_path" ]; then
        status_ok "APK found: $apk_path"
    else
        status_warn "APK not found (build required)"
    fi

    # Check if app is installed
    if android_is_running; then
        if android_is_installed; then
            status_ok "App installed on emulator"
        else
            status_pending "App not installed on emulator"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════
# Full Deploy Flow
# ═══════════════════════════════════════════════════════════════

# Deploy Android app (boot emulator, install, launch)
android_deploy() {
    log_header "Deploying Android App"

    # Check adb first
    if ! android_check_adb; then
        log_error "adb not found. Install Android SDK."
        echo ""
        echo "Install Android SDK from: https://developer.android.com/studio"
        echo "Or via package manager: sudo pacman -S android-tools"
        if confirm "Skip Android deployment?"; then
            return 0
        fi
        return 1
    fi

    # Boot emulator if not running
    if ! android_is_running; then
        local boot_result
        android_boot
        boot_result=$?

        if [ $boot_result -eq 2 ]; then
            # User chose to skip
            log_info "Skipping Android deployment"
            return 0
        elif [ $boot_result -ne 0 ]; then
            log_warn "Standard boot failed, trying software rendering..."
            if ! android_boot_sw; then
                log_error "Could not start emulator"
                echo ""
                echo "You can skip Android and continue with other platforms,"
                echo "or start the emulator manually:"
                echo "  just e2e-android-start"
                if confirm "Skip Android deployment?"; then
                    return 0
                fi
                return 1
            fi
        fi
    else
        log_info "Emulator already running"
    fi

    # Find and install APK
    local apk_path
    apk_path=$(android_find_apk)
    if [ -z "$apk_path" ]; then
        log_error "APK not found. Build it first with: just android"
        return 1
    fi

    android_install "$apk_path" || return 1

    # Launch app
    android_launch || return 1

    log_success "Android deployment complete"
}
