# Vauchi Development Commands
# Usage: just <recipe>
#
# Quick start:
#   git clone git@gitlab.com:vauchi/vauchi.git && cd vauchi
#   just setup
#   just check

set dotenv-load := true
set shell := ["bash", "-cu"]

# GitLab base URL
gitlab_base := "git@gitlab.com:vauchi"

# Public repositories
public_repos := "core relay cli tui desktop e2e features android ios website docs assets dev-tools"

# ═══════════════════════════════════════════════════════════════════
# DAILY COMMANDS - Use these regularly
# ═══════════════════════════════════════════════════════════════════

# Run all checks (format, lint, test)
check: fmt-check lint test

# Build core workspace
build:
    cd core && cargo build --workspace

# Run tests
test:
    cd core && cargo test --workspace

# Format code
fmt:
    cd core && cargo fmt --all

# Check formatting (no changes)
fmt-check:
    cd core && cargo fmt --all -- --check

# Run clippy lints
lint:
    cd core && cargo clippy --workspace -- -D warnings

# Interactive commit across repos with changes
commit:
    ./dev-tools/scripts/commit-interactive.sh

# ═══════════════════════════════════════════════════════════════════
# APPLICATIONS - Run local services
# ═══════════════════════════════════════════════════════════════════

# Start relay server
relay:
    cd relay && cargo run

# Run TUI application
tui:
    cd tui && cargo run

# Run desktop in dev mode
desktop-dev:
    cd desktop && cargo tauri dev

# ═══════════════════════════════════════════════════════════════════
# SETUP & MAINTENANCE
# ═══════════════════════════════════════════════════════════════════

# Clone all repos and set up workspace (run first after cloning meta-repo)
setup: clone-repos
    mkdir -p tmp cache
    @echo "Workspace ready! Run: just check"

# Clone all public repositories
clone-repos:
    #!/usr/bin/env bash
    set -e
    echo "Cloning repositories..."
    for repo in {{public_repos}}; do
        if [[ -d "$repo" ]]; then
            echo "  $repo (exists)"
        else
            git clone "{{gitlab_base}}/$repo.git" "$repo" 2>/dev/null || echo "  $repo (skipped)"
        fi
    done

# Pull latest changes from all repos
pull-all:
    #!/usr/bin/env bash
    for dir in */; do
        [[ -d "${dir}.git" ]] && (cd "$dir" && git pull --rebase 2>/dev/null || git pull) || true
    done

