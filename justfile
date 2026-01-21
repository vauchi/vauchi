# Vauchi Development Commands
# Usage: just <recipe>
# Install just: cargo install just
#
# Quick start from meta-repo:
#   git clone git@gitlab.com:vauchi/vauchi.git
#   cd vauchi
#   just setup

set dotenv-load := true
set shell := ["bash", "-cu"]

# Default relay URL for local development
default_relay := "ws://localhost:8080"

# GitLab base URL
gitlab_base := "git@gitlab.com:vauchi"

# Public repositories to clone
public_repos := "core relay cli tui desktop e2e features android ios website docs assets dev-tools"

# === Workspace Setup ===

# Clone all repos and set up workspace (run this first after cloning meta-repo)
setup: clone-repos setup-dirs
    @echo ""
    @echo "Workspace setup complete!"
    @echo ""
    @echo "Next steps:"
    @echo "  just build      # Build Rust workspace"
    @echo "  just check      # Run all checks"
    @echo "  just help       # Show all commands"

# Clone all public repositories
clone-repos:
    #!/usr/bin/env bash
    set -e
    echo "Cloning repositories from gitlab.com/vauchi..."
    for repo in {{public_repos}}; do
        if [[ -d "$repo" ]]; then
            echo "  $repo already exists, skipping"
        else
            echo "  Cloning $repo..."
            git clone "{{gitlab_base}}/$repo.git" "$repo" 2>/dev/null || echo "  Failed to clone $repo (may not have access)"
        fi
    done

# Clone a single repository
clone repo:
    #!/usr/bin/env bash
    if [[ -d "{{repo}}" ]]; then
        echo "{{repo}} already exists"
    else
        git clone "{{gitlab_base}}/{{repo}}.git" "{{repo}}"
    fi

# Update all repos (pull latest)
pull-all:
    #!/usr/bin/env bash
    set -e
    echo "Pulling latest changes..."
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            repo=$(basename "$dir")
            echo "  $repo"
            (cd "$dir" && git pull --rebase 2>/dev/null || git pull) || true
        fi
    done

# Set up tmp and cache directories
setup-dirs:
    mkdir -p tmp cache
    @echo '*' > tmp/.gitignore
    @echo '!.gitignore' >> tmp/.gitignore
    @echo '*' > cache/.gitignore
    @echo '!.gitignore' >> cache/.gitignore

# === Quick Start ===

# Run all checks (format, lint, test)
check: fmt-check lint test

# Build everything for development
build: build-rust

# === Rust ===

# Run all Rust tests
test:
    cd core && cargo test --workspace

# Run tests for a specific crate
test-crate crate:
    cd core && cargo test -p {{crate}}

# Run relay integration tests
test-relay-integration:
    cd relay && cargo test

# Run core tests only
test-core:
    cd core && cargo test -p vauchi-core

# Run clippy lints
lint:
    cd core && cargo clippy --workspace -- -D warnings

# Format code
fmt:
    cd core && cargo fmt --all

# Check formatting without changes
fmt-check:
    cd core && cargo fmt --all -- --check

# Run security audit
audit:
    cd core && cargo audit
    cd core && cargo deny check

# Build Rust workspace (debug)
build-rust:
    cd core && cargo build --workspace

# Build Rust workspace (release)
build-rust-release:
    cd core && cargo build --workspace --release

# Start relay server
relay:
    cd relay && cargo run

# Start relay server with debug logging
relay-debug:
    RUST_LOG=debug cd relay && cargo run

# Run TUI application
tui:
    cd tui && cargo run

# Initialize a new CLI identity
cli-init name:
    cd cli && cargo run -- init "{{name}}"

# === Benchmarks ===

# Run core crypto benchmarks
bench-core:
    cd core && cargo bench -p vauchi-core

# Run FFI benchmarks
bench-ffi:
    cd core && cargo bench -p vauchi-mobile

# === Android ===

# Build Android native libraries (debug)
build-android-debug:
    ./core/scripts/build-android.sh debug

# Build Android native libraries (release)
build-android-release:
    ./core/scripts/build-android.sh release

# Build Android APK (debug)
android-debug: build-android-debug
    cd android && ./gradlew assembleDebug

# Build Android APK (release)
android-release: build-android-release
    cd android && ./gradlew assembleRelease

# Run Android unit tests
test-android:
    cd android && ./gradlew test

# Clean Android build
clean-android:
    cd android && ./gradlew clean

# === iOS (macOS only) ===

# Build iOS framework (debug)
build-ios-debug:
    BUILD_MODE=debug ./ios/build-ios.sh

