#!/bin/bash
# E2E Test Checklist Script
# Run through all manual E2E tests systematically
#
# Usage:
#   ./e2e-test-checklist.sh           # Interactive mode
#   ./e2e-test-checklist.sh --status  # Show current status
#   ./e2e-test-checklist.sh --deploy  # Deploy apps before testing
#   ./e2e-test-checklist.sh --screenshot # Take screenshot at current step

set -e

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RESULTS_FILE="${SCRIPT_DIR}/.e2e-test-results.json"

# E2E orchestration (if available)
E2E_DIR="$PROJECT_ROOT/_dev-tools/scripts/e2e"
HAS_ORCHESTRATION=false
if [ -f "$E2E_DIR/orchestrate.sh" ]; then
    HAS_ORCHESTRATION=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test definitions
declare -a TESTS=(
    "prereq_relay|Prerequisites: Relay accessible|curl -s https://relay.vauchi.app/health"
    "prereq_ios|Prerequisites: iOS app installed|Check iOS device/simulator"
    "prereq_android|Prerequisites: Android app installed|Check Android device/emulator"
    "test1_alice_identity|Test 1.1: Alice creates identity|iOS: Create identity 'Alice'"
    "test1_alice_qr|Test 1.2: Alice generates QR|iOS: Tap Exchange > Show QR"
    "test1_bob_identity|Test 1.3: Bob creates identity|Android: Create identity 'Bob'"
    "test1_bob_scan|Test 1.4: Bob scans QR|Android: Tap Exchange > Scan QR"
    "test1_alice_confirm|Test 1.5: Alice confirms|iOS: Accept exchange request"
    "test1_verify|Test 1.6: Verify contacts|Both see each other in Contacts"
    "test2_alice_edit|Test 2.1: Alice edits card|iOS: Add email alice@example.com"
    "test2_wait|Test 2.2: Wait for sync|Wait 10 seconds"
    "test2_bob_verify|Test 2.3: Bob sees update|Android: View Alice's card, see email"
    "test3_airplane|Test 3.1: Offline edit|iOS: Airplane mode ON, edit card"
    "test3_reconnect|Test 3.2: Reconnect|iOS: Airplane mode OFF"
    "test3_verify|Test 3.3: Verify sync|Android: See update within 30s"
    "test4_note_phrase|Test 4.1: Note recovery phrase|Record 12/24 word phrase"
    "test4_new_device|Test 4.2: Recover on new device|Select 'Recover account'"
    "test4_enter_phrase|Test 4.3: Enter phrase|Type recovery phrase"
    "test4_verify|Test 4.4: Verify contacts restored|All contacts present"
    "test5_create_label|Test 5.1: Create visibility label|iOS: Create 'Work' label"
    "test5_assign_label|Test 5.2: Assign contact to label|iOS: Assign Bob to 'Work'"
    "test5_verify|Test 5.3: Verify visibility|Bob sees only Work fields"
    "test6_background|Test 6.1: Background sync|Send update while app backgrounded"
    "test6_foreground|Test 6.2: Foreground verify|Bring app forward, see update"
    "test6_restart|Test 6.3: App restart|Kill app, relaunch, verify data"
)

# Initialize results file
init_results() {
    if [ ! -f "$RESULTS_FILE" ]; then
        echo '{"tests":{},"started":"'$(date -Iseconds)'","tester":"","build":""}' > "$RESULTS_FILE"
    fi
}

# Get test status
get_status() {
    local test_id="$1"
    if [ -f "$RESULTS_FILE" ]; then
        jq -r ".tests[\"$test_id\"] // \"pending\"" "$RESULTS_FILE" 2>/dev/null || echo "pending"
    else
        echo "pending"
    fi
}

# Set test status
set_status() {
    local test_id="$1"
    local status="$2"
    local tmp=$(mktemp)
    jq ".tests[\"$test_id\"] = \"$status\"" "$RESULTS_FILE" > "$tmp" && mv "$tmp" "$RESULTS_FILE"
}

# Print status icon
status_icon() {
    case "$1" in
        pass) echo -e "${GREEN}✓${NC}" ;;
        fail) echo -e "${RED}✗${NC}" ;;
        skip) echo -e "${YELLOW}○${NC}" ;;
        *) echo -e "${BLUE}·${NC}" ;;
    esac
}

