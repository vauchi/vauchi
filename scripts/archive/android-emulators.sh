#!/bin/bash
# Android Multi-Emulator Setup
#
# Creates and launches multiple Android emulators for testing.
# Each emulator acts as a separate device with isolated storage.
#
# OS Behavior:
#   macOS: Prompts for remote device IP (virtual instance or real device)
#          Can also run local emulators
#   Windows/Linux: Runs local emulators, can also run in accept-remote mode
#                  which prints connection info for remote ADB connections

set -e

# Source common variables
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Ensure directories exist
ensure_dirs

# Save original env vars to restore later
_ORIG_ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-}"

# Use project-local cache for AVDs (persists between runs)
export ANDROID_AVD_HOME="$ANDROID_AVD_DIR"

# Restore env vars on exit
restore_env() {
    if [ -n "$_ORIG_ANDROID_AVD_HOME" ]; then
        export ANDROID_AVD_HOME="$_ORIG_ANDROID_AVD_HOME"
    else
        unset ANDROID_AVD_HOME
    fi
}
trap restore_env EXIT

# Default ADB port for remote connections
ADB_REMOTE_PORT=5555

# Remote IP for connecting to remote Android device/emulator (macOS mode)
REMOTE_ANDROID_IP=""

# Accept remote mode flag (Windows/Linux)
ACCEPT_REMOTE_MODE=false

# Check for Android SDK
if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
    echo "Error: ANDROID_HOME or ANDROID_SDK_ROOT not set"
    echo "Please install Android Studio and set up the SDK"
    exit 1
fi

SDK_ROOT="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"

# Use SDK's own tools to avoid Homebrew conflicts
EMULATOR="$SDK_ROOT/emulator/emulator"
AVDMANAGER="$ANDROID_CMD_LINE_TOOLS_HOME/avdmanager"
SDKMANAGER="$ANDROID_CMD_LINE_TOOLS_HOME/sdkmanager"
ADB="$SDK_ROOT/platform-tools/adb"

# Fallback to PATH if SDK tools don't exist
[ ! -f "$EMULATOR" ] && EMULATOR="emulator"
[ ! -f "$AVDMANAGER" ] && AVDMANAGER="avdmanager"
[ ! -f "$ADB" ] && ADB="adb"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Current OS: $OS_TYPE"
    echo ""
    echo "Commands (Local Emulators):"
    echo "  list              List available AVDs"
    echo "  create <name>     Create a new AVD for testing"
    echo "  start <name>      Start an emulator"
    echo "  start-all         Start all test emulators (alice, bob)"
    echo "  stop-all          Stop all running emulators"
    echo "  install <name>    Install Vauchi app on emulator"
    echo "  setup             Create alice and bob AVDs if they don't exist"
    echo "  cleanup           Stop emulators and delete test AVDs"
    echo ""
    echo "Commands (Remote):"

    if [[ "$OS_TYPE" == "macos" ]]; then
        echo "  connect <ip>      Connect to remote Android device/emulator via ADB"
        echo "  connect-prompt    Interactively prompt for remote IP and connect"
        echo "  disconnect        Disconnect from remote device"
        echo "  devices           List all connected devices (local and remote)"
        echo ""
        echo "Examples:"
        echo "  $0 setup                    # Create test AVDs"
        echo "  $0 start-all                # Start alice and bob emulators"
        echo "  $0 install vauchi_alice     # Install app on alice"
        echo "  $0 connect 192.168.1.100    # Connect to remote Android device"
        echo "  $0 connect-prompt           # Prompt for remote IP address"
        echo "  $0 devices                  # List all devices"
        echo "  $0 cleanup                  # Remove all test AVDs"
        echo ""
        echo "Remote Android Device Connection (from macOS):"
        echo "  1. On the remote machine (Windows/Linux), run: $0 accept-remote"
        echo "  2. Note the IP address displayed"
        echo "  3. On this Mac, run: $0 connect <remote-ip>"
        echo "  4. Or use: $0 connect-prompt to enter IP interactively"
    else
        echo "  accept-remote     Enable ADB over network and print connection info"
        echo "  connection-info   Show this machine's connection info"
        echo "  devices           List all connected devices (local and remote)"
        echo ""
        echo "Examples:"
        echo "  $0 setup                  # Create test AVDs"
        echo "  $0 start-all              # Start alice and bob emulators"
        echo "  $0 accept-remote          # Enable remote connections"
        echo "  $0 install vauchi_alice   # Install app on alice"
        echo "  $0 cleanup                # Remove all test AVDs"
        echo ""
        echo "Accepting Remote Connections (Windows/Linux):"
        echo "  1. Start an emulator: $0 start-all"
        echo "  2. Enable remote: $0 accept-remote"
        echo "  3. Share the displayed IP with the macOS developer"
        echo "  4. They can then connect using: $0 connect <your-ip>"
    fi

    echo ""
    echo "Multi-Device Testing Flow:"
    echo "  1. Run: $0 setup"
    echo "  2. Run: $0 start-all"
    echo "  3. Deploy app to both emulators from Android Studio"
    echo "     (Ctrl+Click to select multiple devices in Run dialog)"
    echo "  4. Test exchange: Alice generates QR, Bob scans it"
    echo "  5. Run: $0 cleanup        # When done testing"
    exit 1
}