# Build iOS XCFramework (release)
build-ios-release:
    BUILD_MODE=release ./ios/build-ios.sh xcframework

# Clean iOS build artifacts
clean-ios:
    rm -rf ios/Frameworks ios/Vauchi/Generated

# === Desktop (Tauri) ===

# Run desktop in dev mode
desktop-dev:
    cd desktop && cargo tauri dev

# Build desktop release
desktop-release:
    cd desktop && cargo tauri build

# === UniFFI Bindings ===

# Build, test, and generate UniFFI mobile bindings
build-uniffi:
    cd core && cargo build -p vauchi-mobile
    cd core && cargo test -p vauchi-mobile
    ./core/scripts/build-bindings.sh

# Generate mobile bindings (without build/test)
bindings:
    ./core/scripts/build-bindings.sh

# === Documentation ===

# Generate and open Rust docs
docs:
    cd core && cargo doc --workspace --no-deps --open

# === CI Simulation ===

# Run full CI pipeline locally
ci: check audit
    @echo "CI checks passed!"

# Run full CI including Android tests
ci-full: ci test-android
    @echo "Full CI checks passed!"

# === Code Quality ===

# Run all code quality checks
quality: fmt-check lint audit
    @echo "Code quality checks passed!"

# Verify roadmap claims match actual project state
verify-roadmap:
    ./dev-tools/scripts/verify-roadmap.sh

# Run CI with roadmap verification (catches false "done" claims)
ci-verify: ci verify-roadmap
    @echo "CI + roadmap verification passed!"

# Fix common issues automatically
fix:
    cd core && cargo fmt --all
    cd core && cargo clippy --workspace --fix --allow-dirty --allow-staged

# === Coverage ===

# Run tests with coverage (requires cargo-llvm-cov)
coverage:
    cd core && cargo llvm-cov --workspace --html
    @echo "Coverage report generated at code/target/llvm-cov/html/index.html"

# Verify coverage against threshold
coverage-verify threshold="90":
    ./dev-tools/scripts/coverage-verify.sh --threshold {{threshold}}

# Run coverage automation setup and report
coverage-setup:
    ./dev-tools/scripts/coverage/setup-coverage-automation.sh

# Check coverage summary (quick check)
coverage-check threshold="80":
    python3 dev-tools/scripts/coverage/check-coverage.py {{threshold}}

# === Cleanup ===

# Clean all Rust build artifacts
clean-rust:
    cd core && cargo clean

# Clean all build artifacts
clean: clean-rust clean-android clean-ios
    @echo "All build artifacts cleaned"

# === Version Management ===

# Show current versions
versions:
    @echo "Rust workspace versions:"
    @cd core && cargo metadata --format-version 1 | jq -r '.packages[] | select(.source == null) | "\(.name): \(.version)"'

# === Changesets ===

# Add a new changeset
changeset:
    npx changeset add

# Check changeset status
changeset-status:
    npx changeset status

# Version packages based on changesets
changeset-version:
    npm run changeset:version

# Publish release (usually done by CI)
changeset-publish:
    npm run changeset:publish

# Full release workflow: version + sync + commit
release: changeset-version
    @echo "Review changes with: git diff"
    @echo "Then commit with: git add -A && git commit -m 'chore: version packages'"

# === Development Utilities ===

# Watch for changes and run tests
watch:
    cd core && cargo watch -x "test --workspace"

# Watch for changes and run specific crate tests
watch-crate crate:
    cd core && cargo watch -x "test -p {{crate}}"

# === Git Hooks ===

