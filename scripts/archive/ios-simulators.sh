#!/bin/bash
# iOS Multi-Simulator Setup
#
# Launches multiple iOS simulators for testing.
# Each simulator acts as a separate device with isolated storage.
#
# OS Behavior:
#   macOS: Runs simulators locally (default), use --remote to prepare for remote connection
#   Windows/Linux: Remote mode only, prints connection info for macOS host

set -e

# Source common variables
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Use project-local cache for DerivedData (persists between runs)
DERIVED_DATA_DIR="$IOS_DERIVED_DATA_DIR"

# Ensure directories exist
ensure_dirs

# Remote mode flag (can be set via --remote flag on macOS)
REMOTE_MODE=false

# Default ports for remote iOS development
IOS_REMOTE_PORT=5037  # Default for device proxy

# Check OS and set mode
if [[ "$OS_TYPE" != "macos" ]]; then
    REMOTE_MODE=true
fi

# On non-macOS, we can't run simulators locally
check_local_capability() {
    if [[ "$OS_TYPE" != "macos" ]]; then
        print_error "Error: iOS Simulators can only run on macOS"
        echo ""
        echo "You are running on: $OS_TYPE"
        echo ""
        echo "For remote iOS development from $OS_TYPE:"
        echo "  1. On your macOS machine, run: $0 remote-server"
        echo "  2. Note the IP address and port displayed"
        echo "  3. Configure your IDE to connect to that address"
        echo ""
        print_connection_info "iOS Remote (this machine)" "$IOS_REMOTE_PORT"
        echo "Share this info with the macOS host to enable reverse connections."
        exit 1
    fi
}

# Check for Xcode (only on macOS)
if [[ "$OS_TYPE" == "macos" ]]; then
    if ! command -v xcrun &> /dev/null; then
        echo "Error: Xcode command line tools not found"
        echo "Please install Xcode from the App Store"
        exit 1
    fi
fi

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Current OS: $OS_TYPE"
    echo ""

    if [[ "$OS_TYPE" == "macos" ]]; then
        echo "Commands (Local - macOS):"
        echo "  list              List available simulators"
        echo "  booted            List currently running simulators"
        echo "  start <udid>      Start a specific simulator by UDID"
        echo "  start-one         Start one iPhone simulator and install app"
        echo "  start-pair        Start two iPhone simulators for testing"
        echo "  stop-all          Stop all running simulators"
        echo "  install [udid]    Build and install Vauchi app (uses booted sim if no udid)"
        echo "  launch [udid]     Launch the Vauchi app on simulator"
        echo "  cleanup           Stop simulators and clean Vauchi build artifacts"
        echo "  cleanup-caches    Remove simulator caches and unavailable devices (frees disk)"
        echo ""
        echo "Commands (Remote):"
        echo "  remote-server     Start this Mac as a remote iOS build server (prints connection info)"
        echo "  --remote <cmd>    Run any command and also print remote connection info"
        echo ""
        echo "Examples:"
        echo "  $0 list                   # List all simulators"
        echo "  $0 start-one              # Start one iPhone and install app"
        echo "  $0 start-pair             # Start two iPhones for testing"
        echo "  $0 booted                 # See running simulators"
        echo "  $0 install                # Build and install on booted simulator"
        echo "  $0 cleanup                # Clean up Vauchi artifacts"
        echo "  $0 cleanup-caches         # Free disk space (removes caches)"
        echo "  $0 remote-server          # Prepare for remote connections"
        echo "  $0 --remote start-one     # Start simulator + print remote info"
        echo ""
        echo "Quick Start (single simulator):"
        echo "  $0 start-one              # Starts simulator, builds, and installs app"
        echo ""
        echo "Multi-Device Testing Flow:"
        echo "  1. Run: $0 start-pair"
        echo "  2. In Xcode: Product -> Destination -> select first simulator"
        echo "  3. Build and run (Cmd+R)"
        echo "  4. Change destination to second simulator"
        echo "  5. Build and run again (Cmd+R)"
        echo "  6. Test exchange between the two simulators"
        echo ""
        echo "Remote Development (from Windows/Linux):"
        echo "  1. On this Mac: $0 remote-server"
        echo "  2. Note the IP and port displayed"
        echo "  3. On remote machine: configure IDE to connect to this Mac"
        echo ""
        echo "Note: Use 'open -n Simulator.app' to launch additional simulator windows"
    else
        echo "NOTE: iOS Simulators require macOS. This script provides remote connection info."
        echo ""
        echo "Commands:"
        echo "  connection-info   Show connection info to provide to macOS host"
        echo "  help              Show this help message"
        echo ""
        echo "Remote Development Setup:"
        echo "  1. On your macOS machine, run the iOS simulator script"
        echo "  2. Use 'remote-server' command to get connection details"
        echo "  3. Connect from this machine using the provided IP/port"
        echo ""
        print_connection_info "iOS Remote Client (this machine)" "$IOS_REMOTE_PORT"
    fi
    exit 1
}

