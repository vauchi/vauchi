# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Multi-instance dev recipes (testing sync between "devices")

# ═══════════════════════════════════════════════════════════════════
# MULTI-INSTANCE DEV
# ═══════════════════════════════════════════════════════════════════

# Start local relay (memory storage)
[group('dev')]
dev-relay:
    ./scripts/scripts/dev/local-relay.sh

# Start local relay with TLS (for iOS/Android testing)
[group('dev')]
dev-relay-tls:
    ./scripts/scripts/dev/local-relay-tls.sh

# Setup local CA for mobile TLS testing
[group('dev')]
dev-relay-tls-setup:
    ./scripts/scripts/dev/local-relay-tls.sh --setup

# Run CLI with isolated data (e.g., just dev-cli alice init "Alice")
[group('dev')]
[positional-arguments]
dev-cli *args:
    ./scripts/scripts/dev/multi-cli.sh "$@"

# Run TUI with isolated data
[group('dev')]
dev-tui instance:
    ./scripts/scripts/dev/multi-tui.sh {{instance}}

# Clean test data
[group('dev')]
[confirm('This will clean all dev test data. Continue?')]
dev-clean:
    ./scripts/scripts/dev/cleanup.sh all

# Run E2E test checklist (manual device testing)
[group('dev')]
e2e-checklist *args:
    ./scripts/scripts/dev/e2e-test-checklist.sh {{ args }}

# ═══════════════════════════════════════════════════════════════════
# SCHEMA CHECK
# ═══════════════════════════════════════════════════════════════════

# Verify JSON schemas are up to date with core UI types
[group('dev')]
schema-check:
    cd core && cargo test --features schema-gen -p vauchi-core --test schema_gen

# ═══════════════════════════════════════════════════════════════════
# CORE FRESHNESS
# ═══════════════════════════════════════════════════════════════════

# Check if mobile bindings and Rust consumers are up to date with core
[group('dev')]
[script('bash')]
core-freshness:
    set -euo pipefail

    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    DIM='\033[2m'
    NC='\033[0m'

    ROOT="{{justfile_directory()}}"

    # Core HEAD
    CORE_HEAD=$(git -C "$ROOT/core" rev-parse HEAD)
    CORE_SHORT="${CORE_HEAD:0:8}"
    CORE_MSG=$(git -C "$ROOT/core" log -1 --format="%s" HEAD)

    # Latest core tag
    LATEST_TAG=$(git -C "$ROOT/core" describe --tags --abbrev=0 2>/dev/null || echo "none")
    if [ "$LATEST_TAG" != "none" ]; then
        AHEAD=$(git -C "$ROOT/core" rev-list "${LATEST_TAG}..HEAD" --count)
        if [ "$AHEAD" -eq 0 ]; then
            TAG_STATUS="${GREEN}at tag${NC}"
        else
            TAG_STATUS="${YELLOW}${AHEAD} commits ahead${NC}"
        fi
    else
        TAG_STATUS="${DIM}no tags${NC}"
        AHEAD="?"
    fi

    echo "=== Core ==="
    printf "  HEAD:       %s (%s)\n" "$CORE_SHORT" "$CORE_MSG"
    printf "  Latest tag: %s (%b)\n" "$LATEST_TAG" "$TAG_STATUS"
    echo ""

    # Rust consumers (path-overridden locally)
    echo "=== Rust Consumers (path-overridden locally) ==="
    for repo in cli tui desktop; do
        DIR="$ROOT/$repo"
        [ -d "$DIR" ] || continue
        CARGO_CONFIG="$DIR/.cargo/config.toml"
        [ "$repo" = "desktop" ] && CARGO_CONFIG="$DIR/src-tauri/.cargo/config.toml"
        if [ -f "$CARGO_CONFIG" ] && grep -q 'vauchi-core.*path' "$CARGO_CONFIG" 2>/dev/null; then
            printf "  %-10s ${GREEN}path override active${NC} (always uses core HEAD)\n" "$repo:"
        else
            printf "  %-10s ${YELLOW}using git dep${NC} (run: cargo update -p vauchi-core)\n" "$repo:"
        fi
    done
    echo ""

    # Mobile bindings
    echo "=== Mobile Bindings ==="

    # iOS — check Package.swift version
    IOS_PKG="$ROOT/vauchi-mobile-swift/Package.swift"
    if [ -f "$IOS_PKG" ]; then
        IOS_VER=$(sed -n 's/^let version = "\(.*\)"/\1/p' "$IOS_PKG")
        if [ "$LATEST_TAG" != "none" ] && [ "v$IOS_VER" = "$LATEST_TAG" ]; then
            printf "  %-10s ${GREEN}v%s (matches latest tag)${NC}\n" "iOS:" "$IOS_VER"
        else
            printf "  %-10s ${YELLOW}v%s (latest core tag: %s)${NC}\n" "iOS:" "$IOS_VER" "$LATEST_TAG"
        fi
    fi

    # Android — check build.gradle.kts dependency version
    ANDROID_GRADLE="$ROOT/android/app/build.gradle.kts"
    if [ -f "$ANDROID_GRADLE" ]; then
        ANDROID_VER=$(sed -n 's/.*com\.vauchi:vauchi-mobile:\(.*\)".*/\1/p' "$ANDROID_GRADLE")
        if [ "$LATEST_TAG" != "none" ] && [ "v$ANDROID_VER" = "$LATEST_TAG" ]; then
            printf "  %-10s ${GREEN}v%s (matches latest tag)${NC}\n" "Android:" "$ANDROID_VER"
        else
            printf "  %-10s ${YELLOW}v%s (latest core tag: %s)${NC}\n" "Android:" "$ANDROID_VER" "$LATEST_TAG"
        fi
    fi

    # Local bindings status
    echo ""
    echo "=== Local Bindings ==="
    IOS_LOCAL="$ROOT/ios/Vauchi/Generated"
    ANDROID_LOCAL="$ROOT/android/app/src/local-bindings"
    if [ -d "$IOS_LOCAL" ] && [ "$(ls -A "$IOS_LOCAL" 2>/dev/null)" ]; then
        printf "  %-10s ${GREEN}wired${NC}\n" "iOS:"
    else
        printf "  %-10s ${DIM}not wired${NC} (run: just bindings-local)\n" "iOS:"
    fi
    if [ -d "$ANDROID_LOCAL" ] && [ "$(ls -A "$ANDROID_LOCAL" 2>/dev/null)" ]; then
        printf "  %-10s ${GREEN}wired${NC}\n" "Android:"
    else
        printf "  %-10s ${DIM}not wired${NC} (run: just bindings-local)\n" "Android:"
    fi

    # Summary
    echo ""
    if [ "$LATEST_TAG" != "none" ] && [ "$AHEAD" != "0" ] && [ "$AHEAD" != "?" ]; then
        echo "Core has unreleased changes. When ready:"
        echo "  1. Bump version in core/Cargo.toml"
        echo "  2. Merge to main (auto-tags)"
        echo "  3. Stable tag triggers binding build+publish+app bump MRs"
        echo ""
        echo "For local dev: just bindings-local"
    fi
