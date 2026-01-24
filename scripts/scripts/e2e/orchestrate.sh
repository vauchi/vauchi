#!/bin/bash
# E2E Testing Orchestrator
#
# Unified cross-platform E2E testing for iOS (macOS VM) and Android (local).
#
# Usage:
#   ./orchestrate.sh status       # Check status of all components
#   ./orchestrate.sh deploy       # Deploy apps to all devices
#   ./orchestrate.sh deploy-ios   # Deploy iOS app to macOS VM simulator
#   ./orchestrate.sh deploy-android # Deploy Android APK to local emulator
#   ./orchestrate.sh test         # Run E2E test checklist
#   ./orchestrate.sh relay        # Start local TLS relay
#   ./orchestrate.sh relay-setup  # Setup local CA for TLS
#   ./orchestrate.sh screenshot   # Take screenshots from both devices
#   ./orchestrate.sh logs         # Collect logs from both devices
#   ./orchestrate.sh setup        # Initial setup instructions

set -e

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/ios.sh"
source "$SCRIPT_DIR/lib/android.sh"
source "$SCRIPT_DIR/lib/relay.sh"
source "$SCRIPT_DIR/lib/cli.sh"
source "$SCRIPT_DIR/lib/tui.sh"
source "$SCRIPT_DIR/lib/desktop.sh"

# ═══════════════════════════════════════════════════════════════
# Commands
# ═══════════════════════════════════════════════════════════════