# Show all test status
show_status() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Vauchi E2E Test Status"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    local pass=0 fail=0 skip=0 pending=0
    local current_section=""

    for test in "${TESTS[@]}"; do
        IFS='|' read -r id name desc <<< "$test"
        local status=$(get_status "$id")

        # Section headers
        local section="${id%%_*}"
        if [ "$section" != "$current_section" ]; then
            current_section="$section"
            echo ""
            case "$section" in
                prereq) echo -e "${BLUE}▸ Prerequisites${NC}" ;;
                test1) echo -e "${BLUE}▸ Test 1: Contact Exchange (QR Code)${NC}" ;;
                test2) echo -e "${BLUE}▸ Test 2: Card Update Sync${NC}" ;;
                test3) echo -e "${BLUE}▸ Test 3: Offline → Online Sync${NC}" ;;
                test4) echo -e "${BLUE}▸ Test 4: Recovery Flow${NC}" ;;
                test5) echo -e "${BLUE}▸ Test 5: Visibility Labels${NC}" ;;
                test6) echo -e "${BLUE}▸ Test 6: App Lifecycle${NC}" ;;
            esac
        fi

        echo -e "  $(status_icon $status) $name"

        case "$status" in
            pass) pass=$((pass + 1)) ;;
            fail) fail=$((fail + 1)) ;;
            skip) skip=$((skip + 1)) ;;
            *) pending=$((pending + 1)) ;;
        esac
    done

    echo ""
    echo "───────────────────────────────────────────────────────────────"
    echo -e "  Total: ${GREEN}$pass pass${NC} | ${RED}$fail fail${NC} | ${YELLOW}$skip skip${NC} | ${BLUE}$pending pending${NC}"
    echo "───────────────────────────────────────────────────────────────"

    if [ -f "$RESULTS_FILE" ]; then
        local tester=$(jq -r '.tester // ""' "$RESULTS_FILE")
        local build=$(jq -r '.build // ""' "$RESULTS_FILE")
        local started=$(jq -r '.started // ""' "$RESULTS_FILE")
        [ -n "$tester" ] && echo "  Tester: $tester"
        [ -n "$build" ] && echo "  Build: $build"
        [ -n "$started" ] && echo "  Started: $started"
    fi
    echo ""
}

# Run interactive test session
run_interactive() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Vauchi E2E Test Session"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    # Get tester info
    read -p "Tester name: " tester
    read -p "Build version/date: " build

    local tmp=$(mktemp)
    jq ".tester = \"$tester\" | .build = \"$build\"" "$RESULTS_FILE" > "$tmp" && mv "$tmp" "$RESULTS_FILE"

    echo ""
    echo "For each test, enter:"
    echo "  [p]ass  - Test passed"
    echo "  [f]ail  - Test failed (will prompt for notes)"
    echo "  [s]kip  - Skip this test"
    if [ "$HAS_ORCHESTRATION" = true ]; then
        echo "  [c]apture - Take screenshot"
        echo "  [l]ogs  - Collect logs"
    fi
    echo "  [q]uit  - Save and exit"
    echo ""

    for test in "${TESTS[@]}"; do
        IFS='|' read -r id name desc <<< "$test"
        local status=$(get_status "$id")

        # Skip already completed tests
        if [ "$status" = "pass" ] || [ "$status" = "fail" ]; then
            echo -e "$(status_icon $status) $name (already recorded)"
            continue
        fi

        echo ""
        echo -e "${YELLOW}▸ $name${NC}"
        echo "  $desc"
        echo ""

        while true; do
            local prompt_opts="p/f/s"
            if [ "$HAS_ORCHESTRATION" = true ]; then
                prompt_opts="p/f/s/c/l"
            fi
            read -p "  Result [$prompt_opts/q]: " result
            case "$result" in
                p|P|pass)
                    set_status "$id" "pass"
                    echo -e "  ${GREEN}✓ Marked as PASS${NC}"
                    break
                    ;;
                f|F|fail)
                    read -p "  Failure notes: " notes
                    set_status "$id" "fail"
                    # Store notes
                    local tmp=$(mktemp)
                    jq ".notes[\"$id\"] = \"$notes\"" "$RESULTS_FILE" > "$tmp" && mv "$tmp" "$RESULTS_FILE"
                    echo -e "  ${RED}✗ Marked as FAIL${NC}"
                    # Automatically collect logs on failure
                    if [ "$HAS_ORCHESTRATION" = true ]; then
                        collect_logs
                    fi
                    break
                    ;;
                s|S|skip)
                    set_status "$id" "skip"
                    echo -e "  ${YELLOW}○ Marked as SKIP${NC}"
                    break
                    ;;
                c|C|capture)
                    if [ "$HAS_ORCHESTRATION" = true ]; then
                        take_screenshot "$id"
                    else
                        echo "  Screenshot not available without orchestration"
                    fi
                    # Don't break - let user continue with test result
                    ;;
                l|L|logs)
                    if [ "$HAS_ORCHESTRATION" = true ]; then
                        collect_logs
                    else
                        echo "  Log collection not available without orchestration"
                    fi
                    # Don't break - let user continue with test result
                    ;;
                q|Q|quit)
                    echo ""
                    echo "Session saved. Run again to continue."
                    show_status
                    exit 0
                    ;;
                *)
                    echo "  Invalid input. Use $prompt_opts/q"
                    ;;
            esac
        done
    done

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  All tests completed!"
    echo "═══════════════════════════════════════════════════════════════"
    show_status
}