# Install git hooks
install-hooks:
    cp dev-tools/hooks/* .git/hooks/
    chmod +x .git/hooks/*
    @echo "Git hooks installed"

# === Dev Tools ===

# Audit test coverage against Gherkin feature files
feature-audit:
    ./dev-tools/scripts/feature-audit.sh

# Run full test suite (Rust + Android + iOS + Desktop E2E)
test-all:
    ./core/scripts/test-all.sh

# Test relay connectivity
relay-test:
    cd relay && cargo test

# Bump version across all components (Rust, Android, iOS)
bump-version version:
    ./dev-tools/scripts/bump-version.sh {{version}}

# Sync all git repos in workspace
sync-repos:
    ./dev-tools/scripts/sync-all.sh

# Show sync status of all repos
sync-status:
    ./dev-tools/scripts/sync-all.sh -s

# Interactive commit across all repos with changes
commit:
    ./dev-tools/scripts/commit-interactive.sh

# === TDD ===

# Setup TDD environment for a component or with options
tdd-setup *args:
    ./dev-tools/scripts/tdd-setup.sh {{args}}

# Create a new TDD test from template
tdd-test type name:
    ./dev-tools/scripts/tdd-template.sh {{type}} {{name}}

# Check for inline tests in src/ directories (should be in tests/)
check-inline-tests:
    ./dev-tools/scripts/check_inline_tests.sh

# Analyze inline tests that could be extracted
analyze-inline-tests:
    python3 dev-tools/scripts/refactor_tests.py analyze

# Extract inline tests to tests/ directories (creates backup)
extract-inline-tests:
    python3 dev-tools/scripts/refactor_tests.py extract

# === Multi-Instance Testing ===
# Run multiple app instances with isolated data for testing sync/exchange

# Start local relay server (memory storage, no persistence)
dev-relay:
    ./dev-tools/scripts/dev/local-relay.sh

# Run CLI with isolated data directory (e.g., just dev-cli alice init "Alice Smith")
[positional-arguments]
dev-cli *args:
    #!/usr/bin/env bash
    ./dev-tools/scripts/dev/multi-cli.sh "$@"

# Run TUI with isolated data directory (e.g., just dev-tui alice)
dev-tui instance:
    ./dev-tools/scripts/dev/multi-tui.sh {{instance}}

# List test instances
dev-list:
    ./dev-tools/scripts/dev/multi-cli.sh list

# Clean test data (tmp directory)
dev-clean-tmp:
    ./dev-tools/scripts/dev/cleanup.sh tmp

# Clean caches (AVDs, DerivedData)
dev-clean-cache:
    ./dev-tools/scripts/dev/cleanup.sh cache

# Clean all test data and caches
dev-clean-all:
    ./dev-tools/scripts/dev/cleanup.sh all

# Show disk usage of tmp and cache directories
dev-status:
    ./dev-tools/scripts/dev/cleanup.sh status

# === E2E Testing ===

# Run E2E tests (requires relay and CLI binaries)
e2e-test: build-rust
    cd e2e && cargo test -- --ignored --nocapture

# Run E2E tests without building first (assumes binaries exist)
e2e-test-quick:
    cd e2e && cargo test -- --ignored --nocapture

# Run a specific E2E test
e2e-test-one test_name:
    cd e2e && cargo test {{test_name}} -- --ignored --nocapture

# Run E2E tests in release mode (faster)
e2e-test-release: build-rust-release
    cd e2e && cargo test --release -- --ignored --nocapture

# Run only the five-user exchange E2E test
e2e-five-users: build-rust
    cd e2e && cargo test five_user -- --ignored --nocapture

# Run only relay failover E2E tests
e2e-failover: build-rust
    cd e2e && cargo test relay_failover -- --ignored --nocapture

# Run only multi-device sync E2E tests
e2e-sync: build-rust
    cd e2e && cargo test multi_device -- --ignored --nocapture

# === Deployment ===

# Deploy vauchi-relay using Kamal
deploy-relay:
    kamal deploy -c infra/config/deploy.yml

# Show logs from vauchi-relay
relay-logs:
    kamal app logs -f -c infra/config/deploy.yml

# === AI/LLM Tools ===

# Quick codebase exploration using local LLM (ollama + qwen2:0.5b)
# Example: just tell-me-about "iOS tests"
tell-me-about *topic:
    ./dev-tools/scripts/tell-me-about.sh {{topic}}

# === Help ===

# Show structure overview with concise descriptions
structure-overview:
    #!/usr/bin/env bash
    echo "Vauchi Project Structure"
    echo "========================"
    tree -L 3 -I "node_modules|target|build|dist|.git|gradle|intermediates|generated|outputs|tmp|cache" --noreport
    echo ""
    echo "Directory Concerns:"
    echo "-------------------"
    echo "core/             - Core library and mobile bindings"
    echo "  vauchi-core/    - Crypto, X3DH, Double Ratchet, SQLite storage"
    echo "  vauchi-mobile/  - UniFFI bindings for Android/iOS"
    echo "relay/            - WebSocket relay server (standalone)"
    echo "cli/              - Command-line interface"
    echo "tui/              - Terminal user interface"
    echo "desktop/          - Tauri + SolidJS desktop app"
    echo "e2e/              - End-to-end tests"
    echo "android/          - Android application (Kotlin/Compose)"
    echo "ios/              - iOS application (Swift/SwiftUI)"
    echo "docs/             - Architecture, planning, development guides"
    echo "features/         - Gherkin .feature files for TDD"
    echo "dev-tools/        - Git hooks and helper scripts"
    echo "website/          - Project landing page"

# Show all available recipes
help:
    @just --list
