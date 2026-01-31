# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# End-to-end testing recipes

# ═══════════════════════════════════════════════════════════════════
# E2E TESTING
# ═══════════════════════════════════════════════════════════════════

# List available E2E tests
e2e:
    @echo "Available E2E tests:"
    @cd e2e && cargo test -- --list --ignored 2>&1 | grep '^test_' | sed 's/: test//'
    @echo ""
    @echo "Run with: just e2e-run <name>  (or 'all' for all tests)"

# Run E2E test(s) - use 'all' to run everything
e2e-run name: build build-cli build-relay
    #!/usr/bin/env bash
    if [[ "{{name}}" == "all" ]]; then
        cd e2e && cargo test -- --ignored --nocapture
    else
        cd e2e && cargo test {{name}} -- --ignored --nocapture
    fi

# Run E2E smoke tests (fast, for every push)
e2e-smoke: build-cli build-relay
    #!/usr/bin/env bash
    echo "Running E2E smoke tests..."
    cd e2e && cargo test smoke_ -- --ignored --nocapture
    echo ""
    echo "Smoke tests complete."

# Run E2E release tests (full validation)
e2e-release: build-cli build-relay
    #!/usr/bin/env bash
    echo "Running full E2E test suite for release validation..."
    cd e2e && cargo test -- --ignored --nocapture
    echo ""
    echo "Release validation complete."

# Run E2E integration tests only (excludes smoke)
e2e-integration: build-cli build-relay
    #!/usr/bin/env bash
    echo "Running E2E integration tests..."
    cd e2e && cargo test integration_ -- --ignored --nocapture
    echo ""
    echo "Integration tests complete."

# Run a YAML scenario by name
e2e-yaml name:
    #!/usr/bin/env bash
    cd e2e && cargo run --example yaml_runner -- "{{name}}"

# List available YAML scenarios
e2e-yaml-list:
    #!/usr/bin/env bash
    echo "Available YAML scenarios:"
    find e2e/scenarios -name "*.yaml" -o -name "*.yml" 2>/dev/null | while read f; do
        name=$(basename "$f" .yaml)
        dir=$(dirname "$f" | xargs basename)
        echo "  $dir/$name"
    done

# Show manual instructions for a YAML scenario
e2e-yaml-manual name:
    #!/usr/bin/env bash
    cd e2e && cargo run --example yaml_runner -- "{{name}}" --manual