# Push all repos with commits ahead of origin
push-all:
    #!/usr/bin/env bash
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            ahead=$(cd "$dir" && git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
            if [[ "$ahead" -gt 0 ]]; then
                echo "Pushing $dir ($ahead commits ahead)"
                (cd "$dir" && git push)
            fi
        fi
    done

# Clean all build artifacts
clean:
    cd core && cargo clean
    rm -rf tmp/* cache/*

# Run tests with coverage
coverage:
    cd core && cargo llvm-cov --workspace --html
    @echo "Report: core/target/llvm-cov/html/index.html"

# Generate and open Rust docs
docs:
    cd core && cargo doc --workspace --no-deps --open

# Install git hooks
install-hooks:
    cp dev-tools/hooks/* .git/hooks/
    chmod +x .git/hooks/*

# Show all commands
help:
    @just --list

# ═══════════════════════════════════════════════════════════════════
# EXTENDED COMMANDS - Less frequently used
# ═══════════════════════════════════════════════════════════════════

# Run tests for specific crate
test-crate crate:
    cd core && cargo test -p {{crate}}

# Build release binaries
build-release:
    cd core && cargo build --workspace --release

# Run security audit
audit:
    cd core && cargo audit
    cd core && cargo deny check

# Auto-fix lint issues
fix:
    cd core && cargo fmt --all
    cd core && cargo clippy --workspace --fix --allow-dirty --allow-staged

# Watch for changes and run tests
watch:
    cd core && cargo watch -x "test --workspace"

# ═══════════════════════════════════════════════════════════════════
# MOBILE BUILDS
# ═══════════════════════════════════════════════════════════════════

# Build Android native libraries
build-android mode="debug":
    ./core/scripts/build-android.sh {{mode}}

# Build Android APK
android mode="debug": (build-android mode)
    cd android && ./gradlew assemble{{mode}}

# Build iOS framework (macOS only)
build-ios mode="debug":
    BUILD_MODE={{mode}} ./ios/build-ios.sh

# Generate UniFFI mobile bindings
bindings:
    ./core/scripts/build-bindings.sh

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

# ═══════════════════════════════════════════════════════════════════
# MULTI-INSTANCE DEV (testing sync between "devices")
# ═══════════════════════════════════════════════════════════════════

# Start local relay (memory storage)
dev-relay:
    ./dev-tools/scripts/dev/local-relay.sh

# Start local relay with TLS (for iOS/Android testing)
dev-relay-tls:
    ./dev-tools/scripts/dev/local-relay-tls.sh

# Setup local CA for mobile TLS testing
dev-relay-tls-setup:
    ./dev-tools/scripts/dev/local-relay-tls.sh --setup

# Run CLI with isolated data (e.g., just dev-cli alice init "Alice")
[positional-arguments]
dev-cli *args:
    ./dev-tools/scripts/dev/multi-cli.sh "$@"

# Run TUI with isolated data
dev-tui instance:
    ./dev-tools/scripts/dev/multi-tui.sh {{instance}}

# Clean test data
dev-clean:
    ./dev-tools/scripts/dev/cleanup.sh all

# Run E2E test checklist (manual device testing)
e2e-checklist *args:
    ./dev-tools/scripts/dev/e2e-test-checklist.sh {{ args }}

# ═══════════════════════════════════════════════════════════════
# CROSS-PLATFORM E2E TESTING
# ═══════════════════════════════════════════════════════════════

# Check E2E testing status (all platforms)
e2e-status:
    ./dev-tools/scripts/e2e/orchestrate.sh status

# Clean all E2E test data
e2e-clean:
    ./dev-tools/scripts/e2e/orchestrate.sh clean

# Show E2E setup guide
e2e-setup:
    ./dev-tools/scripts/e2e/orchestrate.sh setup

# Show E2E infrastructure as Mermaid diagram
e2e-map:
    ./dev-tools/scripts/e2e/orchestrate.sh map

# List available E2E test scenarios
e2e-scenarios:
    ./dev-tools/scripts/e2e/orchestrate.sh scenarios

# Run an E2E test scenario (use 'all' to run all automated scenarios)
e2e-scenario name="":
    ./dev-tools/scripts/e2e/orchestrate.sh scenario {{name}}

# Run all automated E2E scenarios and show results report
e2e-scenario-all:
    ./dev-tools/scripts/e2e/orchestrate.sh scenario all

# Show latest E2E test report
e2e-report:
    ./dev-tools/scripts/e2e/orchestrate.sh report

# Teardown E2E infrastructure (stop relay, clean all test data)
e2e-teardown-and-clean-infra:
    ./dev-tools/scripts/e2e/orchestrate.sh teardown

# ─── CLI E2E ────────────────────────────────────────────────────

# Run CLI command for instance (e.g., just e2e-cli alice init "Alice")
[positional-arguments]
e2e-cli *args:
    ./dev-tools/scripts/e2e/orchestrate.sh cli "$@"

# Run CLI exchange test between two instances
e2e-cli-test alice="alice" bob="bob":
    ./dev-tools/scripts/e2e/orchestrate.sh cli-test {{alice}} {{bob}}

# ─── TUI E2E ────────────────────────────────────────────────────

# Launch TUI for instance (e.g., just e2e-tui alice)
e2e-tui instance:
    ./dev-tools/scripts/e2e/orchestrate.sh tui {{instance}}

# Launch multiple TUI instances in separate terminals
e2e-tui-multi *instances:
    ./dev-tools/scripts/e2e/orchestrate.sh tui-multi {{instances}}

# ─── Desktop E2E ────────────────────────────────────────────────

# Launch desktop app for instance
e2e-desktop instance="default":
    ./dev-tools/scripts/e2e/orchestrate.sh desktop {{instance}}

# Launch desktop in dev mode for instance
e2e-desktop-dev instance="default":
    ./dev-tools/scripts/e2e/orchestrate.sh desktop-dev {{instance}}

# Build desktop release binary
e2e-desktop-build:
    ./dev-tools/scripts/e2e/orchestrate.sh desktop-build

# ─── Mobile E2E ─────────────────────────────────────────────────

# Deploy apps to all mobile devices (iOS + Android)
e2e-deploy:
    ./dev-tools/scripts/e2e/orchestrate.sh deploy

# Deploy iOS app to macOS VM simulator
e2e-deploy-ios:
    ./dev-tools/scripts/e2e/orchestrate.sh deploy-ios

# Deploy Android APK to local emulator
e2e-deploy-android:
    ./dev-tools/scripts/e2e/orchestrate.sh deploy-android

# Start Android emulator manually (with xcb Qt platform for Wayland compatibility)
e2e-android-start avd="Pixel_7":
    QT_QPA_PLATFORM=xcb emulator -avd {{avd}} -gpu auto

# Run interactive mobile E2E test session
e2e-test-mobile:
    ./dev-tools/scripts/e2e/orchestrate.sh test

# Take screenshots from mobile devices
e2e-screenshot:
    ./dev-tools/scripts/e2e/orchestrate.sh screenshot

# Collect logs from mobile devices
e2e-logs:
    ./dev-tools/scripts/e2e/orchestrate.sh logs

# ─── Relay ──────────────────────────────────────────────────────

# Start local TLS relay for E2E testing
e2e-relay:
    ./dev-tools/scripts/e2e/orchestrate.sh relay

# Setup local CA for TLS relay
e2e-relay-setup:
    ./dev-tools/scripts/e2e/orchestrate.sh relay-setup

# ═══════════════════════════════════════════════════════════════════
# DEPLOYMENT
# ═══════════════════════════════════════════════════════════════════

# Deploy relay using Kamal
deploy-relay:
    kamal deploy -c infra/config/deploy.yml

# Show relay logs
relay-logs:
    kamal app logs -f -c infra/config/deploy.yml

# ═══════════════════════════════════════════════════════════════════
# AI/LLM TOOLS
# ═══════════════════════════════════════════════════════════════════

# Explore codebase with local LLM (e.g., just tell-me-about "iOS tests")
tell-me-about *topic:
    ./dev-tools/scripts/tell-me-about.sh {{topic}}