list_simulators() {
    echo "Available iOS Simulators:"
    xcrun simctl list devices available | grep -E "iPhone|iPad"
}

list_booted() {
    echo "Running Simulators:"
    xcrun simctl list devices | grep "Booted" || echo "  (none)"
}

start_simulator() {
    local udid="$1"
    if [ -z "$udid" ]; then
        echo "Error: Simulator UDID required"
        echo "Use '$0 list' to see available simulators"
        exit 1
    fi

    echo "Starting simulator: $udid"
    xcrun simctl boot "$udid" 2>/dev/null || echo "Simulator may already be booted"

    # Open Simulator app
    if [ -d "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" ]; then
        open "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"
    else
        open -a "$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || \
        echo "Note: Could not open Simulator app automatically. Please open it manually."
    fi
}

get_first_iphone_udid() {
    # Get one iPhone simulator (prefer Pro models, fallback to any iPhone)
    local sim=$(xcrun simctl list devices available | grep -E "iPhone [0-9]+ Pro[^M]" | grep -v "Booted" | head -1)

    if [ -z "$sim" ]; then
        # Fallback: get any available iPhone simulator
        sim=$(xcrun simctl list devices available | grep "iPhone" | grep -v "Booted" | head -1)
    fi

    if [ -z "$sim" ]; then
        echo ""
        return 1
    fi

    echo "$sim" | grep -oE '[A-Fa-f0-9-]{36}'
}

get_booted_udid() {
    xcrun simctl list devices | grep "Booted" | head -1 | grep -oE '[A-Fa-f0-9-]{36}'
}

open_simulator_app() {
    if [ -d "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" ]; then
        open "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"
    else
        open -a "$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || \
        echo "Note: Could not open Simulator app automatically. Please open it manually."
    fi
}

start_one() {
    echo "Starting one iPhone simulator for testing..."
    echo ""

    local udid=$(get_first_iphone_udid)

    if [ -z "$udid" ]; then
        echo "Error: No available iPhone simulators found"
        echo "Create one in Xcode: Window -> Devices and Simulators -> Simulators -> +"
        exit 1
    fi

    local name=$(xcrun simctl list devices available | grep "$udid" | sed 's/(.*//' | xargs)

    echo "Starting simulator: $name ($udid)"
    xcrun simctl boot "$udid" 2>/dev/null || echo "Simulator may already be booted"

    # Wait for simulator to boot
    echo "Waiting for simulator to boot..."
    local count=0
    while ! xcrun simctl list devices | grep "$udid" | grep -q "Booted"; do
        sleep 1
        count=$((count + 1))
        if [ $count -gt 30 ]; then
            echo "Warning: Simulator taking longer than expected to boot"
            break
        fi
    done

    open_simulator_app

    echo ""
    echo "Simulator started: $name"
    echo ""
    echo "Building and installing Vauchi app..."
    install_app "$udid"

    echo ""
    echo "Launching Vauchi app..."
    launch_app "$udid"

    echo ""
    echo "Done! Vauchi is running on $name"
}