# Show E2E test coverage against Gherkin features
e2e-coverage:
    #!/usr/bin/env bash
    echo "E2E Test Coverage Report"
    echo "========================"
    echo ""
    echo "Gherkin Features:"
    feature_count=$(find features -name "*.feature" 2>/dev/null | wc -l)
    echo "  Total feature files: $feature_count"
    echo ""
    echo "Rust E2E Tests:"
    rust_tests=$(cd e2e && cargo test -- --list --ignored 2>&1 | grep -c "^smoke_\|^integration_" || echo 0)
    echo "  Smoke tests: $(cd e2e && cargo test -- --list --ignored 2>&1 | grep -c "^smoke_" || echo 0)"
    echo "  Integration tests: $(cd e2e && cargo test -- --list --ignored 2>&1 | grep -c "^integration_" || echo 0)"
    echo ""
    echo "YAML Scenarios:"
    yaml_smoke=$(find e2e/scenarios/smoke -name "*.yaml" 2>/dev/null | wc -l)
    yaml_integration=$(find e2e/scenarios/integration -name "*.yaml" 2>/dev/null | wc -l)
    yaml_edge=$(find e2e/scenarios/edge -name "*.yaml" 2>/dev/null | wc -l)
    echo "  Smoke: $yaml_smoke"
    echo "  Integration: $yaml_integration"
    echo "  Edge cases: $yaml_edge"
    echo ""
    echo "Feature Traceability:"
    echo "  (Scenarios referencing Gherkin features)"
    grep -h "^feature:" e2e/scenarios/*/*.yaml 2>/dev/null | sort -u | sed 's/feature: /  - /'

# Build CLI binary (into shared target dir for e2e tests)
build-cli:
    cd cli && cargo build --target-dir ../target

# Build relay binary (into shared target dir for e2e tests)
build-relay:
    cd relay && cargo build --target-dir ../target

# ═══════════════════════════════════════════════════════════════
# CROSS-PLATFORM E2E TESTING
# ═══════════════════════════════════════════════════════════════

# Check E2E testing status (all platforms)
e2e-status:
    ./scripts/scripts/e2e/orchestrate.sh status

# Clean all E2E test data
e2e-clean:
    ./scripts/scripts/e2e/orchestrate.sh clean

# Show E2E setup guide
e2e-setup:
    ./scripts/scripts/e2e/orchestrate.sh setup

# Show E2E infrastructure as Mermaid diagram
e2e-map:
    ./scripts/scripts/e2e/orchestrate.sh map

# List available E2E test scenarios
e2e-scenarios:
    ./scripts/scripts/e2e/orchestrate.sh scenarios

# Run an E2E test scenario (use 'all' to run all automated scenarios)
e2e-scenario name="":
    ./scripts/scripts/e2e/orchestrate.sh scenario {{name}}

# Run all automated E2E scenarios and show results report
e2e-scenario-all:
    ./scripts/scripts/e2e/orchestrate.sh scenario all

# Show latest E2E test report
e2e-report:
    ./scripts/scripts/e2e/orchestrate.sh report

# Teardown E2E infrastructure (stop relay, clean all test data)
e2e-teardown-and-clean-infra:
    ./scripts/scripts/e2e/orchestrate.sh teardown

# ─── CLI E2E ────────────────────────────────────────────────────

# Run CLI command for instance (e.g., just e2e-cli alice init "Alice")
[positional-arguments]
e2e-cli *args:
    ./scripts/scripts/e2e/orchestrate.sh cli "$@"

# Run CLI exchange test between two instances
e2e-cli-test alice="alice" bob="bob":
    ./scripts/scripts/e2e/orchestrate.sh cli-test {{alice}} {{bob}}

# ─── TUI E2E ────────────────────────────────────────────────────

# Launch TUI for instance (e.g., just e2e-tui alice)
e2e-tui instance:
    ./scripts/scripts/e2e/orchestrate.sh tui {{instance}}

# Launch multiple TUI instances in separate terminals
e2e-tui-multi *instances:
    ./scripts/scripts/e2e/orchestrate.sh tui-multi {{instances}}

# ─── Desktop E2E ────────────────────────────────────────────────

# Launch desktop app for instance
e2e-desktop instance="default":
    ./scripts/scripts/e2e/orchestrate.sh desktop {{instance}}

# Launch desktop in dev mode for instance
e2e-desktop-dev instance="default":
    ./scripts/scripts/e2e/orchestrate.sh desktop-dev {{instance}}

# Build desktop release binary
e2e-desktop-build:
    ./scripts/scripts/e2e/orchestrate.sh desktop-build

# ─── Mobile E2E ─────────────────────────────────────────────────

# Deploy apps to all mobile devices (iOS + Android)
e2e-deploy:
    ./scripts/scripts/e2e/orchestrate.sh deploy

# Deploy iOS app to macOS VM simulator
e2e-deploy-ios:
    ./scripts/scripts/e2e/orchestrate.sh deploy-ios

# Deploy Android APK to local emulator
e2e-deploy-android:
    ./scripts/scripts/e2e/orchestrate.sh deploy-android

# Start Android emulator manually (with xcb Qt platform for Wayland compatibility)
e2e-android-start avd="Pixel_7":
    QT_QPA_PLATFORM=xcb emulator -avd {{avd}} -gpu auto

# Run interactive mobile E2E test session
e2e-test-mobile:
    ./scripts/scripts/e2e/orchestrate.sh test

# Take screenshots from mobile devices
e2e-screenshot:
    ./scripts/scripts/e2e/orchestrate.sh screenshot

# Collect logs from mobile devices
e2e-logs:
    ./scripts/scripts/e2e/orchestrate.sh logs

# ─── Relay ──────────────────────────────────────────────────────

# Start local TLS relay for E2E testing
e2e-relay:
    ./scripts/scripts/e2e/orchestrate.sh relay

# Setup local CA for TLS relay
e2e-relay-setup:
    ./scripts/scripts/e2e/orchestrate.sh relay-setup
