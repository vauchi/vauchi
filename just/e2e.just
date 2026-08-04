# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

[private]
test-e2e-recipes:
    python3 "{{ justfile_directory() }}/tests/test_e2e_recipe.py" \
        "{{ justfile_directory() }}/justfile"

# End-to-end testing recipes

# ═══════════════════════════════════════════════════════════════════
# E2E TESTING
# ═══════════════════════════════════════════════════════════════════

# List available E2E tests
[group('e2e')]
e2e:
    @echo "Available E2E tests:"
    @cd e2e && cargo test -- --list --include-ignored 2>&1 | grep '^test_' | sed 's/: test//'
    @echo ""
    @echo "Run with: just e2e-run <name>  (or 'all' for all tests)"

# Build E2E binaries with SHA-based caching (relay + CLI)
[group('e2e')]
e2e-build:
    ./scripts/scripts/e2e/build-binaries.sh

# Run E2E test(s) - use 'all' to run everything
[group('e2e')]
[script]
e2e-run name: build e2e-build
    if [[ "{{name}}" == "all" ]]; then
        cd e2e && cargo test -- --include-ignored --nocapture
    else
        cd e2e && cargo test {{name}} -- --include-ignored --nocapture
    fi

# Run E2E smoke tests (fast, for every push)
[group('e2e')]
[script]
e2e-smoke: e2e-build
    echo "Running E2E smoke tests..."
    cd e2e && cargo test smoke_ -- --nocapture
    echo ""
    echo "Smoke tests complete."

# Run E2E release tests (full validation)
[group('e2e')]
[script]
e2e-release: e2e-build
    echo "Running full E2E test suite for release validation..."
    cd e2e && cargo test -- --include-ignored --nocapture
    echo ""
    echo "Release validation complete."

# Run E2E integration tests only (excludes smoke)
[group('e2e')]
[script]
e2e-integration: e2e-build
    echo "Running E2E integration tests..."
    cd e2e && cargo test integration_ -- --nocapture
    echo ""
    echo "Integration tests complete."

# Build CLI binary (into shared target dir for e2e tests)
# Uses --no-default-features to disable secure-storage (macOS Keychain)
# which doesn't persist keys between CLI process invocations.
[private]
build-cli:
    cd cli && cargo build --no-default-features --release --target-dir ../target

# Build relay binary (into shared target dir for e2e tests)
[private]
build-relay:
    cd relay && cargo build --release --target-dir ../target

# ═══════════════════════════════════════════════════════════════
# CROSS-PLATFORM E2E TESTING
# ═══════════════════════════════════════════════════════════════

# Check E2E testing status (all platforms)
[group('e2e')]
e2e-status:
    ./scripts/scripts/e2e/orchestrate.sh status

# Clean all E2E test data
[group('e2e')]
[confirm('This will clean all E2E test data. Continue?')]
e2e-clean:
    ./scripts/scripts/e2e/orchestrate.sh clean

# Show E2E setup guide
[group('e2e')]
e2e-setup:
    ./scripts/scripts/e2e/orchestrate.sh setup

# Show E2E infrastructure as Mermaid diagram
[group('e2e')]
e2e-map:
    ./scripts/scripts/e2e/orchestrate.sh map

# List available E2E test scenarios
[group('e2e')]
e2e-scenarios:
    ./scripts/scripts/e2e/orchestrate.sh scenarios

# Run an E2E test scenario (use 'all' to run all automated scenarios)
[group('e2e')]
e2e-scenario name="":
    ./scripts/scripts/e2e/orchestrate.sh scenario {{name}}

# Run all automated E2E scenarios and show results report
[group('e2e')]
e2e-scenario-all:
    ./scripts/scripts/e2e/orchestrate.sh scenario all

# Show latest E2E test report
[group('e2e')]
e2e-report:
    ./scripts/scripts/e2e/orchestrate.sh report

# Teardown E2E infrastructure (stop relay, clean all test data)
[group('e2e')]
[confirm('This will tear down all E2E infrastructure. Continue?')]
e2e-teardown-and-clean-infra:
    ./scripts/scripts/e2e/orchestrate.sh teardown

# ─── CLI E2E ────────────────────────────────────────────────────

# Run CLI command for instance (e.g., just e2e-cli alice init "Alice")
[group('e2e')]
[positional-arguments]
e2e-cli *args:
    ./scripts/scripts/e2e/orchestrate.sh cli "$@"

