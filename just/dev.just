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
# CORE FRESHNESS
# ═══════════════════════════════════════════════════════════════════

# Check if mobile bindings and Rust consumers are up to date with core
[group('dev')]
[script]
core-freshness:
    source scripts/scripts/output-helpers.sh
    set -euo pipefail

    ROOT="{{justfile_directory()}}"

    # Core's own HEAD and tag come from the local checkout, so fetch it.
    # Consumer pins are read from origin/main by core-pins.py --fetch:
    # local checkouts report what was last pulled, not what is released
    # (on 2026-09-30 they showed iOS and Android a release behind origin).
    git -C "$ROOT/core" fetch --quiet --tags origin 2>/dev/null \
        || printf "%b\n" "${YELLOW}WARNING: could not fetch core; its HEAD and tag may be stale${NC}"

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

    echo "── Core ──"
    printf "  HEAD:       %s (%s)\n" "$CORE_SHORT" "$CORE_MSG"
    printf "  Latest tag: %s (%b)\n" "$LATEST_TAG" "$TAG_STATUS"
    echo ""

    _DEV_COL=12  # label column for dev status
    _dev_status() {
        local label="$1" color="$2" msg="$3"
        local _p=$(( _DEV_COL - ${#label} )); [[ $_p -lt 1 ]] && _p=1
        printf "  %s%*s %s%s%s\n" "$label" "$_p" "" "$color" "$msg" "$NC"
    }

    # Rust consumers (path-overridden locally)
    echo "── Rust Consumers (path-overridden locally) ──"
    for repo in cli tui; do
        DIR="$ROOT/$repo"
        [ -d "$DIR" ] || continue
        CARGO_CONFIG="$DIR/.cargo/config.toml"
        if [ -f "$CARGO_CONFIG" ] && grep -q 'vauchi-core.*path' "$CARGO_CONFIG" 2>/dev/null; then
            _dev_status "$repo:" "$GREEN" "path override active (always uses core HEAD)"
        else
            _dev_status "$repo:" "$YELLOW" "using git dep (run: cargo update -p vauchi-core)"
        fi
    done
    echo ""

    # Every consumer's native pin, as listed in core's ci/consumer-pins.json
    # (ADR-026 amendment). `just check-versions` runs the same check strictly.
    echo "── Core pins (read from origin/main) ──"
    python3 "$ROOT/scripts/scripts/core-pins.py" check --root "$ROOT" --fetch \
        || printf "%b\n" "${YELLOW}  core-pins could not read the table (is core fetched?)${NC}"

    # Local bindings status
    echo ""
    echo "── Local Bindings ──"
    IOS_LOCAL="$ROOT/ios/Vauchi/Generated"
    ANDROID_LOCAL="$ROOT/android/app/src/local-bindings"
    if [ -d "$IOS_LOCAL" ] && [ "$(ls -A "$IOS_LOCAL" 2>/dev/null)" ]; then
        _dev_status "iOS:" "$GREEN" "wired"
    else
        _dev_status "iOS:" "$DIM" "not wired (run: just bindings-local)"
    fi
    if [ -d "$ANDROID_LOCAL" ] && [ "$(ls -A "$ANDROID_LOCAL" 2>/dev/null)" ]; then
        _dev_status "Android:" "$GREEN" "wired"
    else
        _dev_status "Android:" "$DIM" "not wired (run: just bindings-local)"
    fi

    # Summary
    echo ""
    if [ "$LATEST_TAG" != "none" ] && [ "$AHEAD" != "0" ] && [ "$AHEAD" != "?" ]; then
        echo "Core has unreleased changes. When ready:"
        echo "  1. Bump version in core/Cargo.toml"
        echo "  2. Merge to main (auto-tags)"
        echo "  3. The release tag publishes the bindings and opens a pin-bump MR in every consumer"
        echo ""
        echo "For local dev: just bindings-local"
    fi

# Fetch the canonical build-discovery.py from vauchi/scripts into docs
# and spec (private#1267). Local-dev counterpart of the CI fetch step;
# defaults to main, pass a SHA to pin, e.g. just sync-discovery abc123.
[group('dev')]
sync-discovery ref='main':
    #!/bin/bash
    set -euo pipefail
    for repo in docs spec; do
        curl -fsSL "https://gitlab.com/api/v4/projects/77957857/repository/files/scripts%2Fbuild-discovery.py/raw?ref={{ref}}" \
            -o "$repo/scripts/build-discovery.py"
        echo "  synced $repo/scripts/build-discovery.py ({{ref}})"
    done

# Check the conformance suites for drift across core, linux-hw and
# contract (private#1265). Only adapter lines may differ between copies.
[group('dev')]
check-conformance:
    python3 scripts/scripts/check-conformance-sync.py --root .