start_pair() {
    echo "Starting pair of iPhone simulators for testing..."
    echo ""

    # Get two iPhone simulators (prefer Pro models, fallback to any iPhone)
    # Try iPhone Pro first, then any iPhone
    local sims=$(xcrun simctl list devices available | grep -E "iPhone [0-9]+ Pro[^M]" | grep -v "Booted" | head -2)

    if [ -z "$sims" ] || [ $(echo "$sims" | wc -l) -lt 2 ]; then
        # Fallback: get any available iPhone simulators
        sims=$(xcrun simctl list devices available | grep "iPhone" | grep -v "Booted" | head -2)
    fi

    if [ -z "$sims" ]; then
        echo "Error: No available iPhone simulators found"
        echo "Create them in Xcode: Window -> Devices and Simulators -> Simulators -> +"
        exit 1
    fi

    # Extract UDIDs (handle both uppercase and lowercase hex)
    local udid1=$(echo "$sims" | head -1 | grep -oE '[A-Fa-f0-9-]{36}')
    local udid2=$(echo "$sims" | tail -1 | grep -oE '[A-Fa-f0-9-]{36}')

    local name1=$(echo "$sims" | head -1 | sed 's/(.*//' | xargs)
    local name2=$(echo "$sims" | tail -1 | sed 's/(.*//' | xargs)

    if [ "$udid1" = "$udid2" ]; then
        echo "Warning: Only one iPhone simulator found"
        echo "Create another in Xcode for proper multi-device testing"
        udid2=""
        name2=""
    fi

    echo "Starting first simulator: $name1"
    xcrun simctl boot "$udid1" 2>/dev/null || true

    if [ -n "$udid2" ]; then
        echo "Starting second simulator: $name2"
        xcrun simctl boot "$udid2" 2>/dev/null || true
    fi

    open_simulator_app

    echo ""
    echo "Simulators started!"
    list_booted

    echo ""
    echo "Next Steps:"
    echo "  1. In Xcode, select the first simulator as destination"
    echo "  2. Build and run (Cmd+R)"
    echo "  3. Change destination to second simulator"
    echo "  4. Build and run again"
    echo "  5. Test exchange between simulators"
}

stop_all() {
    echo "Stopping all simulators..."
    xcrun simctl shutdown all
    echo "All simulators stopped"
}

install_app() {
    local udid="$1"

    # If no UDID provided, use the first booted simulator
    if [ -z "$udid" ]; then
        udid=$(get_booted_udid)
        if [ -z "$udid" ]; then
            echo "Error: No booted simulator found. Start a simulator first or provide a UDID."
            echo "  $0 start-one     # Start simulator and install"
            echo "  $0 install <udid> # Install on specific simulator"
            exit 1
        fi
        echo "Using booted simulator: $udid"
    fi

    echo "Building Vauchi for simulator..."
    cd "$IOS_DIR"

    # Build for simulator and capture result
    local build_log=$(mktemp)
    set +e
    xcodebuild -scheme Vauchi \
        -destination "id=$udid" \
        -configuration Debug \
        -derivedDataPath "$DERIVED_DATA_DIR" \
        build 2>&1 | tee "$build_log"
    local build_result=${PIPESTATUS[0]}
    set -e

    # Show errors and check result
    if grep -q "BUILD FAILED" "$build_log" || [ $build_result -ne 0 ]; then
        echo ""
        echo "Build failed! Errors:"
        grep -E "error:" "$build_log" | head -10
        rm -f "$build_log"
        exit 1
    fi
    rm -f "$build_log"

    # Get app path from our controlled DerivedData location
    local app_path=$(find "$DERIVED_DATA_DIR" -name "Vauchi.app" -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)

    if [ -z "$app_path" ]; then
        # Fallback to default DerivedData location
        app_path=$(find ~/Library/Developer/Xcode/DerivedData -name "Vauchi.app" -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)
    fi

    if [ -z "$app_path" ]; then
        echo "Error: Built app not found. Build may have failed."
        exit 1
    fi

    echo "Installing $app_path to simulator..."
    xcrun simctl install "$udid" "$app_path"
    echo "App installed successfully!"
}

launch_app() {
    local udid="$1"

    # If no UDID provided, use the first booted simulator
    if [ -z "$udid" ]; then
        udid=$(get_booted_udid)
        if [ -z "$udid" ]; then
            echo "Error: No booted simulator found"
            exit 1
        fi
    fi

    # Get bundle identifier from Info.plist
    local bundle_id="com.vauchi.app"

    # Try to get actual bundle ID from built app
    local app_path=$(find "$DERIVED_DATA_DIR" -name "Vauchi.app" -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)
    if [ -n "$app_path" ] && [ -f "$app_path/Info.plist" ]; then
        local plist_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Info.plist" 2>/dev/null)
        if [ -n "$plist_id" ]; then
            bundle_id="$plist_id"
        fi
    fi

    echo "Launching $bundle_id on simulator $udid..."
    xcrun simctl launch "$udid" "$bundle_id" || {
        echo "Failed to launch. The app may not be installed."
        echo "Run: $0 install $udid"
        exit 1
    }
    echo "App launched!"
}