# Run CLI exchange test between two instances
[group('e2e')]
e2e-cli-test alice="alice" bob="bob":
    ./scripts/scripts/e2e/orchestrate.sh cli-test {{alice}} {{bob}}

# ─── TUI E2E ────────────────────────────────────────────────────

# Launch TUI for instance (e.g., just e2e-tui alice)
[group('e2e')]
e2e-tui instance:
    ./scripts/scripts/e2e/orchestrate.sh tui {{instance}}

# Launch multiple TUI instances in separate terminals
[group('e2e')]
e2e-tui-multi *instances:
    ./scripts/scripts/e2e/orchestrate.sh tui-multi {{instances}}

# Run mobile E2E tests (requires booted simulator/emulator + Maestro)
[group('e2e')]
[script]
e2e-mobile: e2e-build
    echo "Running mobile E2E tests..."
    cd e2e && cargo test test_ios_simulator_exchange -- --ignored --nocapture
    cd e2e && cargo test test_android_emulator_exchange -- --ignored --nocapture
    echo ""
    echo "Mobile E2E tests complete."

# Run all E2E tests (CLI + Mobile)
[group('e2e')]
[script]
e2e-all: e2e-build
    echo "Running full E2E suite (all platforms)..."
    cd e2e && cargo test -- --include-ignored --nocapture
    echo ""
    echo "Full E2E suite complete."

# ─── Mobile E2E ─────────────────────────────────────────────────

# Deploy apps to all mobile devices (iOS + Android)
[group('e2e')]
e2e-deploy:
    ./scripts/scripts/e2e/orchestrate.sh deploy

# Deploy iOS app to macOS simulator
[group('e2e')]
e2e-deploy-ios:
    ./scripts/scripts/e2e/orchestrate.sh deploy-ios

# Deploy Android APK to local emulator
[group('e2e')]
e2e-deploy-android:
    ./scripts/scripts/e2e/orchestrate.sh deploy-android

# Start Android emulator manually (with xcb Qt platform for Wayland compatibility)
[group('e2e')]
e2e-android-start avd=avd_android:
    QT_QPA_PLATFORM=xcb emulator -avd {{avd}} -gpu auto

# Run interactive mobile E2E test session
[group('e2e')]
e2e-test-mobile:
    ./scripts/scripts/e2e/orchestrate.sh test

# Take screenshots from mobile devices
[group('e2e')]
e2e-screenshot:
    ./scripts/scripts/e2e/orchestrate.sh screenshot

# Collect logs from mobile devices
[group('e2e')]
e2e-logs:
    ./scripts/scripts/e2e/orchestrate.sh logs

# ─── Maestro ─────────────────────────────────────────────────────