# Reset results
reset_results() {
    rm -f "$RESULTS_FILE"
    init_results
    echo "Test results reset."
}

# Deploy apps using orchestrator
deploy_apps() {
    if [ "$HAS_ORCHESTRATION" = true ]; then
        echo ""
        echo -e "${BLUE}Deploying apps to devices...${NC}"
        "$E2E_DIR/orchestrate.sh" deploy
    else
        echo "Orchestration not available. Deploy manually."
    fi
}

# Take screenshot using orchestrator
take_screenshot() {
    local step_name="${1:-screenshot}"
    if [ "$HAS_ORCHESTRATION" = true ]; then
        echo -e "${CYAN}Taking screenshots...${NC}"
        "$E2E_DIR/orchestrate.sh" screenshot
    else
        echo "Orchestration not available. Screenshots not supported."
    fi
}

# Collect logs using orchestrator
collect_logs() {
    if [ "$HAS_ORCHESTRATION" = true ]; then
        echo -e "${CYAN}Collecting logs...${NC}"
        "$E2E_DIR/orchestrate.sh" logs
    else
        echo "Orchestration not available. Log collection not supported."
    fi
}

# Export results to markdown
export_markdown() {
    local outfile="${1:-e2e-test-results.md}"

    echo "# E2E Test Results" > "$outfile"
    echo "" >> "$outfile"
    echo "**Date**: $(date)" >> "$outfile"

    if [ -f "$RESULTS_FILE" ]; then
        local tester=$(jq -r '.tester // "Unknown"' "$RESULTS_FILE")
        local build=$(jq -r '.build // "Unknown"' "$RESULTS_FILE")
        echo "**Tester**: $tester" >> "$outfile"
        echo "**Build**: $build" >> "$outfile"
    fi

    echo "" >> "$outfile"
    echo "## Results" >> "$outfile"
    echo "" >> "$outfile"
    echo "| Test | Status | Notes |" >> "$outfile"
    echo "|------|--------|-------|" >> "$outfile"

    for test in "${TESTS[@]}"; do
        IFS='|' read -r id name desc <<< "$test"
        local status=$(get_status "$id")
        local notes=""
        if [ -f "$RESULTS_FILE" ]; then
            notes=$(jq -r ".notes[\"$id\"] // \"\"" "$RESULTS_FILE" 2>/dev/null || echo "")
        fi

        local icon
        case "$status" in
            pass) icon="✅" ;;
            fail) icon="❌" ;;
            skip) icon="⏭️" ;;
            *) icon="⏳" ;;
        esac

        echo "| $name | $icon $status | $notes |" >> "$outfile"
    done

    echo "" >> "$outfile"
    echo "---" >> "$outfile"
    echo "Generated by e2e-test-checklist.sh" >> "$outfile"

    echo "Results exported to: $outfile"
}

# Main
main() {
    init_results

    case "${1:-}" in
        --status|-s)
            show_status
            ;;
        --reset|-r)
            reset_results
            ;;
        --export|-e)
            export_markdown "${2:-}"
            ;;
        --deploy|-d)
            deploy_apps
            ;;
        --screenshot|-c)
            take_screenshot
            ;;
        --logs|-l)
            collect_logs
            ;;
        --help|-h)
            echo "E2E Test Checklist"
            echo ""
            echo "Usage:"
            echo "  $0              Run interactive test session"
            echo "  $0 --status     Show current test status"
            echo "  $0 --reset      Reset all test results"
            echo "  $0 --export     Export results to markdown"
            if [ "$HAS_ORCHESTRATION" = true ]; then
                echo "  $0 --deploy     Deploy apps to devices"
                echo "  $0 --screenshot Take screenshots"
                echo "  $0 --logs       Collect logs"
            fi
            echo "  $0 --help       Show this help"
            ;;
        *)
            run_interactive
            ;;
    esac
}

main "$@"