cleanup() {
    echo "Cleaning up Vauchi iOS artifacts..."

    # Stop all simulators first
    echo "Stopping all simulators..."
    xcrun simctl shutdown all 2>/dev/null || true

    # Clean project-local cache/ios directory
    if [ -d "$IOS_CACHE_DIR" ]; then
        echo "Cleaning project cache/ios directory..."
        rm -rf "$IOS_CACHE_DIR"/*
        mkdir -p "$DERIVED_DATA_DIR"
    fi

    # Clean legacy locations
    if [ -d "$IOS_DIR/.build" ]; then
        echo "Removing legacy ios/.build directory..."
        rm -rf "$IOS_DIR/.build"
    fi
    if [ -d "$TMP_DIR/ios" ]; then
        rm -rf "$TMP_DIR/ios"
    fi

    # Find and remove Vauchi from global DerivedData
    local vauchi_derived=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "Vauchi-*" -type d 2>/dev/null)
    if [ -n "$vauchi_derived" ]; then
        echo "Removing Vauchi from global DerivedData..."
        echo "$vauchi_derived" | xargs rm -rf
    fi

    # Uninstall Vauchi app from all simulators
    echo "Uninstalling Vauchi from simulators..."
    for udid in $(xcrun simctl list devices -j | grep -oE '"udid" : "[^"]+"' | cut -d'"' -f4); do
        xcrun simctl uninstall "$udid" "com.vauchi.app" 2>/dev/null || true
    done

    echo ""
    echo "Cleanup complete!"
}

cleanup_caches() {
    echo "Cleaning iOS simulator caches to free disk space..."
    echo ""

    local total_freed=0

    # Stop all simulators first
    echo "Stopping all simulators..."
    xcrun simctl shutdown all 2>/dev/null || true
    sleep 2

    # Remove unavailable simulators (old iOS versions, etc.)
    echo ""
    echo "Removing unavailable simulators..."
    local before=$(du -sk ~/Library/Developer/CoreSimulator/Devices 2>/dev/null | awk '{print $1}')
    xcrun simctl delete unavailable 2>/dev/null || true
    local after=$(du -sk ~/Library/Developer/CoreSimulator/Devices 2>/dev/null | awk '{print $1}')
    local freed=$((before - after))
    if [ "$freed" -gt 0 ]; then
        echo "  Freed: $((freed / 1024)) MB"
        total_freed=$((total_freed + freed))
    fi

    # Clear CoreSimulator caches
    local cache_dir="$HOME/Library/Developer/CoreSimulator/Caches"
    if [ -d "$cache_dir" ]; then
        echo ""
        echo "Clearing CoreSimulator caches..."
        local cache_size=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
        rm -rf "$cache_dir"/*
        echo "  Freed: $((cache_size / 1024)) MB"
        total_freed=$((total_freed + cache_size))
    fi

    # Clear simulator logs
    local log_dir="$HOME/Library/Logs/CoreSimulator"
    if [ -d "$log_dir" ]; then
        echo ""
        echo "Clearing simulator logs..."
        local log_size=$(du -sk "$log_dir" 2>/dev/null | awk '{print $1}')
        rm -rf "$log_dir"/*
        echo "  Freed: $((log_size / 1024)) MB"
        total_freed=$((total_freed + log_size))
    fi

    # Optionally clear global DerivedData (with confirmation)
    local derived_dir="$HOME/Library/Developer/Xcode/DerivedData"
    if [ -d "$derived_dir" ]; then
        local derived_size=$(du -sk "$derived_dir" 2>/dev/null | awk '{print $1}')
        echo ""
        echo "Global DerivedData: $((derived_size / 1024)) MB"
        echo "  To clear ALL DerivedData (all Xcode projects): rm -rf ~/Library/Developer/Xcode/DerivedData/*"
    fi

    echo ""
    echo "========================================"
    echo "Total freed: $((total_freed / 1024)) MB"
    echo "========================================"
    echo ""
    echo "Current disk usage:"
    df -h / | tail -1 | awk '{print "  Available: " $4 " (" $5 " used)"}'
}

# Remote server mode - prints connection info for remote clients
remote_server() {
    check_local_capability

    echo ""
    print_success "iOS Remote Development Server"
    echo ""
    echo "This Mac is ready to serve as an iOS development host."
    echo ""

    local local_ip=$(get_local_ip)

    print_connection_info "iOS Simulator Host" "$IOS_REMOTE_PORT"

    echo "Available Simulators:"
    list_simulators
    echo ""

    echo "Running Simulators:"
    list_booted
    echo ""

    echo "Instructions for remote clients (Windows/Linux):"
    echo "  1. Ensure both machines are on the same network"
    echo "  2. On the remote machine, configure your IDE/tooling to connect to:"
    echo "     Host: $local_ip"
    echo "     Port: $IOS_REMOTE_PORT"
    echo "  3. For SSH tunneling (recommended):"
    echo "     ssh -L $IOS_REMOTE_PORT:localhost:$IOS_REMOTE_PORT user@$local_ip"
    echo ""
    echo "Xcode Build Server (for remote builds):"
    echo "  The Xcode build can be triggered remotely via SSH:"
    echo "    ssh user@$local_ip 'cd $IOS_DIR && xcodebuild -scheme Vauchi build'"
    echo ""
}

# Show connection info for non-macOS clients
show_connection_info() {
    print_connection_info "iOS Remote Client" "$IOS_REMOTE_PORT"
    echo "Provide this information to the macOS host for reverse connections."
    echo ""
    echo "To connect to a macOS iOS build server:"
    echo "  1. Get the macOS machine's IP address (run 'remote-server' on Mac)"
    echo "  2. SSH tunnel: ssh -L $IOS_REMOTE_PORT:localhost:$IOS_REMOTE_PORT user@<mac-ip>"
    echo "  3. Configure your tooling to use localhost:$IOS_REMOTE_PORT"
}

# Parse --remote flag
if [[ "${1:-}" == "--remote" ]]; then
    REMOTE_MODE=true
    shift
fi

# Handle commands based on OS
case "${1:-}" in
    # Remote commands (available on all OS)
    remote-server)
        remote_server
        ;;
    connection-info)
        show_connection_info
        ;;

    # Local commands (macOS only)
    list)
        check_local_capability
        list_simulators
        [[ "$REMOTE_MODE" == true ]] && print_connection_info "iOS Simulator Host" "$IOS_REMOTE_PORT"
        ;;
    booted)
        check_local_capability
        list_booted
        [[ "$REMOTE_MODE" == true ]] && print_connection_info "iOS Simulator Host" "$IOS_REMOTE_PORT"
        ;;
    start)
        check_local_capability
        start_simulator "$2"
        [[ "$REMOTE_MODE" == true ]] && print_connection_info "iOS Simulator Host" "$IOS_REMOTE_PORT"
        ;;
    start-one)
        check_local_capability
        start_one
        [[ "$REMOTE_MODE" == true ]] && print_connection_info "iOS Simulator Host" "$IOS_REMOTE_PORT"
        ;;
    start-pair)
        check_local_capability
        start_pair
        [[ "$REMOTE_MODE" == true ]] && print_connection_info "iOS Simulator Host" "$IOS_REMOTE_PORT"
        ;;
    stop-all)
        check_local_capability
        stop_all
        ;;
    install)
        check_local_capability
        install_app "$2"
        [[ "$REMOTE_MODE" == true ]] && print_connection_info "iOS Simulator Host" "$IOS_REMOTE_PORT"
        ;;
    launch)
        check_local_capability
        launch_app "$2"
        [[ "$REMOTE_MODE" == true ]] && print_connection_info "iOS Simulator Host" "$IOS_REMOTE_PORT"
        ;;
    cleanup)
        check_local_capability
        cleanup
        ;;
    cleanup-caches)
        check_local_capability
        cleanup_caches
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage
        ;;
esac