# Verify Maestro CLI is installed and environment is ready
[group('e2e')]
[script]
maestro-setup:
    set -euo pipefail
    echo "═══ Maestro Environment Check ═══"
    echo ""

    ERRORS=0

    # 1. Maestro CLI
    if command -v maestro &>/dev/null; then
        echo "  [OK] Maestro CLI: $(maestro --version 2>&1 | head -1)"
    else
        echo "  [MISSING] Maestro CLI"
        echo "    Install: curl -Ls 'https://get.maestro.mobile.dev' | bash"
        ERRORS=$((ERRORS + 1))
    fi
    echo ""

    # 2. iOS tooling (macOS only)
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "  --- iOS ---"
        if command -v xcrun &>/dev/null; then
            echo "  [OK] Xcode CLI tools: $(xcodebuild -version 2>/dev/null | head -1 || echo 'unknown')"
            BOOTED=$(xcrun simctl list devices booted 2>/dev/null | grep -c "Booted" || echo 0)
            echo "  [INFO] Booted simulators: $BOOTED"
            if [[ "$BOOTED" -eq 0 ]]; then
                echo "    Hint: xcrun simctl boot 'iPhone 15 Pro'"
            fi
        else
            echo "  [MISSING] Xcode CLI tools"
            echo "    Install: xcode-select --install"
            ERRORS=$((ERRORS + 1))
        fi
        echo ""
    fi

    # 3. Android tooling
    echo "  --- Android ---"
    if [[ -n "${ANDROID_HOME:-}" ]]; then
        echo "  [OK] ANDROID_HOME: $ANDROID_HOME"
    elif [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
        echo "  [OK] ANDROID_SDK_ROOT: $ANDROID_SDK_ROOT"
    else
        echo "  [MISSING] ANDROID_HOME / ANDROID_SDK_ROOT not set"
        ERRORS=$((ERRORS + 1))
    fi

    if command -v adb &>/dev/null; then
        DEVICES=$(adb devices 2>/dev/null | grep -c "device$" || echo 0)
        echo "  [OK] ADB: $(adb --version 2>&1 | head -1)"
        echo "  [INFO] Connected devices: $DEVICES"
        if [[ "$DEVICES" -eq 0 ]]; then
            echo "    Hint: emulator -avd {{avd_android}}  (or start via Android Studio)"
        fi
    else
        echo "  [MISSING] ADB not in PATH"
        ERRORS=$((ERRORS + 1))
    fi
    echo ""

    # 4. Flow files
    echo "  --- Maestro Flows ---"
    IOS_FLOWS=$(find e2e/maestro/ios -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
    ANDROID_FLOWS=$(find e2e/maestro/android -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
    echo "  [INFO] iOS flows: $IOS_FLOWS"
    echo "  [INFO] Android flows: $ANDROID_FLOWS"
    echo ""

    # Summary
    if [[ $ERRORS -gt 0 ]]; then
        echo "RESULT: $ERRORS issue(s) found. Fix them before running Maestro tests."
        exit 1
    fi
    echo "RESULT: Environment is ready for Maestro testing."

# Run Maestro iOS flows (requires booted simulator)
[group('e2e')]
[script]
e2e-ios flow="create_identity":
    set -euo pipefail
    if ! command -v maestro &>/dev/null; then
        echo "Error: Maestro CLI not found. Run 'just maestro-setup' for instructions."
        exit 1
    fi

    FLOW_PATH="e2e/maestro/ios/{{flow}}.yaml"
    if [[ ! -f "$FLOW_PATH" ]]; then
        echo "Error: Flow not found: $FLOW_PATH"
        echo "Available iOS flows:"
        find e2e/maestro/ios -name "*.yaml" -exec basename {} .yaml \; | sort | sed 's/^/  /'
        exit 1
    fi

    echo "Running iOS flow: {{flow}}"
    maestro test "$FLOW_PATH" --platform ios

# Run Maestro Android flows (requires running emulator)
[group('e2e')]
[script]
e2e-android flow="create_identity":
    set -euo pipefail
    if ! command -v maestro &>/dev/null; then
        echo "Error: Maestro CLI not found. Run 'just maestro-setup' for instructions."
        exit 1
    fi

    FLOW_PATH="e2e/maestro/android/{{flow}}.yaml"
    if [[ ! -f "$FLOW_PATH" ]]; then
        echo "Error: Flow not found: $FLOW_PATH"
        echo "Available Android flows:"
        find e2e/maestro/android -name "*.yaml" -exec basename {} .yaml \; | sort | sed 's/^/  /'
        exit 1
    fi

    echo "Running Android flow: {{flow}}"
    maestro test "$FLOW_PATH" --platform android

# Run all Maestro flows on both platforms
[group('e2e')]
[script]
e2e-maestro platform="all":
    set -euo pipefail
    if ! command -v maestro &>/dev/null; then
        echo "Error: Maestro CLI not found. Run 'just maestro-setup' for instructions."
        exit 1
    fi

    run_platform() {
        local plat="$1"
        local dir="e2e/maestro/$plat"
        # Maestro 2.x does not inherit arbitrary shell env vars; pass the
        # documented flow variables explicitly via --env.
        local maestro_env=(
            --env "NAME=${NAME:-E2E Test}"
            --env "FIELD_TYPE=${FIELD_TYPE:-Email}"
            --env "FIELD_LABEL=${FIELD_LABEL:-Work}"
            --env "FIELD_VALUE=${FIELD_VALUE:-test@example.com}"
            --env "APP_PASSWORD=${APP_PASSWORD:-TestPass123!}"
            --env "DURESS_PIN=${DURESS_PIN:-654321}"
            --env "DECOY_NAME=${DECOY_NAME:-Decoy Contact}"
            --env "REAL_CONTACT_NAME=${REAL_CONTACT_NAME:-E2E Test}"
            --env "CONTACT_NAME=${CONTACT_NAME:-E2E Test}"
            --env "LABEL_NAME=${LABEL_NAME:-VIP}"
            --env "ALERT_MESSAGE=${ALERT_MESSAGE:-Emergency alert test}"
            --env "QR_DATA=${QR_DATA:-vauchi://exchange#test}"
        )

        # Flows that require two physical devices to complete the exchange /
        # device-link protocol. They are skipped by default because they need a
        # second device actively running the app, not just two devices attached.
        # Set E2E_MULTI_DEVICE=1 to run them (CI jobs that provision a pair of
        # devices should enable this).
        local multi_device_flows=(
            complete_exchange
            link_device
        )

        # Flows that require at least one contact to exist in the address book.
        # On a single device contacts can only be created by exchanging with a
        # peer, so these are skipped unless contact state is set up externally.
        # Set E2E_CONTACT_SETUP=1 once a contact-seeding flow is available.
        local contact_dependent_flows=(
            configure_emergency_broadcast
            get_card
            hide_contact
            send_emergency_broadcast
            visibility_labels
            # Duress PIN setup requires selecting a real contact as the
            # alert recipient (Save is gated on >=1 recipient);
            # single-device runs have no contacts (decoys live in a
            # separate table and never appear in the recipient list).
            setup_duress_pin
            duress_unlock
        )

        # Flows that exercise app-password / duress-PIN auth. They change the
        # auth state of the running app and require password entry on cold
        # starts; the current Maestro flows do not handle that entry yet, so
        # they are skipped by default. Set E2E_AUTH_FLOWS=1 to run them once
        # the auth-entry steps are added.
        local auth_dependent_flows=(
            setup_app_password
            setup_duress_pin
            duress_unlock
        )

        # Flows that depend on fragile UI interactions or non-trivial state
        # transitions that are not yet robust in the default single-device run.
        # Set E2E_EDGE_FLOWS=1 to run them once they are hardened.
        local edge_flows=(
            delete_decoy_contact
            emergency_shred
            identity_purge
        )

        # Explicit ordering respects dependencies between stateful flows.
        # create_identity must be first; add_custom_group must be last because
        # it uses clearState and resets onboarding. emergency_shred and
        # identity_purge are destructive and run near the end.
        local ordered_flows=(
            "$dir/create_identity.yaml"
            "$dir/add_decoy_contact.yaml"
            "$dir/add_field.yaml"
            "$dir/generate_qr.yaml"
            "$dir/list_contacts.yaml"
            "$dir/setup_app_password.yaml"
            "$dir/setup_duress_pin.yaml"
            "$dir/delete_decoy_contact.yaml"
            "$dir/sync.yaml"
            "$dir/identity_purge.yaml"
            "$dir/emergency_shred.yaml"
            "$dir/duress_unlock.yaml"
            "$dir/add_custom_group.yaml"
        )

        local run_multi_device=${E2E_MULTI_DEVICE:-0}
        local run_contact_dependent=${E2E_CONTACT_SETUP:-0}
        local run_auth_flows=${E2E_AUTH_FLOWS:-0}
        local run_edge_flows=${E2E_EDGE_FLOWS:-0}

        echo "═══ Running all $plat Maestro flows ═══"
        for flow in "${ordered_flows[@]}"; do
            name=$(basename "$flow" .yaml)

            if [[ " ${multi_device_flows[*]} " == *" $name "* && "$run_multi_device" != "1" ]]; then
                echo "  → $name"
                echo "  ⊘ SKIPPED: set E2E_MULTI_DEVICE=1 to run multi-device exchange/link flows"
                continue
            fi

            if [[ " ${contact_dependent_flows[*]} " == *" $name "* && "$run_contact_dependent" != "1" ]]; then
                echo "  → $name"
                echo "  ⊘ SKIPPED: set E2E_CONTACT_SETUP=1 to run flows that require a contact"
                continue
            fi

            if [[ " ${auth_dependent_flows[*]} " == *" $name "* && "$run_auth_flows" != "1" ]]; then
                echo "  → $name"
                echo "  ⊘ SKIPPED: set E2E_AUTH_FLOWS=1 to run app-password / duress flows"
                continue
            fi

            if [[ " ${edge_flows[*]} " == *" $name "* && "$run_edge_flows" != "1" ]]; then
                echo "  → $name"
                echo "  ⊘ SKIPPED: set E2E_EDGE_FLOWS=1 to run fragile edge-case flows"
                continue
            fi

            echo "  → $name"
            maestro test "$flow" --platform "$plat" "${maestro_env[@]}" || {
                echo "  ✗ FAILED: $name"
                return 1
            }
            echo "  ✓ $name"
        done
        echo ""
    }

    case "{{platform}}" in
        ios)     run_platform ios ;;
        android) run_platform android ;;
        all)
            run_platform ios
            run_platform android
            ;;
        *)
            echo "Error: Unknown platform '{{platform}}'. Use: ios, android, or all"
            exit 1
            ;;
    esac
    echo "All Maestro flows completed."

