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