cmd_status() {
    log_header "E2E Testing Status"

    # Track what needs action
    local suggestions=()

    relay_status
    cli_status
    tui_status
    desktop_status
    ios_status
    android_status

    # Collect suggestions based on status
    echo ""
    log_subheader "Suggested Actions"

    # Check CLI
    if ! cli_is_built 2>/dev/null; then
        suggestions+=("Build CLI: just build-cli")
    fi

    # Check TUI
    if ! tui_is_built 2>/dev/null; then
        suggestions+=("Build TUI: just build")
    fi

    # Check Android app installation
    if android_is_running 2>/dev/null && ! android_is_installed 2>/dev/null; then
        suggestions+=("Install Android app: just e2e-deploy-android")
    fi

    # Check if Android emulator is not running
    if ! android_is_running 2>/dev/null; then
        suggestions+=("Start Android emulator: just e2e-android-start")
    fi

    # Check iOS
    if check_ssh_mac 2>/dev/null; then
        if ! ios_is_booted 2>/dev/null; then
            suggestions+=("Boot iOS simulator: just e2e-deploy-ios")
        elif ! ios_is_installed 2>/dev/null; then
            suggestions+=("Install iOS app: just e2e-deploy-ios")
        fi
    fi

    # Print suggestions or ready message
    if [ ${#suggestions[@]} -eq 0 ]; then
        status_ok "All platforms ready!"
        echo ""
        echo "  Run a test scenario: just e2e-scenario"
        echo "  Or run the checklist: just e2e-test-mobile"
    else
        for suggestion in "${suggestions[@]}"; do
            echo "  → $suggestion"
        done
        echo ""
        echo "  Or deploy everything: just e2e-deploy"
    fi
    echo ""
}

cmd_deploy() {
    log_header "Deploying to All Devices"

    local ios_result=0
    local android_result=0

    # Deploy to iOS (in background)
    log_info "Starting iOS deployment..."
    (ios_deploy) &
    local ios_pid=$!

    # Deploy to Android
    log_info "Starting Android deployment..."
    android_deploy || android_result=$?

    # Wait for iOS
    wait $ios_pid || ios_result=$?

    # Summary
    echo ""
    log_header "Deployment Summary"

    if [ $ios_result -eq 0 ]; then
        status_ok "iOS deployment"
    else
        status_fail "iOS deployment"
    fi

    if [ $android_result -eq 0 ]; then
        status_ok "Android deployment"
    else
        status_fail "Android deployment"
    fi

    # Provide guidance if there were failures
    if [ $ios_result -ne 0 ] || [ $android_result -ne 0 ]; then
        echo ""
        log_subheader "Troubleshooting"

        if [ $ios_result -ne 0 ]; then
            echo "  iOS: Rebuild the app in Xcode on the Mac (Cmd+B)"
            echo "        If app was previously installed, it may still work."
        fi

        if [ $android_result -ne 0 ]; then
            echo "  Android: Rebuild with: just android"
        fi

        echo ""

        # Check if apps are actually usable despite deploy errors
        local ios_usable=false
        local android_usable=false

        if check_ssh_mac 2>/dev/null && ios_is_installed 2>/dev/null; then
            ios_usable=true
        fi

        if android_is_running 2>/dev/null && android_is_installed 2>/dev/null; then
            android_usable=true
        fi

        if [ "$ios_usable" = true ] || [ "$android_usable" = true ]; then
            log_info "Despite errors, some apps are still usable:"
            [ "$ios_usable" = true ] && echo "  ✓ iOS app is installed (previous version)"
            [ "$android_usable" = true ] && echo "  ✓ Android app is installed"
            echo ""
            echo "  Continue testing with: just e2e-scenario"
            return 0  # Don't fail if apps are usable
        fi

        return 1
    fi
}

cmd_deploy_ios() {
    ios_deploy
}

cmd_deploy_android() {
    android_deploy
}

cmd_relay() {
    relay_start_local
    # Keep running until interrupted
    echo "Press Ctrl+C to stop"
    wait
}

cmd_relay_setup() {
    relay_setup_local_ca
}

cmd_test() {
    log_header "E2E Test Session"

    # Check prerequisites
    log_subheader "Checking Prerequisites"

    local ready=true

    # Check relay
    if relay_check_health 2>/dev/null; then
        status_ok "Relay accessible"
    else
        status_fail "Relay not accessible"
        ready=false
    fi

    # Check iOS
    if check_ssh_mac 2>/dev/null && ios_is_booted 2>/dev/null; then
        if ios_is_installed 2>/dev/null; then
            status_ok "iOS app ready"
        else
            status_warn "iOS app not installed"
            ready=false
        fi
    else
        status_fail "iOS simulator not accessible"
        ready=false
    fi

    # Check Android
    if android_is_running 2>/dev/null; then
        if android_is_installed 2>/dev/null; then
            status_ok "Android app ready"
        else
            status_warn "Android app not installed"
            ready=false
        fi
    else
        status_fail "Android emulator not running"
        ready=false
    fi

    if [ "$ready" = false ]; then
        echo ""
        log_warn "Not all prerequisites met. Deploy apps first with: ./orchestrate.sh deploy"

        if ! confirm "Continue anyway?"; then
            exit 1
        fi
    fi

    # Run the test checklist
    echo ""
    "$PROJECT_ROOT/_dev-tools/scripts/dev/e2e-test-checklist.sh"
}

cmd_screenshot() {
    log_header "Taking Screenshots"

    ensure_dirs
    local ts
    ts=$(timestamp)

    # iOS screenshot
    if check_ssh_mac 2>/dev/null && ios_is_booted 2>/dev/null; then
        ios_screenshot "$SCREENSHOTS_DIR/ios_${ts}.png" || log_warn "iOS screenshot failed"
    else
        log_warn "iOS not available"
    fi

    # Android screenshot
    if android_is_running 2>/dev/null; then
        android_screenshot "$SCREENSHOTS_DIR/android_${ts}.png" || log_warn "Android screenshot failed"
    else
        log_warn "Android not available"
    fi

    echo ""
    log_success "Screenshots saved to: $SCREENSHOTS_DIR"
    ls -la "$SCREENSHOTS_DIR"/*.png 2>/dev/null || true
}

cmd_logs() {
    log_header "Collecting Logs"

    ensure_dirs
    local ts
    ts=$(timestamp)

    # iOS logs
    if check_ssh_mac 2>/dev/null && ios_is_booted 2>/dev/null; then
        ios_save_logs "$LOGS_DIR/ios_${ts}.txt" || log_warn "iOS logs failed"
    else
        log_warn "iOS not available"
    fi

    # Android logs
    if android_is_running 2>/dev/null; then
        android_save_logs "$LOGS_DIR/android_${ts}.txt" || log_warn "Android logs failed"
    else
        log_warn "Android not available"
    fi

    echo ""
    log_success "Logs saved to: $LOGS_DIR"
    ls -la "$LOGS_DIR"/*.txt 2>/dev/null || true
}

cmd_setup() {
    log_header "E2E Testing Setup Guide"

    echo "This guide helps you set up cross-platform E2E testing."
    echo ""

    log_subheader "1. macOS VM Setup (for iOS)"
    echo "  - UTM or Parallels VM with macOS"
    echo "  - Enable SSH: System Preferences > Sharing > Remote Login"
    echo "  - Forward port 2222 to VM port 22"
    echo "  - Test: ssh -p 2222 user@localhost"
    echo ""

    log_subheader "2. iOS App"
    echo "  - Open ios/Vauchi.xcodeproj in Xcode on the Mac"
    echo "  - Build for simulator: Cmd+B"
    echo "  - App will be at: ~/Library/Developer/Xcode/DerivedData/..."
    echo ""

    log_subheader "3. Android Emulator"
    echo "  - Install Android SDK with emulator"
    echo "  - Create AVD: avdmanager create avd -n Pixel_7 -k 'system-images;android-34;google_apis;x86_64'"
    echo "  - Test: emulator -list-avds"
    echo ""

    log_subheader "4. Android APK"
    echo "  - Build: just android"
    echo "  - APK at: android/app/build/outputs/apk/debug/app-debug.apk"
    echo ""

    log_subheader "5. Local TLS Relay (Optional)"
    echo "  - Install: caddy and mkcert"
    echo "  - Setup CA: ./orchestrate.sh relay-setup"
    echo "  - For Android physical device, install CA from:"
    echo "    adb push \"\$(mkcert -CAROOT)/rootCA.pem\" /sdcard/"
    echo ""

    log_subheader "6. QR Code Tools (Optional)"
    echo "  - Install zbar-tools for QR decoding:"
    echo "    apt install zbar-tools"
    echo ""

    log_subheader "Verification"
    echo "  Run: ./orchestrate.sh status"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# CLI Commands
# ═══════════════════════════════════════════════════════════════

cmd_cli() {
    local instance="${1:-}"
    shift || true

    if [ -z "$instance" ]; then
        cli_status
        return
    fi

    cli_run "$instance" "$@"
}

cmd_cli_test() {
    cli_test_exchange "${1:-alice}" "${2:-bob}"
}

# ═══════════════════════════════════════════════════════════════
# TUI Commands
# ═══════════════════════════════════════════════════════════════

cmd_tui() {
    local instance="${1:-}"

    if [ -z "$instance" ]; then
        tui_status
        return
    fi

    tui_launch "$instance"
}

cmd_tui_multi() {
    local instances=("${@:-alice bob}")
    tui_launch_multi "${instances[@]}"
}

# ═══════════════════════════════════════════════════════════════
# Desktop Commands
# ═══════════════════════════════════════════════════════════════

cmd_desktop() {
    local instance="${1:-}"

    if [ -z "$instance" ]; then
        desktop_status
        return
    fi

    desktop_launch "$instance"
}

cmd_desktop_dev() {
    local instance="${1:-default}"
    desktop_launch_dev "$instance"
}

cmd_desktop_build() {
    desktop_build_release
}

# ═══════════════════════════════════════════════════════════════
# Clean Commands
# ═══════════════════════════════════════════════════════════════

cmd_clean() {
    log_header "Cleaning E2E Test Data"

    cli_clean_instances
    tui_clean_instances
    desktop_clean_instances
    clean_screenshots
    clean_logs

    log_success "All E2E test data cleaned"
}

cmd_teardown() {
    log_header "Tearing Down E2E Infrastructure"

    # Stop local relay if running
    if relay_stop_local 2>/dev/null; then
        log_success "Local relay stopped"
    else
        log_info "No local relay running"
    fi

    # Clean all test data
    cmd_clean

    log_success "E2E infrastructure torn down"
}

cmd_report() {
    log_header "E2E Test Report"

    # Find the latest report file
    local latest_report
    latest_report=$(ls -t "$TMP_DIR"/e2e_report_*.txt 2>/dev/null | head -1)

    if [[ -z "$latest_report" ]]; then
        log_warn "No E2E report found. Run 'scenario all' first."
        return 1
    fi

    echo ""
    log_info "Latest report: $latest_report"
    echo ""
    cat "$latest_report"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# E2E Scenarios
# ═══════════════════════════════════════════════════════════════

# Scenario result tracking
declare -A SCENARIO_RESULTS

# List available scenarios
cmd_scenarios() {
    log_header "E2E Test Scenarios"

    echo "Available scenarios to run on deployed infrastructure:"
    echo ""
    echo "  1) cli-exchange       - Exchange between two CLI instances"
    echo "  2) tui-exchange       - Exchange between two TUI instances"
    echo "  3) mobile-exchange    - Exchange between iOS and Android"
    echo "  4) cross-platform     - CLI + Mobile exchange"
    echo "  5) sync-test          - Update card and verify sync"
    echo "  6) offline-sync       - Offline edit then sync"
    echo "  7) full-flow          - Complete flow: create, exchange, update, sync"
    echo ""
    echo "Run with: orchestrate.sh scenario <name>"
    echo "Or interactive: orchestrate.sh scenario"
    echo "Or run all: orchestrate.sh scenario all"
}

# Run scenario and capture result
run_scenario() {
    local name="$1"
    local func="$2"
    local result_file="$TMP_DIR/scenario_${name}.result"

    log_info "Running scenario: $name"
    echo ""

    # Run the scenario function and capture exit code
    set +e
    $func > "$result_file" 2>&1
    local exit_code=$?
    set -e

    # Store result
    SCENARIO_RESULTS["$name"]=$exit_code

    if [ $exit_code -eq 0 ]; then
        log_success "Scenario $name: PASSED"
    else
        log_error "Scenario $name: FAILED (exit code: $exit_code)"
    fi

    # Show output if verbose or failed
    if [ "${VERBOSE:-false}" = "true" ] || [ $exit_code -ne 0 ]; then
        echo "--- Output ---"
        cat "$result_file"
        echo "--- End ---"
    fi

    return $exit_code
}

# Run all scenarios and collect results
cmd_scenario_all() {
    log_header "Running All E2E Scenarios"

    local start_time
    start_time=$(date +%s)

    # Track results in file for summary
    local results_file="$TMP_DIR/scenario_results.txt"
    : > "$results_file"

    # List of automated scenarios (excluding interactive ones)
    local automated_scenarios=(
        "cli-exchange"
        "sync-test"
    )

    # Interactive scenarios (need user interaction)
    local interactive_scenarios=(
        "tui-exchange"
        "mobile-exchange"
        "cross-platform"
        "offline-sync"
        "full-flow"
    )

    echo ""
    echo "Automated scenarios: ${automated_scenarios[*]}"
    echo "Interactive scenarios (skipped in batch mode): ${interactive_scenarios[*]}"
    echo ""

    local passed=0
    local failed=0
    local skipped=0

    # Run automated scenarios
    for scenario in "${automated_scenarios[@]}"; do
        echo ""
        log_step "━━━ Scenario: $scenario ━━━"

        local result_file="$TMP_DIR/scenario_${scenario}.log"
        set +e

        case "$scenario" in
            cli-exchange)
                scenario_cli_exchange > "$result_file" 2>&1
                ;;
            sync-test)
                scenario_sync_test_auto > "$result_file" 2>&1
                ;;
            *)
                echo "Unknown scenario" > "$result_file"
                false
                ;;
        esac
        local exit_code=$?
        set -e

        if [ $exit_code -eq 0 ]; then
            echo "$scenario:PASSED" >> "$results_file"
            status_ok "$scenario: PASSED"
            passed=$((passed + 1))
        else
            echo "$scenario:FAILED" >> "$results_file"
            status_fail "$scenario: FAILED"
            failed=$((failed + 1))
            # Show failure output
            echo "--- Failure output ---"
            tail -20 "$result_file" 2>/dev/null || cat "$result_file"
            echo "--- End ---"
        fi
    done

    # Mark interactive scenarios as skipped
    for scenario in "${interactive_scenarios[@]}"; do
        echo "$scenario:SKIPPED" >> "$results_file"
        skipped=$((skipped + 1))
    done

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Summary
    echo ""
    log_header "E2E Scenario Results"
    echo ""
    echo "┌────────────────────────────────────────┐"
    echo "│          SCENARIO RESULTS              │"
    echo "├────────────────────────────────────────┤"

    while IFS=: read -r name result; do
        case "$result" in
            PASSED)  printf "│  %-25s  ✓ PASSED  │\n" "$name" ;;
            FAILED)  printf "│  %-25s  ✗ FAILED  │\n" "$name" ;;
            SKIPPED) printf "│  %-25s  ○ SKIPPED │\n" "$name" ;;
        esac
    done < "$results_file"

    echo "├────────────────────────────────────────┤"
    printf "│  Passed: %-3d  Failed: %-3d  Skipped: %-3d│\n" "$passed" "$failed" "$skipped"
    printf "│  Duration: %d seconds                  │\n" "$duration"
    echo "└────────────────────────────────────────┘"
    echo ""

    # Save full results
    local report_file="$TMP_DIR/e2e_report_$(timestamp).txt"
    {
        echo "E2E Test Report"
        echo "==============="
        echo "Date: $(date)"
        echo "Duration: ${duration}s"
        echo ""
        echo "Results:"
        cat "$results_file"
        echo ""
        echo "Logs saved in: $TMP_DIR/scenario_*.log"
    } > "$report_file"

    log_success "Report saved: $report_file"

    # Return failure if any tests failed
    [ $failed -eq 0 ]
}

# Run a specific scenario
cmd_scenario() {
    local scenario="$1"

    # If no scenario, show interactive menu
    if [ -z "$scenario" ]; then
        cmd_scenarios
        echo ""
        echo "Select scenario:"
        echo "  1) cli-exchange"
        echo "  2) tui-exchange"
        echo "  3) mobile-exchange"
        echo "  4) cross-platform"
        echo "  5) sync-test"
        echo "  6) offline-sync"
        echo "  7) full-flow"
        echo "  a) all - Run all automated scenarios"
        echo ""
        read -p "Enter choice [1-7, a]: " choice

        case "$choice" in
            1) scenario="cli-exchange" ;;
            2) scenario="tui-exchange" ;;
            3) scenario="mobile-exchange" ;;
            4) scenario="cross-platform" ;;
            5) scenario="sync-test" ;;
            6) scenario="offline-sync" ;;
            7) scenario="full-flow" ;;
            a|all) cmd_scenario_all; return $? ;;
            *) log_error "Invalid choice"; return 1 ;;
        esac
    fi

    case "$scenario" in
        all)
            cmd_scenario_all
            ;;
        cli-exchange)
            scenario_cli_exchange
            ;;
        tui-exchange)
            scenario_tui_exchange
            ;;
        mobile-exchange)
            scenario_mobile_exchange
            ;;
        cross-platform)
            scenario_cross_platform
            ;;
        sync-test)
            scenario_sync_test
            ;;
        offline-sync)
            scenario_offline_sync
            ;;
        full-flow)
            scenario_full_flow
            ;;
        *)
            log_error "Unknown scenario: $scenario"
            cmd_scenarios
            return 1
            ;;
    esac
}

# Scenario: CLI Exchange
scenario_cli_exchange() {
    log_header "Scenario: CLI Exchange"
    cli_test_exchange "alice" "bob"
}

# Scenario: TUI Exchange
scenario_tui_exchange() {
    log_header "Scenario: TUI Exchange"
    echo "This scenario requires two terminals."
    echo ""
    echo "Instructions:"
    echo "  1. Terminal 1: just e2e-tui alice"
    echo "  2. Terminal 2: just e2e-tui bob"
    echo "  3. In Alice's TUI: Create identity, go to Exchange, Show QR"
    echo "  4. In Bob's TUI: Create identity, go to Exchange, Scan QR"
    echo "  5. Verify both see each other in Contacts"
    echo ""

    if confirm "Launch TUI instances in new terminals?"; then
        tui_launch_multi alice bob
    fi
}

# Scenario: Mobile Exchange
scenario_mobile_exchange() {
    log_header "Scenario: Mobile Exchange (iOS <-> Android)"

    # Check prerequisites
    local ios_ready=false
    local android_ready=false

    if check_ssh_mac 2>/dev/null && ios_is_booted 2>/dev/null && ios_is_installed 2>/dev/null; then
        ios_ready=true
    fi

    if android_is_running 2>/dev/null && android_is_installed 2>/dev/null; then
        android_ready=true
    fi

    if [ "$ios_ready" = false ] || [ "$android_ready" = false ]; then
        log_warn "Mobile apps not fully deployed"
        echo ""
        [ "$ios_ready" = false ] && echo "  iOS: Not ready"
        [ "$android_ready" = false ] && echo "  Android: Not ready"
        echo ""
        if confirm "Deploy mobile apps now?"; then
            cmd_deploy
        else
            return 1
        fi
    fi

    echo ""
    echo "Instructions for Mobile Exchange:"
    echo ""
    echo "  iOS (Alice):"
    echo "    1. Create identity 'Alice'"
    echo "    2. Go to Exchange > Show QR"
    echo ""
    echo "  Android (Bob):"
    echo "    1. Create identity 'Bob'"
    echo "    2. Go to Exchange > Scan QR"
    echo "    3. Scan Alice's QR code"
    echo ""
    echo "  iOS (Alice):"
    echo "    4. Accept the exchange request"
    echo ""
    echo "  Both:"
    echo "    5. Verify contacts appear"
    echo ""

    if confirm "Take screenshots for documentation?"; then
        cmd_screenshot
    fi
}

# Scenario: Cross-Platform
scenario_cross_platform() {
    log_header "Scenario: Cross-Platform Exchange"

    echo "This scenario tests exchange between CLI and Mobile."
    echo ""
    echo "Instructions:"
    echo ""
    echo "  1. CLI (Alice):"
    echo "     just e2e-cli alice init 'Alice'"
    echo "     just e2e-cli alice exchange start"
    echo "     (copy the QR data)"
    echo ""
    echo "  2. Android/iOS (Bob):"
    echo "     Create identity 'Bob'"
    echo "     Use deep link or scan QR"
    echo ""
    echo "  3. CLI (Alice):"
    echo "     just e2e-cli alice sync"
    echo "     just e2e-cli alice contacts list"
    echo ""

    # Check if alice already exists
    local alice_dir
    alice_dir=$(cli_instance_dir "alice")

    if [ -d "$alice_dir" ] && [ -f "$alice_dir/identity.json" ]; then
        log_info "Alice CLI instance already exists"
        echo ""
        echo "Run: just e2e-cli alice exchange start"
    elif confirm "Create CLI instance for Alice?"; then
        cli_init "alice" "Alice Smith"
        echo ""
        echo "Now run: just e2e-cli alice exchange start"
    fi
}

# Scenario: Sync Test
scenario_sync_test() {
    log_header "Scenario: Sync Test"

    echo "This scenario tests card updates syncing across devices."
    echo ""
    echo "Prerequisites: Two devices with exchanged contacts"
    echo ""
    echo "Instructions:"
    echo "  1. On Device A: Edit your card (add email, phone, etc.)"
    echo "  2. Wait 10 seconds"
    echo "  3. On Device B: View Device A's card"
    echo "  4. Verify the update appears"
    echo ""

    if confirm "Run CLI sync test?"; then
        scenario_sync_test_auto
    fi
}

# Automated Sync Test (non-interactive)
scenario_sync_test_auto() {
    log_step "Testing CLI sync..."

    if ! cli_is_built; then
        log_error "CLI not built"
        return 1
    fi

    # Check if instances exist
    local alice_dir
    alice_dir=$(cli_instance_dir "alice")
    local bob_dir
    bob_dir=$(cli_instance_dir "bob")

    if [ ! -d "$alice_dir" ] || [ ! -d "$bob_dir" ]; then
        log_warn "CLI instances alice/bob not found, creating..."
        # Clean and recreate
        cli_clean_instances
        cli_init "alice" "Alice Smith"
        cli_init "bob" "Bob Jones"

        # Run exchange first
        log_step "Running exchange first..."
        local qr_data
        qr_data=$(cli_run_capture "alice" exchange start 2>&1 | grep -oE 'vauchi://[^ ]+' | head -1 || true)
        if [ -n "$qr_data" ]; then
            cli_run "bob" exchange complete "$qr_data" || true
        fi
    fi

    # Sync both
    cli_sync "alice" 2>/dev/null || log_warn "Alice sync failed"
    cli_sync "bob" 2>/dev/null || log_warn "Bob sync failed"

    log_success "Sync test complete"
}

# Scenario: Offline Sync
scenario_offline_sync() {
    log_header "Scenario: Offline Sync"

    echo "This scenario tests offline editing and sync."
    echo ""
    echo "Instructions:"
    echo "  1. On mobile device: Enable airplane mode"
    echo "  2. Edit your card"
    echo "  3. Disable airplane mode"
    echo "  4. Wait for sync"
    echo "  5. On other device: Verify update appears"
    echo ""
}

# Scenario: Full Flow
scenario_full_flow() {
    log_header "Scenario: Full E2E Flow"

    echo "Complete end-to-end test flow:"
    echo ""
    echo "  Phase 1: Setup"
    echo "    - Deploy apps to all platforms"
    echo "    - Create identities"
    echo ""
    echo "  Phase 2: Exchange"
    echo "    - Exchange contacts via QR"
    echo "    - Verify contacts on both devices"
    echo ""
    echo "  Phase 3: Sync"
    echo "    - Update card on one device"
    echo "    - Verify sync on other device"
    echo ""
    echo "  Phase 4: Offline"
    echo "    - Edit while offline"
    echo "    - Reconnect and verify sync"
    echo ""

    if confirm "Start with CLI exchange test?"; then
        scenario_cli_exchange
    fi

    echo ""
    if confirm "Continue with mobile exchange instructions?"; then
        scenario_mobile_exchange
    fi
}

# ═══════════════════════════════════════════════════════════════
# Cross-Platform Commands
# ═══════════════════════════════════════════════════════════════

cmd_exchange() {
    log_header "Cross-Platform Exchange Test"

    # Prerequisites check
    if ! check_ssh_mac 2>/dev/null || ! ios_is_booted 2>/dev/null; then
        log_error "iOS not available"
        return 1
    fi

    if ! android_is_running 2>/dev/null; then
        log_error "Android not available"
        return 1
    fi

    if ! check_qr_tools; then
        log_warn "QR tools not installed. Install zbar-tools for automated QR decoding."
        log_info "Falling back to manual exchange."
        echo ""
        echo "Manual Steps:"
        echo "  1. On iOS: Tap Exchange > Show QR"
        echo "  2. On Android: Tap Exchange > Scan QR"
        echo "  3. Or take screenshot and decode:"
        echo "     ./orchestrate.sh screenshot"
        echo "     zbarimg tmp/e2e-screenshots/ios_*.png"
        return 0
    fi

    ensure_dirs
    local ts
    ts=$(timestamp)

    # Step 1: Take iOS screenshot (assuming QR is displayed)
    log_step "Step 1: Capturing iOS QR code"
    echo "Make sure the QR code is displayed on iOS, then press Enter"
    read -p ""

    local ios_screenshot="$SCREENSHOTS_DIR/ios_qr_${ts}.png"
    ios_screenshot "$ios_screenshot"

    # Step 2: Decode QR
    log_step "Step 2: Decoding QR code"
    local qr_data
    qr_data=$(decode_qr "$ios_screenshot")

    if [ -z "$qr_data" ]; then
        log_error "Could not decode QR code from screenshot"
        return 1
    fi

    log_success "QR data decoded: ${qr_data:0:50}..."

    # Step 3: Inject via deep link on Android
    log_step "Step 3: Opening deep link on Android"
    android_open_url "vauchi://exchange?data=$(echo "$qr_data" | jq -sRr @uri)"

    log_success "Exchange initiated"
    echo ""
    echo "Check both devices for contact exchange completion"
}

# ═══════════════════════════════════════════════════════════════
# Infrastructure Map
# ═══════════════════════════════════════════════════════════════

cmd_map() {
    log_header "E2E Infrastructure Map"

    # Collect current status for dynamic diagram
    local relay_status="○"
    local relay_text="Not connected"
    local cli_status="○"
    local cli_text="Not built"
    local tui_status="○"
    local tui_text="Not built"
    local desktop_status="○"
    local desktop_text="Not available"
    local ios_status="○"
    local ios_text="Not available"
    local android_status="○"
    local android_text="Not running"
    local macos_vm_status="○"
    local macos_vm_text="Not reachable"

    # Check statuses
    if relay_check_health 2>/dev/null; then
        relay_status="●"; relay_text="Connected"
    else
        relay_status="○"; relay_text="Not connected"
    fi

    if cli_is_built 2>/dev/null; then
        cli_status="●"; cli_text="Built"
    fi

    if tui_is_built 2>/dev/null; then
        tui_status="●"; tui_text="Built"
    fi

    if desktop_is_dev_available 2>/dev/null || desktop_is_built 2>/dev/null; then
        desktop_status="●"; desktop_text="Available"
    fi

    if check_ssh_mac 2>/dev/null; then
        macos_vm_status="●"; macos_vm_text="Reachable"
        if ios_is_booted 2>/dev/null; then
            if ios_is_installed 2>/dev/null; then
                ios_status="●"; ios_text="Running + Installed"
            else
                ios_status="◐"; ios_text="Running"
            fi
        else
            ios_status="◐"; ios_text="Available"
        fi
    else
        macos_vm_status="○"; macos_vm_text="Not reachable"
        ios_status="○"; ios_text="VM not reachable"
    fi

    if android_is_running 2>/dev/null; then
        if android_is_installed 2>/dev/null; then
            android_status="●"; android_text="Running + Installed"
        else
            android_status="◐"; android_text="Running"
        fi
    else
        android_status="◐"; android_text="Available"
    fi

    # Collect session identities
    local cli_instances=()
    local tui_instances=()
    local desktop_instances=()

    if [ -d "$CLI_TEST_DATA_DIR" ]; then
        while IFS= read -r dir; do
            [ -n "$dir" ] && cli_instances+=("$(basename "$dir")")
        done < <(find "$CLI_TEST_DATA_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -10)
    fi
    if [ -d "$TUI_TEST_DATA_DIR" ]; then
        while IFS= read -r dir; do
            [ -n "$dir" ] && tui_instances+=("$(basename "$dir")")
        done < <(find "$TUI_TEST_DATA_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -10)
    fi
    if [ -d "$DESKTOP_TEST_DATA_DIR" ]; then
        while IFS= read -r dir; do
            [ -n "$dir" ] && desktop_instances+=("$(basename "$dir")")
        done < <(find "$DESKTOP_TEST_DATA_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -10)
    fi

    # Format instance lists for display
    local cli_inst_str="${cli_instances[*]:-none}"
    local tui_inst_str="${tui_instances[*]:-none}"
    local desktop_inst_str="${desktop_instances[*]:-none}"

    echo ""
    echo "  Legend: ● Ready   ◐ Partial   ○ Not Available"
    echo ""
    echo "  ╔════════════════════════════════════════════════════════════════════════════════════╗"
    echo "  ║                                                                                    ║"
    echo "  ║   ┌────────────────────────────────────────────────────────────────────────────┐   ║"
    echo "  ║   │                        🖥️  ORCHESTRATOR (Linux)                             │   ║"
    echo "  ║   │                                                                            │   ║"
    printf "  ║   │   [$cli_status] CLI              [$tui_status] TUI              [$desktop_status] Desktop               │   ║\n"
    echo "  ║   │       (vauchi)            (vauchi-tui)           (Tauri)               │   ║"
    echo "  ║   │          │                    │                    │                   │   ║"
    echo "  ║   │          └────────────────────┼────────────────────┘                   │   ║"
    echo "  ║   │                               │                                        │   ║"
    echo "  ║   └───────────────────────────────┼────────────────────────────────────────┘   ║"
    echo "  ║                                   │                                            ║"
    echo "  ║                                   │ WebSocket                                  ║"
    echo "  ║                                   ▼                                            ║"
    echo "  ║   ┌────────────────────────────────────────────────────────────────────────────┐ ║"
    echo "  ║   │                         ☁️  RELAY SERVER                                    │ ║"
    printf "  ║   │                           [$relay_status] %-12s                               │ ║\n" "$relay_text"
    echo "  ║   │                                                                            │ ║"
    echo "  ║   │           Production: wss://relay.vauchi.app                               │ ║"
    echo "  ║   │           Local:      wss://localhost:8443                                 │ ║"
    echo "  ║   └────────────────────────────────────────────────────────────────────────────┘ ║"
    echo "  ║                                   │                                            ║"
    echo "  ║                    ┌──────────────┴──────────────┐                             ║"
    echo "  ║                    │                             │                             ║"
    echo "  ║                    ▼                             ▼                             ║"
    echo "  ║   ┌──────────────────────────────────┐ ┌──────────────────────────────────┐    ║"
    echo "  ║   │     🍎 macOS VM (SSH:2222)       │ │     🤖 Android (Local)           │    ║"
    printf "  ║   │        [$macos_vm_status] %-19s │ │        [$android_status] %-19s │    ║\n" "$macos_vm_text" "$android_text"
    echo "  ║   │                                  │ │                                  │    ║"
    echo "  ║   │   ┌──────────────────────────┐   │ │   ┌──────────────────────────┐   │    ║"
    echo "  ║   │   │     📱 iOS Simulator      │   │ │   │   📱 Android Emulator    │   │    ║"
    printf "  ║   │   │     [$ios_status] %-16s │   │ │   │   [$android_status] %-16s │   │    ║\n" "${ios_text:0:16}" "${android_text:0:16}"
    echo "  ║   │   │                          │   │ │   │                          │   │    ║"
    echo "  ║   │   │   ┌──────────────────┐   │   │ │   │   ┌──────────────────┐   │   │    ║"
    echo "  ║   │   │   │    Vauchi App    │   │   │ │   │   │    Vauchi App    │   │   │    ║"
    echo "  ║   │   │   └──────────────────┘   │   │ │   │   └──────────────────┘   │   │    ║"
    echo "  ║   │   └──────────────────────────┘   │ │   └──────────────────────────┘   │    ║"
    echo "  ║   └──────────────────────────────────┘ └──────────────────────────────────┘    ║"
    echo "  ║                                                                                    ║"
    echo "  ╚════════════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Session Identities Section
    echo "  ╔════════════════════════════════════════════════════════════════════════════════════╗"
    echo "  ║                            👤 E2E SESSION IDENTITIES                               ║"
    echo "  ╠════════════════════════════════════════════════════════════════════════════════════╣"

    local has_any_identity=false

    # CLI Identities
    if [ ${#cli_instances[@]} -gt 0 ]; then
        has_any_identity=true
        echo "  ║                                                                                    ║"
        echo "  ║   CLI Instances:                                                                   ║"
        for instance in "${cli_instances[@]}"; do
            local instance_dir="$CLI_TEST_DATA_DIR/$instance"
            local identity_name=""
            local contacts_count=0

            # Try to get identity name using CLI card show command
            if [ -f "$instance_dir/identity.json" ] && cli_is_built 2>/dev/null; then
                identity_name=$("$(cli_binary)" --data-dir "$instance_dir" --relay "$CLI_RELAY_URL" card show 2>/dev/null | head -2 | tail -1 | sed 's/^ *//' | head -c 20)
            fi
            # Count contacts using CLI (look for "Contacts (N):" in output)
            if cli_is_built 2>/dev/null; then
                local contact_output
                contact_output=$("$(cli_binary)" --data-dir "$instance_dir" --relay "$CLI_RELAY_URL" contacts list 2>/dev/null || true)
                contacts_count=$(echo "$contact_output" | grep -oP 'Contacts \(\K[0-9]+' | head -1 || echo "0")
                [ -z "$contacts_count" ] && contacts_count=0
            fi

            if [ -n "$identity_name" ] && [ "$identity_name" != "(no fields)" ]; then
                printf "  ║     ├─ 🔹 %-10s │ Identity: %-20s │ Contacts: %-3s     ║\n" "$instance" "${identity_name:0:20}" "$contacts_count"
            else
                printf "  ║     ├─ 🔹 %-10s │ (data dir exists)                │ Contacts: %-3s     ║\n" "$instance" "$contacts_count"
            fi
        done
    fi

    # TUI Identities
    if [ ${#tui_instances[@]} -gt 0 ]; then
        has_any_identity=true
        echo "  ║                                                                                    ║"
        echo "  ║   TUI Instances:                                                                   ║"
        for instance in "${tui_instances[@]}"; do
            local instance_dir="$TUI_TEST_DATA_DIR/$instance"
            local identity_name=""
            local contacts_count=0

            if [ -f "$instance_dir/identity.json" ]; then
                identity_name=$(grep -oP '"name"\s*:\s*"\K[^"]+' "$instance_dir/identity.json" 2>/dev/null | head -1)
            fi
            if [ -d "$instance_dir/contacts" ]; then
                contacts_count=$(find "$instance_dir/contacts" -name "*.json" 2>/dev/null | wc -l)
            fi

            if [ -n "$identity_name" ]; then
                printf "  ║     ├─ 🔸 %-10s │ Identity: %-20s │ Contacts: %-3s     ║\n" "$instance" "${identity_name:0:20}" "$contacts_count"
            else
                printf "  ║     ├─ 🔸 %-10s │ (data dir only)                  │ Contacts: %-3s     ║\n" "$instance" "$contacts_count"
            fi
        done
    fi

    # Desktop Identities
    if [ ${#desktop_instances[@]} -gt 0 ]; then
        has_any_identity=true
        echo "  ║                                                                                    ║"
        echo "  ║   Desktop Instances:                                                               ║"
        for instance in "${desktop_instances[@]}"; do
            local instance_dir="$DESKTOP_TEST_DATA_DIR/$instance"
            local identity_name=""
            local contacts_count=0

            if [ -f "$instance_dir/identity.json" ]; then
                identity_name=$(grep -oP '"name"\s*:\s*"\K[^"]+' "$instance_dir/identity.json" 2>/dev/null | head -1)
            fi
            if [ -d "$instance_dir/contacts" ]; then
                contacts_count=$(find "$instance_dir/contacts" -name "*.json" 2>/dev/null | wc -l)
            fi

            if [ -n "$identity_name" ]; then
                printf "  ║     ├─ 🔶 %-10s │ Identity: %-20s │ Contacts: %-3s     ║\n" "$instance" "${identity_name:0:20}" "$contacts_count"
            else
                printf "  ║     ├─ 🔶 %-10s │ (data dir only)                  │ Contacts: %-3s     ║\n" "$instance" "$contacts_count"
            fi
        done
    fi

    # Mobile Apps (identities stored on device)
    if [ "$ios_status" = "●" ] || [ "$android_status" = "●" ]; then
        has_any_identity=true
        echo "  ║                                                                                    ║"
        echo "  ║   Mobile Apps (identities on device):                                              ║"
        [ "$ios_status" = "●" ] && echo "  ║     ├─ 📱 iOS App        │ Identity stored on simulator                        ║"
        [ "$android_status" = "●" ] && echo "  ║     ├─ 📱 Android App    │ Identity stored on emulator                         ║"
    fi

    if [ "$has_any_identity" = false ]; then
        echo "  ║                                                                                    ║"
        echo "  ║   No session identities found.                                                     ║"
        echo "  ║                                                                                    ║"
        echo "  ║   Create identities with:                                                          ║"
        echo "  ║     just e2e-cli alice init \"Alice Smith\"                                          ║"
        echo "  ║     just e2e-cli bob init \"Bob Jones\"                                              ║"
    fi

    echo "  ║                                                                                    ║"
    echo "  ╚════════════════════════════════════════════════════════════════════════════════════╝"
    echo ""

    # Optionally save mermaid to file
    if [ "${1:-}" = "--mermaid" ]; then
        local output_file="${2:-$TMP_DIR/e2e-infrastructure.md}"
        cmd_map_mermaid > "$output_file"
        log_success "Mermaid diagram saved to: $output_file"
    fi
}

# Generate Mermaid diagram (for documentation)
cmd_map_mermaid() {
    echo '```mermaid'
    echo "graph TB"
    echo "    subgraph orchestrator[\"Orchestrator (Linux)\"]"
    echo "        orch[\"orchestrate.sh\"]"
    echo "        cli[\"CLI (vauchi)\"]"
    echo "        tui[\"TUI (vauchi-tui)\"]"
    echo "        desktop[\"Desktop (Tauri)\"]"
    echo "    end"
    echo ""
    echo "    subgraph macos_vm[\"macOS VM (SSH :2222)\"]"
    echo "        simulator[\"iOS Simulator\"]"
    echo "        ios_app[\"Vauchi iOS App\"]"
    echo "        simulator --> ios_app"
    echo "    end"
    echo ""
    echo "    subgraph local_android[\"Android (Local)\"]"
    echo "        emulator[\"Android Emulator\"]"
    echo "        android_app[\"Vauchi Android App\"]"
    echo "        emulator --> android_app"
    echo "    end"
    echo ""
    echo "    subgraph relay_server[\"Relay Server\"]"
    echo "        relay[\"WebSocket Relay\"]"
    echo "        relay_prod[\"wss://relay.vauchi.app\"]"
    echo "        relay_local[\"wss://localhost:8443\"]"
    echo "    end"
    echo ""
    echo "    orch -->|SSH| simulator"
    echo "    orch -->|adb| emulator"
    echo ""
    echo "    cli -.->|WebSocket| relay"
    echo "    tui -.->|WebSocket| relay"
    echo "    desktop -.->|WebSocket| relay"
    echo "    ios_app -.->|WebSocket| relay"
    echo "    android_app -.->|WebSocket| relay"
    echo ""
    echo "    relay --> relay_prod"
    echo "    relay --> relay_local"
    echo '```'
}

cmd_help() {
    echo "E2E Testing Orchestrator"
    echo ""
    echo "Usage: orchestrate.sh <command> [args...]"
    echo ""
    echo "General:"
    echo "  status              Check status of all components"
    echo "  map                 Show infrastructure as Mermaid diagram"
    echo "  setup               Show setup guide"
    echo "  clean               Clean all E2E test data"
    echo "  teardown            Stop relay and clean all test data"
    echo "  report              Show latest E2E test report"
    echo "  help                Show this help"
    echo ""
    echo "Scenarios (run on deployed infrastructure):"
    echo "  scenarios           List available test scenarios"
    echo "  scenario [name]     Run a test scenario (interactive if no name)"
    echo "  scenario all        Run all automated scenarios with results report"
    echo ""
    echo "CLI Testing:"
    echo "  cli [inst] [cmd]    Run CLI command for instance (prompts if missing)"
    echo "  cli-test [a] [b]    Run exchange test between two CLI instances"
    echo ""
    echo "TUI Testing:"
    echo "  tui [instance]      Launch TUI for instance (prompts if missing)"
    echo "  tui-multi [a b ..]  Launch multiple TUI instances in terminals"
    echo ""
    echo "Desktop Testing:"
    echo "  desktop [instance]  Launch desktop app (prompts if missing)"
    echo "  desktop-dev [inst]  Launch desktop in dev mode"
    echo "  desktop-build       Build desktop release binary"
    echo ""
    echo "Mobile Testing:"
    echo "  deploy              Deploy apps to all mobile devices"
    echo "  deploy-ios          Deploy iOS app to macOS VM simulator"
    echo "  deploy-android      Deploy Android APK to local emulator"
    echo "  test                Run E2E test checklist interactively"
    echo "  screenshot          Take screenshots from mobile devices"
    echo "  logs                Collect logs from mobile devices"
    echo "  exchange            Run cross-platform QR exchange test"
    echo ""
    echo "Relay:"
    echo "  relay               Start local TLS relay server"
    echo "  relay-setup         Setup local CA for TLS"
    echo ""
    echo "Configuration: _dev-tools/scripts/e2e/config.env"
    echo ""
    echo "Quick Start:"
    echo "  1. orchestrate.sh status       # Check what's available"
    echo "  2. orchestrate.sh deploy       # Deploy mobile apps"
    echo "  3. orchestrate.sh scenario     # Run a test scenario"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════

main() {
    # Setup cleanup trap
    setup_cleanup_trap

    local command="${1:-help}"
    shift || true

    case "$command" in
        # General
        status)
            cmd_status
            ;;
        map)
            cmd_map "$@"
            ;;
        setup)
            cmd_setup
            ;;
        clean)
            cmd_clean
            ;;
        teardown)
            cmd_teardown
            ;;
        report)
            cmd_report
            ;;
        help|--help|-h)
            cmd_help
            ;;

        # Scenarios
        scenarios)
            cmd_scenarios
            ;;
        scenario)
            cmd_scenario "$@"
            ;;

        # CLI
        cli)
            cmd_cli "$@"
            ;;
        cli-test)
            cmd_cli_test "$@"
            ;;

        # TUI
        tui)
            cmd_tui "$@"
            ;;
        tui-multi)
            cmd_tui_multi "$@"
            ;;

        # Desktop
        desktop)
            cmd_desktop "$@"
            ;;
        desktop-dev)
            cmd_desktop_dev "$@"
            ;;
        desktop-build)
            cmd_desktop_build
            ;;

        # Mobile
        deploy)
            cmd_deploy
            ;;
        deploy-ios)
            cmd_deploy_ios
            ;;
        deploy-android)
            cmd_deploy_android
            ;;
        test)
            cmd_test
            ;;
        screenshot|screenshots)
            cmd_screenshot
            ;;
        logs)
            cmd_logs
            ;;
        exchange)
            cmd_exchange
            ;;

        # Relay
        relay)
            cmd_relay
            ;;
        relay-setup)
            cmd_relay_setup
            ;;

        *)
            log_error "Unknown command: $command"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