# Run the MVP-critical Maestro flows (Layer 3 gate subset).
# Plan: _private/docs/planning/todo/2026-04-20-frontend-correctness-strategy-plan.md
# Task 3.3. Runs the five user-critical flows only (not the full
# e2e/maestro tree), suitable for nightly CI without burning the
# full ~20-flow budget every run.
#
# Flows:
#   add_field.yaml           — text input commit + "my info" roundtrip
#   add_custom_group.yaml    — regression for `submit_custom_group` bug
#   generate_qr.yaml         — QR exchange single-device hand-off point
#   sync.yaml                — sync trigger + post-state
#   create_identity.yaml     — prerequisite for the others
[group('e2e')]
[script]
e2e-maestro-critical platform="all" device="":
    set -euo pipefail
    if ! command -v maestro &>/dev/null; then
        echo "Error: Maestro CLI not found. Run 'just maestro-setup' for instructions."
        exit 1
    fi

    MVP_FLOWS=(
        create_identity
        add_field
        generate_qr
        sync
        add_custom_group
    )

    run_critical() {
        local plat="$1"
        local dir="e2e/maestro/$plat"
        local device_args=()
        if [[ -n "{{ device }}" ]]; then
            device_args+=(--device "{{ device }}")
        fi
        # Maestro 2.x does not inherit arbitrary shell env vars; pass the
        # flow parameters explicitly via --env. Defaults match the documented
        # variables in add_field.yaml / create_identity.yaml.
        local maestro_env=(
            --env "NAME=${NAME:-E2E Test}"
            --env "FIELD_TYPE=${FIELD_TYPE:-Email}"
            --env "FIELD_LABEL=${FIELD_LABEL:-Work}"
            --env "FIELD_VALUE=${FIELD_VALUE:-test@example.com}"
        )
        echo "═══ Running MVP-critical $plat Maestro flows ═══"
        for name in "${MVP_FLOWS[@]}"; do
            local flow="$dir/$name.yaml"
            if [[ ! -f "$flow" ]]; then
                echo "  SKIP: $name (not present on $plat)"
                continue
            fi
            echo "  → $name"
            if maestro "${device_args[@]}" test "$flow" --platform "$plat" "${maestro_env[@]}"; then
                echo "  ✓ $name"
            else
                echo "  ✗ FAILED: $name"
                return 1
            fi
        done
    }

    case "{{platform}}" in
        ios)     run_critical ios ;;
        android) run_critical android ;;
        all)
            run_critical ios
            run_critical android
            ;;
        *)
            echo "Error: Unknown platform '{{platform}}'. Use: ios, android, or all"
            exit 1
            ;;
    esac
    echo "Critical Maestro flows completed."