list_avds() {
    echo "Available AVDs:"
    "$EMULATOR" -list-avds
}

create_avd() {
    local name="$1"
    if [ -z "$name" ]; then
        echo "Error: AVD name required"
        exit 1
    fi

    echo "Creating AVD: $name"

    # Detect architecture - Apple Silicon needs arm64-v8a, Intel needs x86_64
    # Use sysctl to detect Apple Silicon even when running under Rosetta
    local ARCH
    if [ "$(uname -s)" = "Darwin" ]; then
        if sysctl -n hw.optional.arm64 2>/dev/null | grep -q "1"; then
            ARCH="arm64-v8a"
        elif [ "$(uname -m)" = "arm64" ]; then
            ARCH="arm64-v8a"
        else
            ARCH="x86_64"
        fi
    elif [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
        ARCH="arm64-v8a"
    else
        ARCH="x86_64"
    fi

    echo "Detected architecture: $ARCH"

    # Find an available system image - try both architectures if needed
    local SYSTEM_IMAGE=""
    local found=false

    # Check for available images in order of preference
    for arch in "$ARCH" "arm64-v8a" "x86_64"; do
        for api in "android-35" "android-34"; do
            for variant in "google_apis" "google_apis_playstore"; do
                if [ -d "$SDK_ROOT/system-images/$api/$variant/$arch" ]; then
                    SYSTEM_IMAGE="system-images;$api;$variant;$arch"
                    found=true
                    echo "Found system image: $SYSTEM_IMAGE"
                    break 3
                fi
            done
        done
    done

    if [ "$found" != true ]; then
        # Default to android-35 google_apis for the architecture
        SYSTEM_IMAGE="system-images;android-35;google_apis;$ARCH"
        echo "No local image found. Downloading: $SYSTEM_IMAGE"
        "$SDKMANAGER" "$SYSTEM_IMAGE" || {
            echo "Error: Failed to download system image."
            echo "Please install a system image manually via Android Studio SDK Manager."
            exit 1
        }
    fi

    # Create AVD
    echo "no" | "$AVDMANAGER" create avd \
        --name "$name" \
        --package "$SYSTEM_IMAGE" \
        --device "pixel_6" \
        --force

    echo "AVD '$name' created successfully"
}

start_emulator() {
    local name="$1"
    if [ -z "$name" ]; then
        echo "Error: AVD name required"
        exit 1
    fi

    echo "Starting emulator: $name"

    # Check for Wayland session - emulator needs XWayland (xcb) as it lacks native Wayland support
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        print_warning "Wayland session detected. Using XWayland (xcb) for emulator display."
        export QT_QPA_PLATFORM=xcb
    fi

    "$EMULATOR" -avd "$name" -no-snapshot-load &
    echo "Emulator '$name' starting in background (PID: $!)"
}

start_all() {
    echo "Starting test emulators..."

    # Check if AVDs exist, create them if not
    existing=$("$EMULATOR" -list-avds 2>/dev/null || echo "")

    if ! echo "$existing" | grep -q "vauchi_alice" || ! echo "$existing" | grep -q "vauchi_bob"; then
        echo "Test AVDs not found. Running setup first..."
        setup_test_avds
    fi

    start_emulator "vauchi_alice"
    sleep 2
    start_emulator "vauchi_bob"
    echo ""
    echo "Both emulators starting. Wait for them to boot, then deploy the app."
    echo "In Android Studio: Run -> Select Deployment Target -> Hold Ctrl and click both devices"
}

install_app() {
    local avd_name="$1"
    if [ -z "$avd_name" ]; then
        echo "Error: AVD name required"
        exit 1
    fi

    # Get serial for the AVD
    local serial=$("$ADB" devices | grep -v "List" | grep "emulator" | head -1 | awk '{print $1}')

    if [ -z "$serial" ]; then
        echo "Error: No running emulator found"
        exit 1
    fi

    echo "Installing to $serial..."
    cd "$ANDROID_DIR"
    ./gradlew installDebug -Pandroid.injected.build.api=34
}

setup_test_avds() {
    echo "Setting up test AVDs..."

    # Check if AVDs exist
    existing=$("$EMULATOR" -list-avds 2>/dev/null || echo "")

    if ! echo "$existing" | grep -q "vauchi_alice"; then
        create_avd "vauchi_alice"
    else
        echo "vauchi_alice already exists"
    fi

    if ! echo "$existing" | grep -q "vauchi_bob"; then
        create_avd "vauchi_bob"
    else
        echo "vauchi_bob already exists"
    fi

    echo ""
    echo "Setup complete! Available test AVDs:"
    list_avds
}

stop_all() {
    echo "Stopping all running emulators..."

    # Get list of running emulator serials
    local emulators=$("$ADB" devices | grep "emulator-" | awk '{print $1}')

    if [ -z "$emulators" ]; then
        echo "No running emulators found."
        return 0
    fi

    for serial in $emulators; do
        echo "Stopping $serial..."
        "$ADB" -s "$serial" emu kill 2>/dev/null || true
    done

    # Wait for emulators to terminate
    sleep 2
    echo "All emulators stopped."
}

cleanup() {
    echo "Cleaning up test AVDs and emulators..."

    # Stop any running emulators first
    stop_all

    # Delete test AVDs
    existing=$("$EMULATOR" -list-avds 2>/dev/null || echo "")

    if echo "$existing" | grep -q "vauchi_alice"; then
        echo "Deleting AVD: vauchi_alice"
        "$AVDMANAGER" delete avd --name "vauchi_alice" 2>/dev/null || true
    fi

    if echo "$existing" | grep -q "vauchi_bob"; then
        echo "Deleting AVD: vauchi_bob"
        "$AVDMANAGER" delete avd --name "vauchi_bob" 2>/dev/null || true
    fi

    # Clean up project-local cache/android directory
    if [ -d "$ANDROID_CACHE_DIR" ]; then
        echo "Cleaning project cache/android directory..."
        rm -rf "$ANDROID_CACHE_DIR"/*
        mkdir -p "$ANDROID_AVD_DIR"
    fi

    # Also clean any orphaned AVDs in default location (legacy)
    local default_avd_home="$HOME/.android/avd"
    if [ -d "$default_avd_home" ]; then
        rm -rf "$default_avd_home/vauchi_alice.avd" 2>/dev/null || true
        rm -rf "$default_avd_home/vauchi_bob.avd" 2>/dev/null || true
        rm -f "$default_avd_home/vauchi_alice.ini" 2>/dev/null || true
        rm -f "$default_avd_home/vauchi_bob.ini" 2>/dev/null || true
    fi

    # Clean legacy tmp/android location
    if [ -d "$TMP_DIR/android" ]; then
        rm -rf "$TMP_DIR/android"
    fi

    echo ""
    echo "Cleanup complete!"
    echo "Remaining AVDs:"
    list_avds
}

# ============================================================================
# Remote Connection Functions
# ============================================================================

# Connect to a remote Android device/emulator (primarily for macOS)
connect_remote() {
    local remote_ip="$1"

    if [ -z "$remote_ip" ]; then
        print_error "Error: Remote IP address required"
        echo "Usage: $0 connect <ip-address>"
        echo "Example: $0 connect 192.168.1.100"
        exit 1
    fi

    echo ""
    print_info "Connecting to remote Android device at $remote_ip:$ADB_REMOTE_PORT..."
    echo ""

    # Try to connect
    if "$ADB" connect "$remote_ip:$ADB_REMOTE_PORT"; then
        print_success "Connected successfully!"
        echo ""
        echo "Connected devices:"
        "$ADB" devices -l
    else
        print_error "Failed to connect to $remote_ip:$ADB_REMOTE_PORT"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Ensure the remote device has ADB over network enabled"
        echo "  2. On the remote machine, run: $0 accept-remote"
        echo "  3. Check firewall settings allow port $ADB_REMOTE_PORT"
        echo "  4. Verify both machines are on the same network"
        exit 1
    fi
}

# Interactive prompt for remote IP (macOS)
connect_prompt() {
    echo ""
    print_info "Remote Android Device Connection"
    echo ""
    echo "Enter the IP address of the remote Android device or emulator."
    echo "The remote machine should have run '$0 accept-remote' first."
    echo ""

    read -p "Remote IP address: " remote_ip

    if [ -z "$remote_ip" ]; then
        print_error "No IP address provided"
        exit 1
    fi

    # Validate IP format (basic check)
    if ! echo "$remote_ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        print_warning "Warning: '$remote_ip' doesn't look like a valid IP address"
        read -p "Continue anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    connect_remote "$remote_ip"
}

# Disconnect from remote device
disconnect_remote() {
    echo ""
    print_info "Disconnecting from remote devices..."
    echo ""

    # Get list of connected remote devices
    local remotes=$("$ADB" devices | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:" | awk '{print $1}')

    if [ -z "$remotes" ]; then
        echo "No remote devices connected."
        return 0
    fi

    for remote in $remotes; do
        echo "Disconnecting from $remote..."
        "$ADB" disconnect "$remote" 2>/dev/null || true
    done

    print_success "Disconnected from all remote devices."
    echo ""
    echo "Remaining devices:"
    "$ADB" devices -l
}

# Enable ADB over network for remote connections (Windows/Linux)
accept_remote() {
    echo ""
    print_success "Android Remote Connection Server"
    echo ""

    local local_ip=$(get_local_ip)

    # Check for running emulators/devices
    local devices=$("$ADB" devices | grep -v "List" | grep -E "emulator-|device$" | head -1)

    if [ -z "$devices" ]; then
        print_warning "Warning: No Android devices or emulators detected."
        echo ""
        echo "Start an emulator first:"
        echo "  $0 start-all"
        echo ""
        echo "Or connect a physical device via USB."
        echo ""
    fi

    # For emulators, they already listen on a port, we just need to share info
    # For physical devices connected via USB, we need to enable tcpip mode
    local usb_device=$("$ADB" devices | grep -v "List" | grep "device$" | grep -v "emulator" | head -1 | awk '{print $1}')

    if [ -n "$usb_device" ]; then
        echo "Physical device detected: $usb_device"
        echo "Enabling ADB over network..."
        "$ADB" -s "$usb_device" tcpip "$ADB_REMOTE_PORT" 2>/dev/null || true
        sleep 2
        print_success "ADB over network enabled on port $ADB_REMOTE_PORT"
    fi

    # Print connection info
    print_connection_info "Android ADB Server" "$ADB_REMOTE_PORT"

    echo "Instructions for remote developers (macOS):"
    echo "  1. On the remote Mac, run:"
    echo "     $0 connect $local_ip"
    echo ""
    echo "  2. Or use interactive mode:"
    echo "     $0 connect-prompt"
    echo ""

    # List current devices
    echo "Currently connected devices:"
    "$ADB" devices -l
    echo ""

    # For emulators, show their specific ports
    local emulators=$("$ADB" devices | grep "emulator-" | awk '{print $1}')
    if [ -n "$emulators" ]; then
        echo "Emulator ports (can also connect directly):"
        for emu in $emulators; do
            local port=$(echo "$emu" | sed 's/emulator-//')
            echo "  $emu -> $local_ip:$port"
        done
        echo ""
    fi

    echo "Firewall: Ensure port $ADB_REMOTE_PORT is open for incoming connections."
}

# Show connection info for this machine
show_connection_info() {
    print_connection_info "Android ADB" "$ADB_REMOTE_PORT"

    echo "Current devices:"
    "$ADB" devices -l
}

# List all connected devices
list_devices() {
    echo ""
    echo "Connected Android Devices:"
    echo ""
    "$ADB" devices -l
    echo ""

    # Categorize devices
    local local_emulators=$("$ADB" devices | grep "emulator-" | wc -l | tr -d ' ')
    local usb_devices=$("$ADB" devices | grep -v "List" | grep "device$" | grep -v "emulator" | grep -v ":" | wc -l | tr -d ' ')
    local remote_devices=$("$ADB" devices | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:" | wc -l | tr -d ' ')

    echo "Summary:"
    echo "  Local emulators: $local_emulators"
    echo "  USB devices: $usb_devices"
    echo "  Remote devices: $remote_devices"
}

case "${1:-}" in
    # Local emulator commands
    list)
        list_avds
        ;;
    create)
        create_avd "$2"
        ;;
    start)
        start_emulator "$2"
        ;;
    start-all)
        start_all
        ;;
    install)
        install_app "$2"
        ;;
    setup)
        setup_test_avds
        ;;
    stop-all)
        stop_all
        ;;
    cleanup)
        cleanup
        ;;

    # Remote connection commands
    connect)
        connect_remote "$2"
        ;;
    connect-prompt)
        connect_prompt
        ;;
    disconnect)
        disconnect_remote
        ;;
    accept-remote)
        accept_remote
        ;;
    connection-info)
        show_connection_info
        ;;
    devices)
        list_devices
        ;;

    help|--help|-h)
        usage
        ;;
    *)
        usage
        ;;
esac
