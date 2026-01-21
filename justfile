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
public_repos := "code features android ios website docs assets dev-tools"

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
    cd code && cargo test --workspace

# Run tests for a specific crate
test-crate crate:
    cd code && cargo test -p {{crate}}

# Run relay integration tests
test-relay-integration:
    ./code/vauchi-relay/scripts/test-integration.sh

# Run core tests only
test-core:
    cd code && cargo test -p vauchi-core

# Run clippy lints
lint:
    cd code && cargo clippy --workspace -- -D warnings

# Format code
fmt:
    cd code && cargo fmt --all

# Check formatting without changes
fmt-check:
    cd code && cargo fmt --all -- --check

# Run security audit
audit:
    cd code && cargo audit
    cd code && cargo deny check

# Build Rust workspace (debug)
build-rust:
    cd code && cargo build --workspace

# Build Rust workspace (release)
build-rust-release:
    cd code && cargo build --workspace --release

# Start relay server
relay:
    cd code && cargo run -p vauchi-relay

# Start relay server with debug logging
relay-debug:
    RUST_LOG=debug cd code && cargo run -p vauchi-relay

# Run TUI application
tui:
    cd code && cargo run -p vauchi-tui

# Initialize a new CLI identity
cli-init name:
    cd code && cargo run -p vauchi-cli -- init "{{name}}"

# === Benchmarks ===

# Run core crypto benchmarks
bench-core:
    cd code && cargo bench -p vauchi-core

# Run FFI benchmarks
bench-ffi:
    cd code && cargo bench -p vauchi-mobile

# === Android ===

# Build Android native libraries (debug)
build-android-debug:
    ./code/scripts/build-android.sh debug

# Build Android native libraries (release)
build-android-release:
    ./code/scripts/build-android.sh release

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
    cd code/vauchi-desktop && cargo tauri dev

# Build desktop release
desktop-release:
    cd code/vauchi-desktop && cargo tauri build

# === UniFFI Bindings ===

# Build, test, and generate UniFFI mobile bindings
build-uniffi:
    cd code && cargo build -p vauchi-mobile
    cd code && cargo test -p vauchi-mobile
    ./code/scripts/build-bindings.sh

# Generate mobile bindings (without build/test)
bindings:
    ./code/scripts/build-bindings.sh

# === Documentation ===

# Generate and open Rust docs
docs:
    cd code && cargo doc --workspace --no-deps --open

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
    cd code && cargo fmt --all
    cd code && cargo clippy --workspace --fix --allow-dirty --allow-staged

# === Coverage ===

# Run tests with coverage (requires cargo-llvm-cov)
coverage:
    cd code && cargo llvm-cov --workspace --html
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
    cd code && cargo clean

# Clean all build artifacts
clean: clean-rust clean-android clean-ios
    @echo "All build artifacts cleaned"

# === Version Management ===

# Show current versions
versions:
    @echo "Rust workspace versions:"
    @cd code && cargo metadata --format-version 1 | jq -r '.packages[] | select(.source == null) | "\(.name): \(.version)"'

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
    cd code && cargo watch -x "test --workspace"

# Watch for changes and run specific crate tests
watch-crate crate:
    cd code && cargo watch -x "test -p {{crate}}"

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
    ./code/scripts/test-all.sh

# Test relay connectivity (health, WebSocket, TLS)
relay-test host="relay.vauchi.app":
    ./code/scripts/relay-test.sh {{host}}

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
    tree -L 4 -I "node_modules|target|build|dist|.git|gradle|intermediates|generated|outputs|tmp|cache" --noreport
    echo ""
    echo "Directory Concerns:"
    echo "-------------------"
    echo "android/          - Android application (Kotlin/Compose)"
    echo "  app/src/        - Android source code"
    echo "ios/              - iOS application (Swift/SwiftUI)"
    echo "  Vauchi/         - iOS source code (ViewModels, Views, Services)"
    echo "code/             - Core implementation and tools"
    echo "  vauchi-core/    - Core library: crypto, X3DH, Double Ratchet, SQLite storage"
    echo "  vauchi-relay/   - Relay server: WebSocket handler for encrypted message delivery"
    echo "  vauchi-desktop/ - Desktop app: Tauri (Rust) + SolidJS frontend"
    echo "  vauchi-mobile/  - Mobile shared: UniFFI bindings for Android/iOS"
    echo "  vauchi-cli/     - CLI: Command-line tool for identity and exchange"
    echo "  vauchi-tui/     - TUI: Terminal-based user interface"
    echo "  scripts/        - Build and automation scripts"
    echo "docs/             - Documentation: architecture, planning, and development guides"
    echo "features/         - Specs: Gherkin .feature files for TDD"
    echo "dev-tools/        - Tooling: Git hooks and development helper scripts"
    echo "website/          - Marketing: Project landing page"

# Show all available recipes
help:
    @just --list