# Run a two-device protocol scenario via the Phase 4 orchestrator.
# Plan: _private/docs/planning/todo/2026-04-20-frontend-correctness-strategy-plan.md
# Task 4.4. Boots two Android emulators (VAUCHI_AVD_{A,B}),
# installs `android/app/build/outputs/apk/debug/app-debug.apk` on
# both, and runs the requested scenario from
# `e2e/two-device/scenarios/`. Tears down cleanly on exit.
#
# Status: SCAFFOLD. Configure two AVDs named `vauchi-test-0` and
# `vauchi-test-1` (or override via env), then:
#   just e2e-two-device symmetric_exchange
# See the runbook at
# `_private/docs/reference/2026-04-20-two-device-test-runbook.md`.
[group('e2e')]
[script]
e2e-two-device scenario:
    set -euo pipefail
    ./e2e/two-device/orchestrator.sh "{{scenario}}"

# ─── Relay ──────────────────────────────────────────────────────

# Start local TLS relay for E2E testing
[group('e2e')]
e2e-relay:
    ./scripts/scripts/e2e/orchestrate.sh relay

# Setup local CA for TLS relay
[group('e2e')]
e2e-relay-setup:
    ./scripts/scripts/e2e/orchestrate.sh relay-setup

# ─── Website E2E ──────────────────────────────────────────────────

# Run website Playwright tests locally (theme toggle + language switching)
[group('e2e')]
e2e-website:
    cd website && npm test

# Run website Playwright tests against deployed site
[group('e2e')]
e2e-website-deployed:
    cd website && BASE_URL=https://vauchi.app npm test
