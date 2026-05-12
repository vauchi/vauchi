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

# Regenerate JSON schemas in `core/vauchi-core/schemas/` from current UI types.
# Use after editing `ScreenModel`, `UserAction`, or `ActionResult` shapes.
# Writes `screen-model.schema.json`, `user-action.schema.json`,
# `action-result.schema.json`. Review the diff and commit alongside the
# type change so `just schema-check` stays green on CI.
[group('dev')]
schema-regen:
    cd core && cargo test --features schema-gen -p vauchi-core --test schema_gen -- regenerate --ignored

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

    # Platform bindings
    echo "── Platform Bindings ──"

    # iOS — check Package.swift version
    IOS_PKG="$ROOT/vauchi-platform-swift/Package.swift"
    if [ -f "$IOS_PKG" ]; then
        IOS_VER=$(sed -n 's/^let version = "\(.*\)"/\1/p' "$IOS_PKG")
        if [ "$LATEST_TAG" != "none" ] && [ "v$IOS_VER" = "$LATEST_TAG" ]; then
            _dev_status "iOS:" "$GREEN" "v$IOS_VER (matches latest tag)"
        else
            _dev_status "iOS:" "$YELLOW" "v$IOS_VER (latest core tag: $LATEST_TAG)"
        fi
    fi

    # Android — check build.gradle.kts dependency version
    ANDROID_GRADLE="$ROOT/android/app/build.gradle.kts"
    if [ -f "$ANDROID_GRADLE" ]; then
        ANDROID_VER=$(sed -n 's/.*com\.vauchi:vauchi-platform:\(.*\)".*/\1/p' "$ANDROID_GRADLE")
        if [ "$LATEST_TAG" != "none" ] && [ "v$ANDROID_VER" = "$LATEST_TAG" ]; then
            _dev_status "Android:" "$GREEN" "v$ANDROID_VER (matches latest tag)"
        else
            _dev_status "Android:" "$YELLOW" "v$ANDROID_VER (latest core tag: $LATEST_TAG)"
        fi
    fi

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
        echo "  3. Stable tag triggers binding build+publish+app bump MRs"
        echo ""
        echo "For local dev: just bindings-local"
    fi

# ═══════════════════════════════════════════════════════════════════
# BRANCH REF MAINTENANCE
# ═══════════════════════════════════════════════════════════════════

# Fix non-main git dependency branch refs across all Rust consumer repos
[group('dev')]
[script]
fix-branch-refs:
    set -euo pipefail
    source scripts/scripts/output-helpers.sh
    ROOT="{{justfile_directory()}}"
    FIXED=0
    for repo in cli tui e2e linux-gtk relay; do
        TOML="$ROOT/$repo/Cargo.toml"
        [ -f "$TOML" ] || continue
        BAD=$(taplo get -f "$TOML" -o json 2>/dev/null \
            | jq -r '.. | .branch? // empty' | grep -v '^main$' || true)
        if [ -n "$BAD" ]; then
            echo "${YELLOW}$repo${NC}: fixing non-main branch refs"
            echo "$BAD" | sed 's/^/  /'
            sed -i.bak 's/branch = "[^"]*"/branch = "main"/g' "$TOML" && rm -f "$TOML.bak"
            (cd "$ROOT/$repo" && cargo update 2>&1 | tail -1)
            echo "  ${GREEN}→ restored to main${NC}"
            FIXED=$((FIXED + 1))
        fi
    done
    if [ "$FIXED" -eq 0 ]; then
        echo "${GREEN}All repos already point to main${NC}"
    else
        echo ""
        echo "Fixed $FIXED repo(s). Review and commit:"
        echo "  git diff */Cargo.toml */Cargo.lock"
    fi
