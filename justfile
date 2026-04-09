# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Vauchi Development Commands
# Usage: just <recipe>
#
# Quick start:
#   git clone git@gitlab.com:vauchi/vauchi.git && cd vauchi
#   just setup
#   just check

set dotenv-load := true
set shell := ["bash", "-cu"]
set script-interpreter := ["bash", "-eu"]
set windows-shell := ["C:/Program Files/Git/usr/bin/bash.exe", "-cu"]

# Windows: [script] recipes use 'sh' which isn't in Windows PATH by default.
# Prepend Git's usr/bin so sh/bash are found for script recipes.
export PATH := if os() == "windows" { "C:/Program Files/Git/usr/bin" + ";" + env("PATH") } else { env("PATH") }

# GitLab base URL
gitlab_base := "git@gitlab.com:vauchi"

# Public repositories (mirrored to GitHub)
public_repos := "gitlab-profile scripts assets core relay ohttp-relay cli tui e2e features android ios docs locales themes website vauchi-platform-swift macos windows linux-gtk linux-qt web-demo"

# Private repository (consolidated, cloned as _private)
private_repo := "private"

# Tooling repositories (url,dir format, outside vauchi group)
tooling_repos := "git@gitlab.com:megloff1/drift-detector.git,drift-detector git@gitlab.com:megloff1/markdown-plan.git,markdown-plan"

# Device names (single source of truth for all recipes)
ios_simulator := "iPhone 17 Pro"
avd_android := "Pixel_7"

# ─── Aliases ─────────────────────────────────────────────────────

alias b := build
alias t := test
alias c := check
alias f := fmt

# Run a command inside a sub-repo directory (subshell — cwd never leaks)
# Usage: just exec-in-repo android "./gradlew :app:assembleDebug"
#        just exec-in-repo core "cargo test -p vauchi-core"
#        just exec-in-repo ios "xcodebuild -scheme Vauchi build"
[group('core')]
exec-in-repo repo +cmd:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -d "{{ repo }}" ]]; then
        echo "Error: repo '{{ repo }}' not found" >&2; exit 1
    fi
    (cd "{{ repo }}" && {{ cmd }})

# ─── Modules ──────────────────────────────────────────────────────

[doc('Multi-repo git operations')]
mod git 'just/git.just'

[doc('GitLab MR, pipeline, and issue operations')]
mod gitlab 'just/gitlab.just'

[doc('Git worktree management for parallel development')]
mod worktree 'just/worktree.just'

import 'just/apps.just'
import 'just/setup.just'
import 'just/mobile.just'
import 'just/e2e.just'
import 'just/deploy.just'
import 'just/runners.just'
import 'just/dev.just'
import 'just/plan.just'
import 'just/perf.just'
import 'just/device-test.just'
import 'just/device-test-macos.just'
import 'just/desktop-test.just'
import 'just/health.just'

# ═══════════════════════════════════════════════════════════════════
# DAILY COMMANDS - Use these regularly
# ═══════════════════════════════════════════════════════════════════

# Run all checks: format-check → lint → test
[group('daily')]
[script]
check *args:
    set -euo pipefail
    source scripts/scripts/quiet-runner.sh
    _qr_parse_args {{args}}
    if quiet_enabled; then
        _QR_TOTAL_START=$SECONDS
        export _QR_SHARED_DIR
        _QR_SHARED_DIR=$(mktemp -d)
        trap 'rm -rf "$_QR_SHARED_DIR"' EXIT
        # Run all three phases in parallel. Each writes to a separate
        # results file in _QR_SHARED_DIR, so no file conflicts.
        # Within a single repo, clippy and test share target/ and Cargo
        # serializes them via its lock — the speedup comes from fmt-check
        # overlapping with compilation and from cross-repo parallelism.
        just fmt-check ${_QR_REPO:-} --quiet &
        just lint ${_QR_REPO:-} --quiet &
        just test ${_QR_REPO:-} --quiet &
        wait
        qr_print_shared_summary "check" || exit 1
    else
        just fmt-check ${_QR_REPO:-}
        just lint ${_QR_REPO:-}
        just test ${_QR_REPO:-}
    fi
    # Write TDD stamps for repos that passed all checks
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/stamp.sh
    for r in $(resolve_repo "${_QR_REPO:-}" "test"); do
        stamp_write "$r" 2>/dev/null || true
    done

# Build workspace or specific repo
[group('daily')]
[script]
build *args:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/quiet-runner.sh
    _qr_parse_args {{args}}
    for r in $(resolve_repo "${_QR_REPO:-}" "build"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        if ! quiet_enabled; then echo "═══ build: $r ($tc) ═══"; fi
        _do_step() {
            case "$tc" in
                rust)    (cd "$dir" && cargo build --workspace 2>&1) ;;
                npm)     (cd "$dir" && npm ci --silent && npm run build 2>&1) ;;
                gradle)  (cd "$dir" && ./gradlew assembleDebug 2>&1) ;;
                xcode)
                    local xc_dest='platform=iOS Simulator,name={{ ios_simulator }}'
                    [[ "$r" == "macos" ]] && xc_dest='platform=macOS'
                    (cd "$dir" && xcodebuild -scheme Vauchi -destination "$xc_dest" -configuration Debug -skipPackageUpdates build -quiet 2>&1)
                    ;;
                mkdocs)  (cd "$dir" && mkdocs build --strict 2>&1) ;;
                *)       echo "  (no build step for $tc)"; return 0 ;;
            esac
        }
        run_step "$r" _do_step
    done
    print_summary "build" || exit 1

# Run tests
[group('daily')]
[script]
test *args:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/quiet-runner.sh
    _qr_parse_args {{args}}
    for r in $(resolve_repo "${_QR_REPO:-}" "test"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        if ! quiet_enabled; then echo "═══ test: $r ($tc) ═══"; fi
        tfeats=$(repo_test_features "$r")
        _do_step() {
            case "$tc" in
                rust)
                    if command -v cargo-nextest &>/dev/null; then
                        (cd "$dir" && cargo nextest run --workspace $tfeats 2>&1)
                    else
                        (cd "$dir" && cargo test --workspace $tfeats 2>&1)
                    fi
                    ;;
                npm)     (cd "$dir" && npx playwright test --project=chromium --grep-invert "@visual|@a11y" 2>&1) ;;
                gradle)  (cd "$dir" && ./gradlew test 2>&1) ;;
                xcode)
                    local xc_dest='platform=iOS Simulator,name={{ ios_simulator }}'
                    [[ "$r" == "macos" ]] && xc_dest='platform=macOS'
                    (cd "$dir" && xcodebuild -scheme Vauchi -destination "$xc_dest" -skipPackageUpdates test -quiet 2>&1)
                    ;;
                mkdocs)  (cd "$dir" && mkdocs build --strict 2>&1) ;;
                *)       echo "  (no test step for $tc)"; return 0 ;;
            esac
        }
        run_step "$r" _do_step
    done
    print_summary "test" || exit 1

# Run slow / ignored tests (nightly CI, timing-sensitive, property-based)
[group('daily')]
test-slow *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    for r in $(resolve_repo "${1:-}" "test"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        tfeats=$(repo_test_features "$r")
        case "$tc" in
            rust)
                echo "═══ test-slow: $r ═══"
                (cd "$dir" && cargo test --workspace $tfeats -- --ignored --nocapture)
                ;;
        esac
    done

# Format code
[group('daily')]
[script]
fmt *args:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/quiet-runner.sh
    _qr_parse_args {{args}}
    for r in $(resolve_repo "${_QR_REPO:-}" "fmt"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        if ! quiet_enabled; then echo "═══ fmt: $r ($tc) ═══"; fi
        _do_step() {
            case "$tc" in
                rust)    (cd "$dir" && cargo fmt --all 2>&1) ;;
                npm)     (cd "$dir" && npx prettier --write src/ 2>&1) ;;
                xcode)   (cd "$dir" && swiftformat . 2>&1) ;;
                *)       echo "  (no fmt step for $tc)"; return 0 ;;
            esac
        }
        run_step "$r" _do_step
    done
    print_summary "fmt" || exit 1

# Check formatting (no changes)
[group('daily')]
[script]
fmt-check *args:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/quiet-runner.sh
    _qr_parse_args {{args}}
    for r in $(resolve_repo "${_QR_REPO:-}" "fmt"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        if ! quiet_enabled; then echo "═══ fmt-check: $r ($tc) ═══"; fi
        _do_step() {
            case "$tc" in
                rust)    (cd "$dir" && cargo fmt --all -- --check 2>&1) ;;
                npm)     (cd "$dir" && npx prettier --check src/ 2>&1) ;;
                xcode)   (cd "$dir" && swiftformat --lint . 2>&1) ;;
                *)       echo "  (no fmt-check step for $tc)"; return 0 ;;
            esac
        }
        run_step "$r" _do_step
    done
    print_summary "fmt-check" || exit 1

# Run lints
[group('daily')]
[script]
lint *args:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/quiet-runner.sh
    _qr_parse_args {{args}}
    for r in $(resolve_repo "${_QR_REPO:-}" "lint"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        if ! quiet_enabled; then echo "═══ lint: $r ($tc) ═══"; fi
        _do_step() {
            case "$tc" in
                rust)    (cd "$dir" && cargo clippy --workspace -- -D warnings 2>&1) ;;
                npm)     (cd "$dir" && npm run lint 2>&1 && npm run lint:css 2>&1) ;;
                gradle)  (cd "$dir" && ./gradlew lint 2>&1) ;;
                xcode)   (cd "$dir" && swiftlint lint --strict --quiet 2>&1 && swiftformat --lint . 2>&1) ;;
                mkdocs)  (cd "$dir" && markdownlint '**/*.md' 2>&1) ;;
                python)
                    if [[ -f "$dir/scripts/validate.py" ]]; then
                        (cd "$dir" && python3 scripts/validate.py 2>&1)
                    fi
                    ;;
                gherkin) echo "  (gherkin lint: advisory only)"; return 0 ;;
                shell)   (cd "$dir" && shellcheck scripts/*.sh 2>&1) ;;
                html)    (cd "$dir" && htmlhint public/**/*.html 2>&1) ;;
                *)       echo "  (no lint step for $tc)"; return 0 ;;
            esac
        }
        run_step "$r" _do_step
    done
    print_summary "lint" || exit 1

# Interactive commit across repos with changes
[group('daily')]
commit:
    ./scripts/scripts/commit-interactive.sh

# Non-interactive commit for a single repo (for automation / Claude)
# Usage: just commit-repo core "feat: add exchange timeout"
#        just commit-repo . "chore: update justfile"   (root repo)
[group('daily')]
[no-cd]
[script]
commit-repo repo message:
    set -euo pipefail
    dir="{{ repo }}"
    if [[ "$dir" == "." || "$dir" == "root" ]]; then
        dir="."
        label="vauchi (root)"
    else
        label="{{ repo }}"
    fi
    if [[ "$dir" != "." && ! -d "$dir/.git" ]]; then
        echo "ERROR: $dir is not a git repo" >&2
        exit 1
    fi
    # Warn if HEAD is a WIP commit (suggest wip-undo first)
    head_msg=$(git -C "$dir" log -1 --format=%s 2>/dev/null || true)
    if [[ "$head_msg" == wip:* ]]; then
        echo "WARNING: HEAD is a WIP commit: $head_msg"
        echo "Consider running 'just git wip-undo {{ repo }}' first to restore WIP changes,"
        echo "then commit properly."
        echo ""
    fi
    # Check for changes
    if [[ -z "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
        echo "$label: nothing to commit"
        exit 0
    fi
    echo "── $label ──"
    git -C "$dir" status --short
    echo ""
    # Warn about untracked files (not staged by -u)
    untracked=$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null)
    if [[ -n "$untracked" ]]; then
        echo "NOTE: Untracked files (not staged — use 'git add' manually if needed):"
        echo "$untracked" | sed 's/^/  ? /'
        echo ""
    fi
    git -C "$dir" add -u
    # Check if anything was staged after add -u
    if [[ -z "$(git -C "$dir" diff --cached --name-only 2>/dev/null)" ]]; then
        echo "$label: only untracked files — nothing staged (use 'git -C $dir add <file>' to stage)"
        exit 0
    fi
    git -C "$dir" commit -m "{{ message }}"
    echo ""
    echo "Committed in $label"

# ═══════════════════════════════════════════════════════════════════
# EXTENDED COMMANDS - Less frequently used
# ═══════════════════════════════════════════════════════════════════

# Run tests for specific crate (within core workspace)
[group('extended')]
[working-directory('core')]
test-crate crate:
    cargo test -p {{crate}} --features vauchi-core/testing

# Run a single test file by name
# Usage: just test-file identity_test           (searches core/)
#        just test-file exchange_test relay      (searches relay/)
[group('extended')]
[no-cd]
[script]
test-file name repo='core':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    repos=$(resolve_repo "{{ repo }}" "test")
    for r in $repos; do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        tfeats=$(repo_test_features "$r")
        case "$tc" in
            rust)
                echo "── $r: cargo test --test {{ name }} $tfeats ──"
                (cd "$dir" && cargo test --test "{{ name }}" $tfeats 2>&1) || true
                ;;
            npm)
                echo "── $r: npx vitest {{ name }} ──"
                (cd "$dir" && npx vitest run "{{ name }}" 2>&1) || true
                ;;
            gradle)
                echo "── $r: ./gradlew test --tests *{{ name }}* ──"
                (cd "$dir" && ./gradlew test --tests "*{{ name }}*" 2>&1) || true
                ;;
            *)
                echo "── $r: test-file not supported for $tc ──"
                ;;
        esac
    done

# Run tests matching a name pattern
# Usage: just test-name exchange_round_trip          (searches core/)
#        just test-name relay_failover e2e           (searches e2e/)
[group('extended')]
[no-cd]
[script]
test-name pattern repo='core':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    repos=$(resolve_repo "{{ repo }}" "test")
    for r in $repos; do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        tfeats=$(repo_test_features "$r")
        case "$tc" in
            rust)
                echo "── $r: cargo test {{ pattern }} $tfeats ──"
                (cd "$dir" && cargo test $tfeats "{{ pattern }}" 2>&1) || true
                ;;
            npm)
                echo "── $r: npx vitest -t '{{ pattern }}' ──"
                (cd "$dir" && npx vitest run -t "{{ pattern }}" 2>&1) || true
                ;;
            gradle)
                echo "── $r: ./gradlew test --tests *{{ pattern }}* ──"
                (cd "$dir" && ./gradlew test --tests "*{{ pattern }}*" 2>&1) || true
                ;;
            *)
                echo "── $r: test-name not supported for $tc ──"
                ;;
        esac
    done

# Build release binaries
[group('extended')]
[working-directory('core')]
build-release:
    cargo build --workspace --release

# Build vauchi-cabi DLL for Windows (requires Rust + MSVC + CMake + NASM)
[group('extended')]
[script]
build-cabi-windows:
    set -euo pipefail
    echo "Building vauchi-cabi for Windows..."
    cd core && cargo build -p vauchi-cabi --release --features audio
    cd ..
    mkdir -p windows/cabi
    cp core/target/release/vauchi_cabi.dll windows/cabi/vauchi_cabi.dll
    cp core/vauchi-cabi/include/vauchi.h windows/cabi/vauchi.h
    echo "✓ DLL copied to windows/cabi/"

# Download pre-built vauchi-cabi DLL from GitLab registry
[group('extended')]
[script]
download-cabi:
    set -euo pipefail
    if [ ! -f windows/cabi-version.json ]; then
      echo "ERROR: windows/cabi-version.json not found"; exit 1
    fi
    VERSION=$(python3 -c "import json; print(json.load(open('windows/cabi-version.json'))['version'])")
    SHA256=$(python3 -c "import json; print(json.load(open('windows/cabi-version.json'))['sha256'])")
    if [ "$VERSION" = "0.0.0" ]; then
      echo "CABI version is placeholder — run 'just build-cabi-windows' instead"; exit 1
    fi
    if [ -n "${GITLAB_TOKEN:-}" ]; then
      HEADER="PRIVATE-TOKEN: $GITLAB_TOKEN"
    elif command -v glab >/dev/null 2>&1; then
      TOKEN=$(glab auth token 2>/dev/null || echo "")
      if [ -z "$TOKEN" ]; then
        echo "ERROR: No GITLAB_TOKEN and glab not authenticated"; exit 1
      fi
      HEADER="PRIVATE-TOKEN: $TOKEN"
    else
      echo "ERROR: No GITLAB_TOKEN and glab not installed"; exit 1
    fi
    PROJECT_ID=$(glab api projects/vauchi%2Fcore --jq '.id' 2>/dev/null || echo "")
    if [ -z "$PROJECT_ID" ]; then
      echo "ERROR: Could not resolve core project ID"; exit 1
    fi
    BASE_URL="https://gitlab.com/api/v4/projects/$PROJECT_ID/packages/generic/vauchi-cabi-windows/$VERSION"
    mkdir -p windows/cabi
    echo "Downloading vauchi_cabi.dll v$VERSION..."
    curl -sSfL -H "$HEADER" "$BASE_URL/vauchi_cabi.dll" -o windows/cabi/vauchi_cabi.dll
    if command -v sha256sum >/dev/null 2>&1; then
      ACTUAL=$(sha256sum windows/cabi/vauchi_cabi.dll | cut -d' ' -f1)
    else
      ACTUAL=$(shasum -a 256 windows/cabi/vauchi_cabi.dll | cut -d' ' -f1)
    fi
    if [ "$ACTUAL" != "$SHA256" ]; then
      echo "ERROR: SHA-256 mismatch — expected $SHA256, got $ACTUAL"
      rm windows/cabi/vauchi_cabi.dll; exit 1
    fi
    echo "✓ SHA-256 verified"
    if command -v cosign >/dev/null 2>&1; then
      curl -sSfL -H "$HEADER" "$BASE_URL/vauchi_cabi.dll.sha256" -o windows/cabi/vauchi_cabi.dll.sha256
      curl -sSfL -H "$HEADER" "$BASE_URL/vauchi_cabi.dll.sha256.bundle" -o windows/cabi/vauchi_cabi.dll.sha256.bundle
      cosign verify-blob --key windows/cosign.pub --bundle windows/cabi/vauchi_cabi.dll.sha256.bundle windows/cabi/vauchi_cabi.dll.sha256 \
        && echo "✓ Cosign verified" || echo "⚠ Cosign verification failed (non-fatal for local dev)"
    else
      echo "⚠ cosign not installed — skipping signature verification"
    fi
    curl -sSfL -H "$HEADER" "$BASE_URL/vauchi.h" -o windows/cabi/vauchi.h 2>/dev/null || true
    echo "✓ DLL ready at windows/cabi/"

# Create a dev tag for fast CI feedback (lint + test only)
# Usage: just release-dev [repo] [version]
[group('extended')]
[script]
release-dev repo="core" version="":
    just _release-tag "{{ repo }}" "{{ version }}" dev "Dev release" "lightweight pipeline (lint + test only)"

# Create an RC tag for full quality gate (coverage, mutation, bench)
# Usage: just release-rc [repo] [version]
[group('extended')]
[script]
release-rc repo="core" version="":
    just _release-tag "{{ repo }}" "{{ version }}" rc "Release candidate" "full quality gate (coverage, mutation, bench, security)\n  NO publish, deploy, or mobile binding trigger"

# Internal: create a suffixed tag (-dev.N or -rc.N) with auto-increment
[private]
[script]
_release-tag repo version suffix label description:
    set -euo pipefail
    REPO="{{ repo }}"
    CARGO_TOML="$REPO/Cargo.toml"
    if [[ -n "{{ version }}" ]]; then
        TAG="v{{ version }}"
    else
        if [[ "$REPO" == "core" ]]; then
            BASE=$(grep -A5 '^\[workspace\.package\]' "$CARGO_TOML" | grep '^version' | sed 's/.*"\(.*\)"/\1/')
        else
            BASE=$(grep '^version' "$CARGO_TOML" | head -1 | sed 's/.*"\(.*\)"/\1/')
        fi
        BASE=$(echo "$BASE" | sed 's/-.*//')
        LAST=$(git -C "$REPO" tag -l "v${BASE}-{{ suffix }}.*" | sort -V | tail -1 || true)
        if [[ -n "$LAST" ]]; then
            N=$(echo "$LAST" | grep -oE '[0-9]+$')
            N=$((N + 1))
        else
            N=1
        fi
        TAG="v${BASE}-{{ suffix }}.${N}"
    fi
    echo "Creating {{ suffix }} tag for $REPO: $TAG"
    echo -e "  This will trigger a {{ description }}"
    echo ""
    BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
    if [[ "$BRANCH" != "main" ]]; then
        echo "ERROR: Must be on main branch (currently on $BRANCH)"
        exit 1
    fi
    git -C "$REPO" tag -a "$TAG" -m "{{ label }} $TAG"
    git -C "$REPO" push origin "$TAG"
    echo "Created and pushed $TAG"
    echo "  Pipeline: https://gitlab.com/vauchi/$REPO/-/pipelines"

# Create a PROD release tag (full pipeline + publish + deploy + mobile triggers)
# Usage: just release-prod [repo]
# Reads version from <repo>/Cargo.toml — must be a clean version (no -dev/-rc suffix)
[group('extended')]
[script]
release-prod repo="core":
    set -euo pipefail
    REPO="{{ repo }}"
    CARGO_TOML="$REPO/Cargo.toml"
    if [[ "$REPO" == "core" ]]; then
        VERSION=$(grep -A5 '^\[workspace\.package\]' "$CARGO_TOML" | grep '^version' | sed 's/.*"\(.*\)"/\1/')
    else
        VERSION=$(grep '^version' "$CARGO_TOML" | head -1 | sed 's/.*"\(.*\)"/\1/')
    fi
    if echo "$VERSION" | grep -qE -- '-(dev|rc)\.'; then
        echo "ERROR: Cargo.toml has pre-release version $VERSION"
        echo "  Update Cargo.toml to a clean version (e.g., 0.2.3) before PROD release"
        exit 1
    fi
    TAG="v${VERSION}"
    echo "Creating PROD tag for $REPO: $TAG"
    echo "  This will trigger the FULL release pipeline:"
    echo "    - Build + test + coverage + mutation"
    echo "    - Package iOS/Android bindings"
    echo "    - Publish to GitLab package registry"
    echo "    - Create GitLab release"
    if [[ "$REPO" == "core" ]]; then
        echo "    - Trigger mobile binding repos -> iOS/Android apps"
    fi
    echo ""
    echo "  Promotion chain for this version:"
    git -C "$REPO" tag -l "v${VERSION}*" 2>/dev/null | sort -V | sed 's/^/    /' || true
    echo "    $TAG  <- YOU ARE HERE"
    echo ""
    read -p "Proceed? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 1
    fi
    BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
    if [[ "$BRANCH" != "main" ]]; then
        echo "ERROR: Must be on main branch (currently on $BRANCH)"
        exit 1
    fi
    git -C "$REPO" tag -a "$TAG" -m "Release $TAG"
    git -C "$REPO" push origin "$TAG"
    echo "Created and pushed $TAG"

# Show version promotion history for a given base version
# Usage: just release-history [repo] [version]
[group('extended')]
[script]
release-history repo="core" version="":
    set -euo pipefail
    REPO="{{ repo }}"
    CARGO_TOML="$REPO/Cargo.toml"
    if [[ -n "{{ version }}" ]]; then
        BASE="{{ version }}"
    else
        if [[ "$REPO" == "core" ]]; then
            BASE=$(grep -A5 '^\[workspace\.package\]' "$CARGO_TOML" | grep '^version' | sed 's/.*"\(.*\)"/\1/' | sed 's/-.*//')
        else
            BASE=$(grep '^version' "$CARGO_TOML" | head -1 | sed 's/.*"\(.*\)"/\1/' | sed 's/-.*//')
        fi
    fi
    echo "Version promotion history for $REPO v${BASE}:"
    echo ""
    git -C "$REPO" tag -l "v${BASE}*" | sort -V | while read -r tag; do
        DATE=$(git -C "$REPO" log -1 --format=%ci "$tag" 2>/dev/null | cut -d' ' -f1)
        if echo "$tag" | grep -q "dev"; then
            echo "  $tag  ($DATE)  [dev]"
        elif echo "$tag" | grep -q "rc"; then
            echo "  $tag  ($DATE)  [RC]"
        else
            echo "  $tag  ($DATE)  [PROD]"
        fi
    done

# Show full release chain status across all repos (core → swift/kotlin → ios/android)
# Usage: just release-chain-status [version]
#   just release-chain-status          # auto-detect from core/Cargo.toml
#   just release-chain-status 0.3.1    # specific version
[group('extended')]
[script]
release-chain-status version="":
    set -euo pipefail

    # Resolve version
    if [[ -n "{{ version }}" ]]; then
        BASE="{{ version }}"
    else
        BASE=$(grep -A5 '^\[workspace\.package\]' core/Cargo.toml | grep '^version' | sed 's/.*"\(.*\)"/\1/' | sed 's/-.*//')
    fi

    echo "═══ Release Chain Status for v${BASE} ═══"
    echo ""

    # 1. Core tags
    echo "── Core Tags ──"
    TAGS=$(git -C core tag -l "v${BASE}*" 2>/dev/null | sort -V)
    if [[ -z "$TAGS" ]]; then
        echo "  No tags for v${BASE}"
    else
        echo "$TAGS" | while read -r tag; do
            DATE=$(git -C core log -1 --format=%ci "$tag" 2>/dev/null | cut -d' ' -f1)
            if echo "$tag" | grep -q "dev"; then
                echo "  $tag  ($DATE)  [dev]"
            elif echo "$tag" | grep -q "rc"; then
                echo "  $tag  ($DATE)  [RC]"
            else
                echo "  $tag  ($DATE)  [PROD]"
            fi
        done
    fi
    LATEST_TAG=$(echo "$TAGS" | tail -1)
    echo ""

    # 2. Core pipeline status for latest tag
    if [[ -n "$LATEST_TAG" ]]; then
        echo "── Core Pipeline (${LATEST_TAG}) ──"
        if command -v glab &>/dev/null && glab auth status &>/dev/null 2>&1; then
            glab ci list -R vauchi/core 2>/dev/null | grep -E "${LATEST_TAG}|${BASE}" | head -3 || echo "  No pipeline found"
        else
            echo "  (glab not authenticated — run 'glab auth login')"
        fi
        echo ""
    fi

    # 3. Distribution repo status
    for dist_repo in vauchi-platform-swift; do
        echo "── ${dist_repo} ──"
        if command -v glab &>/dev/null && glab auth status &>/dev/null 2>&1; then
            # Check for open MRs mentioning this version
            MRS=$(glab mr list -R "vauchi/${dist_repo}" --state opened 2>/dev/null | grep -i "${BASE}" || true)
            if [[ -n "$MRS" ]]; then
                echo "  Open MRs:"
                echo "$MRS" | sed 's/^/    /'
            else
                echo "  No open MRs for v${BASE}"
            fi
            # Show latest pipeline (just the first result line, skip header)
            LATEST=$(glab ci list -R "vauchi/${dist_repo}" 2>/dev/null | head -2 | tail -1)
            if [[ -n "$LATEST" ]]; then
                echo "  Latest pipeline: $LATEST"
            fi
        else
            echo "  (glab not authenticated)"
        fi
        echo ""
    done

    # 4. App repo status
    for app_repo in ios android; do
        echo "── ${app_repo} ──"
        if command -v glab &>/dev/null && glab auth status &>/dev/null 2>&1; then
            MRS=$(glab mr list -R "vauchi/${app_repo}" --state opened 2>/dev/null | grep -i "${BASE}" || true)
            if [[ -n "$MRS" ]]; then
                echo "  Open MRs:"
                echo "$MRS" | sed 's/^/    /'
            else
                echo "  No open MRs for v${BASE}"
            fi
        else
            echo "  (glab not authenticated)"
        fi
        echo ""
    done

    echo "═══ End ═══"

# Run security audit
[group('extended')]
[script]
audit repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    RUST_REPOS="$(repos_by_toolchain rust)"
    if [[ -z "{{repo}}" ]]; then
        repos="$RUST_REPOS"
    elif [[ "{{repo}}" == "all" ]]; then
        repos="$RUST_REPOS"
    else
        repos="{{repo}}"
    fi
    for r in $repos; do
        dir=$(repo_dir "$r")
        echo "═══ audit: $r ═══"
        (cd "$dir" && cargo audit 2>&1) || true
        (cd "$dir" && cargo deny check 2>&1) || true
    done

# Auto-fix lint issues
[group('extended')]
[script]
fix repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    for r in $(resolve_repo "{{repo}}" "fix"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        echo "═══ fix: $r ($tc) ═══"
        case "$tc" in
            rust)
                (cd "$dir" && cargo fmt --all 2>&1) || true
                (cd "$dir" && cargo clippy --workspace --fix --allow-dirty --allow-staged 2>&1) || true
                ;;
            npm)     (cd "$dir" && npx prettier --write src/ 2>&1) || true ;;
            xcode)
                (cd "$dir" && swiftformat . 2>&1) || true
                (cd "$dir" && swiftlint --fix 2>&1) || true
                ;;
            *)       echo "  (no fix step for $tc)" ;;
        esac
    done

# Serve the website locally (http://localhost:3000)
[group('extended')]
run-website *args:
    cd website && npx serve public {{args}}

# Watch for changes and run tests (core only)
[group('extended')]
[working-directory('core')]
watch:
    cargo watch -x "test --workspace"

# Engineering metrics dashboard (PI-21)
[group('extended')]
metrics *args:
    ./scripts/scripts/engineering-metrics.sh {{args}}

# Push engineering metrics to Prometheus pushgateway
[group('extended')]
metrics-push *args:
    ./scripts/scripts/ci/metrics-push.sh {{args}}

# Run tests with coverage
[group('extended')]
[script]
coverage *args:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/quiet-runner.sh
    _qr_parse_args {{args}}
    for r in $(resolve_repo "${_QR_REPO:-}" "coverage"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        tfeats=$(repo_test_features "$r")
        echo "═══ coverage: $r ($tc) ═══"
        _do_step() {
            case "$tc" in
                rust)
                    (cd "$dir" && cargo llvm-cov --workspace --html $tfeats 2>&1)
                    ;;
                gradle)
                    (cd "$dir" && ./gradlew jacocoDebugTestReport 2>&1)
                    ;;
                npm)
                    (cd "$dir" && npx vitest run --coverage 2>&1)
                    ;;
                xcode)
                    if [[ "$(uname)" != "Darwin" ]]; then
                        echo "SKIP: iOS coverage requires macOS" >&2
                        return 0
                    fi
                    rm -rf "$dir/coverage_result.xcresult"
                    (cd "$dir" && xcodebuild -scheme Vauchi \
                        -destination 'platform=iOS Simulator,name={{ ios_simulator }}' \
                        -enableCodeCoverage YES \
                        -resultBundlePath "$dir/coverage_result" \
                        test 2>&1)
                    xcrun xccov view --report "$dir/coverage_result.xcresult"
                    ;;
            esac
        }
        run_step "$r" _do_step
    done
    print_summary "coverage" || exit 1
    echo ""
    echo "Reports:"
    for r in $(resolve_repo "${_QR_REPO:-}" "coverage"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        case "$tc" in
            rust)   echo "  $r: $dir/target/llvm-cov/html/index.html" ;;
            gradle) echo "  $r: $dir/app/build/reports/jacoco/jacocoDebugTestReport/html/index.html" ;;
            npm)    echo "  $r: $dir/coverage/index.html" ;;
            xcode)  echo "  $r: $dir/coverage_result.xcresult (open with Xcode)" ;;
        esac
    done

# Run Criterion benchmarks
[group('extended')]
[script]
bench *args:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/quiet-runner.sh
    _qr_parse_args {{args}}
    for r in $(resolve_repo "${_QR_REPO:-}" "bench"); do
        dir=$(repo_dir "$r")
        echo "═══ bench: $r ═══"
        _do_step() {
            (cd "$dir" && cargo bench 2>&1)
        }
        run_step "$r" _do_step
    done
    print_summary "bench" || exit 1

# Generate and open Rust docs
[group('extended')]
[working-directory('core')]
docs:
    cargo doc --workspace --no-deps --open

# Install git hooks (pre-commit + pre-push) across all repos
[group('extended')]
install-hooks:
    bash scripts/install-hooks.sh

# Check file sizes against thresholds (src: 500/1000, test: 800/1200)
[group('tools')]
[script]
lint-file-size repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    RUST_REPOS="$(repos_by_toolchain rust)"
    if [[ -z "{{repo}}" ]]; then
        repos="$RUST_REPOS"
    elif [[ "{{repo}}" == "all" ]]; then
        repos="$RUST_REPOS"
    else
        repos="{{repo}}"
    fi
    FAILED=0
    for r in $repos; do
        dir=$(repo_dir "$r")
        if [[ ! -d "$dir" ]]; then continue; fi
        echo "═══ file-size: $r ═══"
        scripts/scripts/check-file-size.sh "$dir" || FAILED=1
    done
    if [[ $FAILED -ne 0 ]]; then exit 1; fi

# Show file churn + size correlation (highest-risk files)
[group('tools')]
[script]
churn repo='core':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    dir=$(repo_dir "{{repo}}")
    echo "═══ File Churn + Size: {{repo}} (last 3 months) ═══"
    echo ""
    echo "Commits  Lines  File"
    echo "───────  ─────  ────"
    git -C "$dir" log --format='%H' --since='3 months ago' \
        | xargs -I{} git -C "$dir" diff-tree --no-commit-id --name-only -r {} \
        | sort | uniq -c | sort -rn | head -30 \
        | while read -r count file; do
            filepath="$dir/$file"
            if [[ -f "$filepath" && "$file" == *.rs ]]; then
                lines=$(wc -l < "$filepath" | tr -d ' ')
                if [[ $lines -gt 500 ]]; then
                    printf "%7d  %5d  %s  ← LARGE\n" "$count" "$lines" "$file"
                else
                    printf "%7d  %5d  %s\n" "$count" "$lines" "$file"
                fi
            fi
        done
    echo ""
    echo "Files marked ← LARGE exceed 500 lines and are high-churn: prioritize splitting."

# Show quick reference
[group('tools')]
[script]
help:
    cat <<'HELP'
    Vauchi Development Commands
    ═══════════════════════════

    Daily workflow:
      just check [repo]       Format + lint + test
      just build [repo]       Build
      just test [repo]        Run tests
      just fmt [repo]         Format code
      just lint [repo]        Run lints
      just fix [repo]         Auto-fix formatting + lint
      just commit             Interactive commit across repos
      just commit-repo <r> <msg>  Non-interactive commit (for automation)

      Repo argument: omit = auto-detect from pwd (or all from workspace root)
      Examples: just test core, just lint cli, just check ios
      Valid repos: core cli relay tui e2e android ios docs
                   locales themes features website scripts
                   macos windows linux-gtk linux-qt web-demo

    GitLab:
      just gitlab mr-list [repo]            List open MRs
      just gitlab mr-view <id> [repo]       View MR details
      just gitlab mr-create [repo] [title]  Create MR from current branch
      just gitlab mr-approve <id> [repo]    Approve MR
      just gitlab mr-merge <id> [repo]      Merge MR
      just gitlab mr-status [repo]          MR status for current branch
      just gitlab pipeline-status [repo]    Pipeline status (current branch)
      just gitlab pipeline-list [repo]      Recent pipelines
      just gitlab pipeline-log <id> [repo]  Job log output
      just gitlab pipeline-wait [repo]      Wait for pipeline to complete
      just gitlab issue-list [repo]         List open issues
      just gitlab issue-create <t> [repo]   Create issue

    Git (multi-repo):
      just git sync           Fetch all + pull where on main
      just git main           Switch to main (prompts: wip/stash/abort)
      just git main wip       Switch to main (auto-WIP-commit, non-interactive)
      just git main yes       Switch to main (auto-stash, non-interactive)
      just git wip [msg]      Save WIP checkpoint commits (safer than stash)
      just git wip-undo       Undo WIP commits (soft reset, keeps changes)
      just git resume <branch> Switch to branch + auto-undo WIP commits
      just git status         Show status across all repos
      just git branch-status  Branch state: ahead/behind/merged
      just git stale-branches [days]  Find branches with no recent activity
      just git diff-main [r]  Diff current branch vs main
      just git log-branch [r] Commits on branch not on main
      just git rebase-main [r] Rebase branch on origin/main
      just git pull-all       Pull latest in all repos
      just git push-all       Push repos with commits ahead (full checks)
      just git push-all skip-tests  Push without running tests
      just git fetch          Fetch all repos
      just git branches       Show branches across repos
      just git branch <name> [repos]  Create branch across repos
      just git stash-list     Show stashes across all repos
      just git cleanup        Preview merged branch cleanup
      just git cleanup run    Delete merged branches + prune refs

    Worktrees (parallel development):
      just worktree create <branch> [repos]  Create parallel checkout
      just worktree list      List active worktrees
      just worktree remove <branch>  Remove worktree (interactive)
      just worktree remove-force <branch>  Remove worktree (non-interactive)

    Apps:
      just run <platform>     Run app (cli|tui|relay|android|ios)
      just relay              Start relay server
      just tui                Run TUI

    Deploy:
      just deploy             Deploy relay + landing (Kamal)
      just deploy-check       Check deployed versions vs origin/main
      just core-freshness     Check if bindings/consumers are up to date with core
      just schema-check       Verify JSON schemas match core UI types
      just design-check       Validate design docs (YAML, coverage, cross-refs)

    Housekeeping:
      just housekeeping       Run all health checks (changes, snapshots, stashes,
                              branches, merged refs, stale plans, problems, drift)

    Extended:
      just test-crate <crate> Test specific crate in core workspace
      just test-file <name> [repo]  Run single test file
      just test-name <pat> [repo]   Run tests matching name pattern
      just audit [repo]       Security audit (Rust repos)
      just coverage           Coverage report (core)
      just watch              Watch + test (core)
      just build-release      Release build (core)
      just release-dev [repo] [version]    Create dev tag (fast pipeline)
      just release-rc [repo] [version]     Create RC tag (full quality gate)
      just release-prod [repo]             Create PROD tag (full release)
      just release-history [repo] [ver]    Show version promotion chain

    Setup:
      just setup              Clone all repos, init workspace
      just install-dev-deps   Install toolchain (Homebrew + Cargo)
      just clean              Clean all build artifacts

    Tools:
      just grep <pattern> [glob]  Search across all repos
      just concept <name>     Search by drift concept + aliases
      just consumers <pattern> Find downstream usage of core API
      just lint-file-size [repo]  Check file sizes against thresholds
      just churn [repo]       File churn + size correlation (risk)
      just check-refs         Verify Cargo.toml branch refs → main
      just check-annotations [repo]  Check @scenario coverage
      just check-lifecycle    Validate feature lifecycle tags
      just reuse [repo]       REUSE / SPDX license header check
      just metrics            Engineering metrics dashboard
      just lint-docs          Check doc naming, links, license text
      just sync-locales       Validate locale files
      just vrt-gallery        Cross-platform VRT gallery

    Full list:  just --list --list-submodules
    HELP

# ═══════════════════════════════════════════════════════════════════
# HOUSEKEEPING
# ═══════════════════════════════════════════════════════════════════

# Safely clean orphaned vauchi test temp dirs (skips Claude session data)
[group('daily')]
[script]
tmp-clean:
    set -uo pipefail
    me=$(whoami)
    cleaned=0
    skipped=0
    # Only target .tmp* dirs containing vauchi.db, older than 5 minutes, with no open handles
    while IFS= read -r dbfile; do
        dir=$(dirname "$dbfile")
        # Skip if any process has files open in this dir
        if lsof +D "$dir" &>/dev/null; then
            skipped=$((skipped + 1))
            continue
        fi
        rm -rf "$dir"
        cleaned=$((cleaned + 1))
    done < <(find /tmp -maxdepth 2 -user "$me" -name 'vauchi.db' -path '/tmp/.tmp*' -mmin +5 2>/dev/null)
    echo "Cleaned $cleaned test temp dir(s), skipped $skipped (in use)"

# Remove stale cargo artifacts older than N days (default: 30) across all Rust repos
[group('daily')]
[script]
sweep days="30":
    set -euo pipefail
    if ! command -v cargo-sweep &>/dev/null; then
        echo "cargo-sweep not installed. Run: cargo install cargo-sweep"
        exit 1
    fi
    source scripts/scripts/resolve-repo.sh
    read -ra rust_dirs <<< "$(repos_by_toolchain rust)"
    total_before=0
    total_after=0
    for dir in "${rust_dirs[@]}"; do
        target="$dir/target"
        [[ -d "$target" ]] || continue
        before=$(du -sm "$target" 2>/dev/null | cut -f1)
        total_before=$((total_before + before))
        cargo sweep --time {{days}} "$dir" 2>/dev/null
        after=$(du -sm "$target" 2>/dev/null | cut -f1)
        total_after=$((total_after + after))
        freed=$((before - after))
        [[ $freed -gt 0 ]] && echo "  $dir: freed ${freed} MB (${before} → ${after} MB)"
    done
    total_freed=$((total_before - total_after))
    echo "Total: freed ${total_freed} MB (${total_before} → ${total_after} MB)"

# Run all non-destructive health checks and print a summary
[group('daily')]
[script]
housekeeping:
    set -uo pipefail
    source scripts/scripts/for-each-repo.sh
    source scripts/scripts/resolve-repo.sh
    ISSUES=0
    SECTION=0

    section() {
        SECTION=$((SECTION + 1))
        echo ""
        echo "═══ [$SECTION] $1 ═══"
    }

    # 0. Fetch remotes, fast-forward main, rebase local branches
    section "Sync with remotes"
    _sync_repo() {
        local label="$1" dir="$2"
        git -C "$dir" fetch origin --prune --quiet 2>/dev/null || { echo "  $label: fetch failed"; return; }
        local branch
        branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "")
        [[ -z "$branch" ]] && return
        if [[ "$branch" == "main" ]]; then
            # Fast-forward main if clean
            if git -C "$dir" diff --quiet 2>/dev/null && git -C "$dir" diff --cached --quiet 2>/dev/null; then
                local behind
                behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "0")
                if [[ "$behind" -gt 0 ]]; then
                    git -C "$dir" merge --ff-only origin/main --quiet 2>/dev/null \
                        && echo "  $label: fast-forwarded main ($behind commit(s))" \
                        || echo "  $label: main diverged, cannot fast-forward"
                fi
            fi
        else
            # Rebase feature branch onto latest origin/main
            if git -C "$dir" diff --quiet 2>/dev/null && git -C "$dir" diff --cached --quiet 2>/dev/null; then
                local rebase_output
                rebase_output=$(git -C "$dir" rebase origin/main 2>&1) \
                    && { echo "$rebase_output" | grep -q "up to date" || echo "  $label: rebased $branch onto origin/main"; } \
                    || { echo "  $label: rebase failed on $branch — resolve manually"; git -C "$dir" rebase --abort 2>/dev/null; ISSUES=$((ISSUES + 1)); }
            else
                echo "  $label: skipped rebase (dirty working tree on $branch)"
            fi
        fi
    }
    for_each_repo _sync_repo
    echo "  Sync complete"

    # 1. Uncommitted changes & untracked files
    section "Uncommitted changes"
    dirty=0
    _check_uncommitted() {
        local label="$1" dir="$2"
        local status
        status=$(git -C "$dir" status --porcelain 2>/dev/null || true)
        if [[ -n "$status" ]]; then
            local modified untracked
            modified=$(echo "$status" | grep -c '^ M\|^M \|^MM' || true)
            untracked=$(echo "$status" | grep -c '^??' || true)
            local parts=()
            [[ "$modified" -gt 0 ]] && parts+=("$modified modified")
            [[ "$untracked" -gt 0 ]] && parts+=("$untracked untracked")
            local detail
            detail=$(IFS=', '; echo "${parts[*]}")
            echo "  $label: $detail"
            dirty=$((dirty + modified + untracked))
        fi
    }
    for_each_repo _check_uncommitted
    if [[ "$dirty" -eq 0 ]]; then
        echo "  All clean"
    else
        ISSUES=$((ISSUES + dirty))
    fi

    # 2. Unreviewed insta snapshots
    section "Unreviewed snapshots"
    snaps=$(find . -name '*.snap.new' -not -path '*/target/*' 2>/dev/null || true)
    if [[ -n "$snaps" ]]; then
        count=$(echo "$snaps" | wc -l | tr -d ' ')
        echo "  $count unreviewed snapshot(s):"
        echo "$snaps" | sed 's/^/    /'
        echo "  -> Run: (cd tui && cargo insta review)"
        ISSUES=$((ISSUES + count))
    else
        echo "  None"
    fi

    # 3. Stashes
    section "Stashes"
    stash_total=0
    _check_stashes() {
        local label="$1" dir="$2"
        local stash_count
        stash_count=$(git -C "$dir" stash list 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$stash_count" -gt 0 ]]; then
            echo "  $label: $stash_count stash(es)"
            git -C "$dir" stash list 2>/dev/null | head -3 | sed 's/^/    /'
            [[ "$stash_count" -gt 3 ]] && echo "    ... and $((stash_count - 3)) more"
            stash_total=$((stash_total + stash_count))
        fi
    }
    for_each_repo _check_stashes
    if [[ "$stash_total" -eq 0 ]]; then
        echo "  None"
    else
        ISSUES=$((ISSUES + stash_total))
    fi

    # 4. Leftover WIP commits
    section "WIP commits (unsaved work)"
    wip_count=0
    _check_wip() {
        local label="$1" dir="$2"
        local head_msg
        head_msg=$(git -C "$dir" log -1 --format=%s 2>/dev/null || true)
        if [[ "$head_msg" == wip:* ]]; then
            local branch
            branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "detached")
            echo "  $label ($branch): $head_msg"
            wip_count=$((wip_count + 1))
        fi
    }
    for_each_repo _check_wip
    if [[ "$wip_count" -eq 0 ]]; then
        echo "  None"
    else
        echo "  $wip_count repo(s) with WIP commits at HEAD"
        echo "  -> Undo with: just git wip-undo"
        ISSUES=$((ISSUES + wip_count))
    fi

    # 5. Stale local branches (non-main, with age)
    section "Stale local branches"
    stale_branches=0
    now_epoch=$(date +%s)
    _check_stale_branches() {
        local label="$1" dir="$2"
        local branches
        branches=$(git -C "$dir" branch --no-color 2>/dev/null | grep -v '^\* ' | grep -v 'main$' | sed 's/^[[:space:]]*//' || true)
        if [[ -n "$branches" ]]; then
            while IFS= read -r br; do
                [[ -z "$br" ]] && continue
                local last_epoch age_days age_label
                last_epoch=$(git -C "$dir" log -1 --format=%ct "$br" 2>/dev/null || echo "$now_epoch")
                age_days=$(( (now_epoch - last_epoch) / 86400 ))
                if [[ "$age_days" -ge 14 ]]; then
                    age_label="${age_days}d STALE"
                else
                    age_label="${age_days}d"
                fi
                echo "  $label: $br ($age_label)"
                stale_branches=$((stale_branches + 1))
            done <<< "$branches"
        fi
    }
    for_each_repo _check_stale_branches
    if [[ "$stale_branches" -eq 0 ]]; then
        echo "  None"
    else
        echo "  $stale_branches local branch(es) besides main"
        echo "  -> Detail: just git stale-branches"
        ISSUES=$((ISSUES + stale_branches))
    fi

    # 6. Merged remote branches
    section "Merged remote branches"
    merged=$(just git cleanup 2>&1 | grep -E '^\s+origin/' || true)
    if [[ -n "$merged" ]]; then
        count=$(echo "$merged" | wc -l | tr -d ' ')
        echo "  $count merged remote ref(s):"
        echo "$merged" | sed 's/^/  /'
        echo "  -> Run: just git cleanup run"
        ISSUES=$((ISSUES + count))
    else
        echo "  None"
    fi

    # 7. Stale plans
    section "Stale plans (30+ days)"
    stale_output=$(just plan-stale 2>&1 || true)
    stale_count=$(echo "$stale_output" | grep -c 'STALE' || true)
    if [[ "$stale_count" -gt 0 ]]; then
        echo "$stale_output" | grep 'STALE' | sed 's/^/  /'
        ISSUES=$((ISSUES + stale_count))
    else
        echo "  None"
    fi

    # 8. Problem records summary
    section "Problem records"
    just problem-list 2>&1 | sed 's/^/  /'

    # 9. Stale local binding artifacts
    section "Stale local binding artifacts"
    stale_bindings=0
    # Android: .so files in jniLibs without -PlocalBindings flag
    android_jniLibs="android/app/src/main/jniLibs"
    if [[ -d "$android_jniLibs" ]]; then
        so_count=$(find "$android_jniLibs" -name '*.so' 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$so_count" -gt 0 ]]; then
            echo "  android: $so_count stale .so file(s) in app/src/main/jniLibs/"
            echo "  -> These shadow the Maven AAR and cause runtime crashes!"
            echo "  -> Fix: rm -rf android/app/src/main/jniLibs/*/"
            stale_bindings=$((stale_bindings + so_count))
        fi
    fi
    # Android: local Kotlin bindings
    android_local_kt="android/app/src/local-bindings/kotlin"
    if [[ -d "$android_local_kt" ]]; then
        kt_count=$(find "$android_local_kt" -name '*.kt' 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$kt_count" -gt 0 ]]; then
            echo "  android: $kt_count local Kotlin binding file(s) in src/local-bindings/"
            stale_bindings=$((stale_bindings + 1))
        fi
    fi
    # iOS: check for stale .spm-packages or DerivedData
    ios_spm="ios/.spm-packages"
    if [[ -d "$ios_spm" ]]; then
        echo "  ios: .spm-packages/ exists (can cause stale resolution)"
        stale_bindings=$((stale_bindings + 1))
    fi
    if [[ "$stale_bindings" -eq 0 ]]; then
        echo "  None"
    else
        ISSUES=$((ISSUES + stale_bindings))
    fi

    # 10. Drift (high severity only, quick)
    section "Drift (high severity)"
    drift_output=$(just drift --limit=5 2>&1 || true)
    if echo "$drift_output" | grep -q "0 high"; then
        echo "  No high-severity drift"
    else
        echo "$drift_output" | tail -5 | sed 's/^/  /'
    fi

    # 11. Unpushed commits
    section "Unpushed commits"
    unpushed=0
    _check_unpushed() {
        local label="$1" dir="$2"
        local ahead
        ahead=$(git -C "$dir" rev-list --count @{upstream}..HEAD 2>/dev/null || echo "0")
        if [[ "$ahead" -gt 0 ]]; then
            echo "  $label: $ahead commit(s) ahead of origin"
            unpushed=$((unpushed + ahead))
        fi
    }
    for_each_repo _check_unpushed
    if [[ "$unpushed" -eq 0 ]]; then
        echo "  All repos up to date with origin"
    else
        echo "  -> Push with: just git push-all"
        ISSUES=$((ISSUES + unpushed))
    fi

    # 12. Unreviewed proposals
    section "Unreviewed proposals"
    proposals_dir="_private/docs/planning/proposals"
    if [[ -d "$proposals_dir" ]]; then
        prop_count=$(find "$proposals_dir" -name '*.md' -not -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$prop_count" -ge 5 ]]; then
            echo "  ALERT: $prop_count unreviewed proposal(s) (threshold: 5)"
            find "$proposals_dir" -name '*.md' -not -name 'README.md' 2>/dev/null | while IFS= read -r f; do echo "    $(basename "$f")"; done
            ISSUES=$((ISSUES + prop_count))
        elif [[ "$prop_count" -gt 0 ]]; then
            echo "  $prop_count proposal(s)"
        else
            echo "  None"
        fi
    else
        echo "  None"
    fi

    # 13. Stale problem records (14d intake, 30d other phases)
    # Uses git last-modified date (not directory creation date) for accuracy.
    # A record updated yesterday is not stale even if created months ago.
    section "Stale problem records"
    stale_problems=0
    now_epoch=$(date +%s)
    for dir in _private/docs/problems/*/; do
        [[ ! -f "${dir}README.md" ]] && continue
        dirname=$(basename "$dir")
        [[ "$dirname" == "done" ]] && continue
        # Extract status from first 20 lines using sed
        status=$(head -20 "${dir}README.md" | sed -n 's/.*\*\*Status\*\*[[:space:]]*[|:][[:space:]]*`\?\([a-zA-Z]*\).*/\1/p' | head -1 || true)
        status=$(echo "$status" | tr '[:upper:]' '[:lower:]')
        [[ "$status" == "done" || "$status" == "archived" || "$status" == "complete" ]] && continue
        # Use git last-modified date for any file in the problem directory
        # This catches updates to README.md, plan.md, investigation.md, etc.
        last_modified=$(git -C _private log -1 --format=%ct -- "docs/problems/$dirname/" 2>/dev/null || echo "0")
        if [[ "$last_modified" == "0" ]]; then
            # Fallback: directory creation date from name prefix
            date_prefix=$(echo "$dirname" | sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\).*/\1/p')
            [[ -z "$date_prefix" ]] && continue
            last_modified=$(date -j -f "%Y-%m-%d" "$date_prefix" +%s 2>/dev/null || date -d "$date_prefix" +%s 2>/dev/null || continue)
        fi
        age_days=$(( (now_epoch - last_modified) / 86400 ))
        threshold=30
        [[ "$status" == "intake" ]] && threshold=14
        if [[ "$age_days" -ge "$threshold" ]]; then
            echo "  $dirname (${status:-unknown}, ${age_days}d since last update, threshold: ${threshold}d)"
            stale_problems=$((stale_problems + 1))
        fi
    done
    if [[ "$stale_problems" -eq 0 ]]; then
        echo "  None"
    else
        ISSUES=$((ISSUES + stale_problems))
    fi

    # 14. Orphaned worktrees
    section "Orphaned worktrees"
    if [[ -d ".worktrees" ]]; then
        wt_count=$(ls -d .worktrees/*/ 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$wt_count" -gt 0 ]]; then
            echo "  $wt_count active worktree(s):"
            ls -d .worktrees/*/ 2>/dev/null | sed 's|.worktrees/||;s|/||;s/^/    /'
            echo "  -> Remove with: just worktree remove-force <branch>"
            ISSUES=$((ISSUES + wt_count))
        else
            echo "  None"
        fi
    else
        echo "  None"
    fi

    # 15. Orphaned test temp dirs (vauchi-core tests leak TempDir on SIGKILL)
    section "Orphaned test temp dirs"
    # Only count .tmp* dirs containing vauchi.db (test databases), skip others
    test_tmp_count=$(find /tmp -maxdepth 2 -user "$(whoami)" -name 'vauchi.db' -path '/tmp/.tmp*' 2>/dev/null | wc -l | tr -d ' ')
    tmp_total=$(find /tmp -maxdepth 1 -user "$(whoami)" -name '.tmp*' -type d 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$test_tmp_count" -gt 0 ]]; then
        # Only clean dirs with no open file handles (safe)
        stale=$(find /tmp -maxdepth 2 -user "$(whoami)" -name 'vauchi.db' -path '/tmp/.tmp*' -mmin +5 2>/dev/null | wc -l | tr -d ' ')
        echo "  $test_tmp_count test temp dir(s) ($tmp_total total .tmp* dirs)"
        if [[ "$stale" -gt 0 ]]; then
            echo "  $stale older than 5min — safe to clean:"
            echo "  -> just tmp-clean"
        fi
        ISSUES=$((ISSUES + test_tmp_count))
    elif [[ "$tmp_total" -gt 0 ]]; then
        echo "  $tmp_total .tmp* dir(s) (not test databases)"
    else
        echo "  None"
    fi

    # 16. Cargo target sizes
    section "Cargo target sizes"
    total_mb=0
    for dir in $(repos_by_toolchain rust); do
        target="$dir/target"
        [[ -d "$target" ]] || continue
        size_mb=$(du -sm "$target" 2>/dev/null | cut -f1)
        total_mb=$((total_mb + size_mb))
        if [[ "$size_mb" -gt 1024 ]]; then
            echo "  $dir: $((size_mb / 1024)) GB"
        else
            echo "  $dir: ${size_mb} MB"
        fi
    done
    if [[ "$total_mb" -gt 0 ]]; then
        echo "  Total: $((total_mb / 1024)) GB"
        echo "  -> just sweep          (clean artifacts older than 30 days)"
        echo "  -> just sweep 7        (clean artifacts older than 7 days)"
    else
        echo "  No target dirs"
    fi

    # 17. Cargo.toml ref check (branch = "main")
    section "Cargo.toml branch refs"
    ref_output=$(just check-refs 2>&1 || true)
    if echo "$ref_output" | grep -q "not pointing to main"; then
        echo "$ref_output" | grep "not pointing to main" | sed 's/^/  /'
        bad_refs=$(echo "$ref_output" | grep -c "not pointing to main" || true)
        ISSUES=$((ISSUES + bad_refs))
    else
        echo "  All refs point to main"
    fi

    # 18. Just recipe documentation freshness
    section "allow_failure budget"
    if scripts/scripts/check-allow-failure-budget.sh . >/dev/null 2>&1; then
        count=$(scripts/scripts/check-allow-failure-budget.sh . 2>&1 | grep "Current count:" | grep -oE '[0-9]+')
        echo "  $count allow_failure entries (within budget)"
    else
        output=$(scripts/scripts/check-allow-failure-budget.sh . 2>&1 || true)
        count=$(echo "$output" | grep "Current count:" | grep -oE '[0-9]+')
        budget=$(echo "$output" | grep "Budget:" | grep -oE '[0-9]+')
        echo "  OVER BUDGET: $count allow_failure entries (budget: $budget)"
        echo "  -> scripts/scripts/check-allow-failure-budget.sh .   (details)"
        ISSUES=$((ISSUES + 1))
    fi

    section "Recipe documentation"
    doc_output=$(just check-just-docs 2>&1 || true)
    if echo "$doc_output" | grep -q "^OK"; then
        echo "  All recipes documented"
    else
        undoc=$(echo "$doc_output" | grep -c "^  -" || true)
        echo "  $undoc undocumented recipe(s)"
        echo "  -> just check-just-docs fix   (auto-append missing)"
        ISSUES=$((ISSUES + undoc))
    fi

    # Summary
    echo ""
    echo "──────────────────────────────────────────"
    if [[ "$ISSUES" -eq 0 ]]; then
        echo "Housekeeping: all clear!"
    else
        echo "Housekeeping: $ISSUES item(s) need attention"
    fi

# ═══════════════════════════════════════════════════════════════════
# CROSS-REPO TOOLS
# ═══════════════════════════════════════════════════════════════════

# Search across all repos for a pattern
# Usage: just grep "fn exchange"
#        just grep "vauchi_core" "*.toml"
[group('tools')]
[no-cd]
[script]
grep pattern glob='':
    set -uo pipefail
    source scripts/scripts/for-each-repo.sh
    GLOB_ARGS=()
    if [[ -n "{{ glob }}" ]]; then
        GLOB_ARGS=(--glob "{{ glob }}")
    fi
    _grep_repo() {
        local label="$1" dir="$2"
        # Skip generated/vendor dirs
        results=$(rg "{{ pattern }}" "$dir" \
            --no-heading --color=never \
            --glob '!target/' --glob '!node_modules/' --glob '!dist/' \
            --glob '!*.lock' --glob '!.git/' \
            ${GLOB_ARGS[@]+"${GLOB_ARGS[@]}"} 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            echo "── $label ──"
            echo "$results"
            echo ""
        fi
    }
    for_each_repo _grep_repo

# Verify Cargo.toml branch refs point to main
# Usage: just check-refs
[group('tools')]
[no-cd]
[script]
check-refs:
    set -euo pipefail
    echo "Checking Cargo.toml git dependency branch refs..."
    found=0
    while IFS= read -r line; do
        file=$(echo "$line" | cut -d: -f1)
        content=$(echo "$line" | cut -d: -f2-)
        # Extract the branch value
        branch_val=$(echo "$content" | sed -n 's/.*branch\s*=\s*"\([^"]*\)".*/\1/p')
        if [[ "$branch_val" != "main" ]]; then
            echo "  FAIL: $file"
            echo "        $content"
            echo "        branch = \"$branch_val\" (expected \"main\")"
            echo ""
            found=1
        fi
    done < <(rg 'branch\s*=' --glob '*/Cargo.toml' --glob 'Cargo.toml' --no-heading 2>/dev/null || true)
    if [[ "$found" -eq 0 ]]; then
        echo "  All branch refs point to main"
    else
        echo "FAIL: Non-main branch refs found. Fix before pushing."
        exit 1
    fi

# Check crypto-critical crate versions are consistent across all Cargo.lock files
# Catches version skew where cli and relay could ship different zeroize/chacha20/subtle versions
[group('tools')]
[no-cd]
[script]
check-lockfile-consistency:
    set -euo pipefail
    echo "Checking crypto crate version consistency across Cargo.lock files..."
    echo ""

    # Crypto-critical crates that MUST be the same version everywhere
    CRITICAL_CRATES="ed25519-dalek x25519-dalek sha2 hmac hkdf chacha20poly1305 argon2 zeroize subtle curve25519-dalek aead"

    LOCKFILES=()
    LABELS=()
    for dir in $(repos_by_toolchain rust); do
        if [[ -f "$dir/Cargo.lock" ]]; then
            LOCKFILES+=("$dir/Cargo.lock")
            LABELS+=("$dir")
        fi
    done

    if [[ ${#LOCKFILES[@]} -lt 2 ]]; then
        echo "  Only ${#LOCKFILES[@]} Cargo.lock file(s) found — nothing to compare"
        exit 0
    fi

    divergent=0
    for crate in $CRITICAL_CRATES; do
        versions=()
        sources=()
        for i in "${!LOCKFILES[@]}"; do
            # Extract version from Cargo.lock (format: name = "crate"\nversion = "x.y.z")
            ver=$(sed -n "/^name = \"${crate}\"\$/,/^$/{ s/^version = \"\(.*\)\"/\1/p; }" "${LOCKFILES[$i]}" | head -1)
            if [[ -n "$ver" ]]; then
                versions+=("$ver")
                sources+=("${LABELS[$i]}=$ver")
            fi
        done

        # Check if all versions are the same
        if [[ ${#versions[@]} -gt 1 ]]; then
            unique=$(printf '%s\n' "${versions[@]}" | sort -u | wc -l | tr -d ' ')
            if [[ "$unique" -gt 1 ]]; then
                echo "  DIVERGENT: $crate"
                for s in "${sources[@]}"; do
                    echo "    $s"
                done
                divergent=$((divergent + 1))
            fi
        fi
    done

    if [[ "$divergent" -eq 0 ]]; then
        echo "  All ${#LOCKFILES[@]} lockfiles agree on crypto crate versions"
    else
        echo ""
        echo "FAIL: $divergent crypto crate(s) have version skew across repos"
        echo "Fix: run 'cargo update -p <crate>' in the divergent repos"
        exit 1
    fi

# Verify cosign.pub is identical across all repos that serve it
# Source of truth: core/cosign.pub. Self-healing: run with 'fix' to sync.
# Usage: just check-cosign-pub [fix]
[group('tools')]
[no-cd]
[script]
check-cosign-pub action='check':
    set -euo pipefail
    SOURCE="core/cosign.pub"
    COPIES=(
        "website/app-files-src/cosign.pub"
        "website/public/.well-known/cosign.pub"
        "docs/docs/.well-known/cosign.pub"
    )
    if [[ ! -f "$SOURCE" ]]; then
        echo "ERROR: source of truth missing: $SOURCE"
        exit 1
    fi
    SOURCE_HASH=$(sha256sum "$SOURCE" | cut -d' ' -f1)
    divergent=0
    for copy in "${COPIES[@]}"; do
        if [[ ! -f "$copy" ]]; then
            echo "  MISSING: $copy"
            divergent=$((divergent + 1))
            if [[ "{{ action }}" == "fix" ]]; then
                mkdir -p "$(dirname "$copy")"
                cp "$SOURCE" "$copy"
                echo "    → copied from $SOURCE"
            fi
        else
            COPY_HASH=$(sha256sum "$copy" | cut -d' ' -f1)
            if [[ "$SOURCE_HASH" != "$COPY_HASH" ]]; then
                echo "  DIVERGENT: $copy (hash mismatch)"
                divergent=$((divergent + 1))
                if [[ "{{ action }}" == "fix" ]]; then
                    cp "$SOURCE" "$copy"
                    echo "    → synced from $SOURCE"
                fi
            fi
        fi
    done
    if [[ "$divergent" -eq 0 ]]; then
        echo "  cosign.pub: all ${#COPIES[@]} copies match $SOURCE (sha256:${SOURCE_HASH:0:16}…)"
    elif [[ "{{ action }}" != "fix" ]]; then
        echo ""
        echo "Fix: run 'just check-cosign-pub fix' to sync from $SOURCE"
        exit 1
    else
        echo "  Fixed $divergent divergent copies"
    fi

# Validate CLAUDE.md: check referenced files exist, detect orphaned docs
# Self-healing: catches stale references and new docs not yet referenced
# Usage: just check-claude-md
[group('tools')]
[no-cd]
[script]
check-claude-md:
    set -euo pipefail
    CLAUDE_MD="CLAUDE.md"
    DOCS_DIR=".claude/docs"
    errors=0
    # 1. Check all .claude/docs/ and .claude/rules/ paths referenced in CLAUDE.md exist
    for ref in $(grep -oE '`[^`]*\.md`' "$CLAUDE_MD" | tr -d '`' | grep -E '\.claude/'); do
        if [[ ! -f "$ref" ]]; then
            echo "  BROKEN REF: $ref (referenced in CLAUDE.md but missing)"
            errors=$((errors + 1))
        fi
    done
    # 2. Check for orphaned docs (in .claude/docs/ but not referenced anywhere)
    for f in "$DOCS_DIR"/*.md; do
        name=$(basename "$f")
        # Check CLAUDE.md, rules/, and skills/
        if ! grep -qr "$name" "$CLAUDE_MD" .claude/rules/ .claude/skills/ 2>/dev/null; then
            echo "  ORPHANED: $DOCS_DIR/$name (not referenced from CLAUDE.md, rules, or skills)"
            errors=$((errors + 1))
        fi
    done
    # 3. Check _private paths referenced in CLAUDE.md exist
    for ref in $(grep -oE '`_private/[^`]*`' "$CLAUDE_MD" | tr -d '`'); do
        if [[ ! -f "$ref" ]] && [[ ! -d "$ref" ]]; then
            echo "  BROKEN REF: $ref (referenced in CLAUDE.md but missing)"
            errors=$((errors + 1))
        fi
    done
    if [[ "$errors" -eq 0 ]]; then
        echo "  CLAUDE.md: all references valid, no orphaned docs"
    else
        echo ""
        echo "  $errors issue(s) found. Fix references or add docs to CLAUDE.md."
        exit 1
    fi

# Check spelling across all repos (typos — fast, source-code-aware)
# Usage: just spellcheck
[group('tools')]
spellcheck:
    typos .

# Run REUSE compliance check (SPDX license headers)
# Usage: just reuse [repo]   (omit for all repos)
[group('tools')]
[no-cd]
[script]
reuse repo='':
    if ! command -v reuse &>/dev/null; then
        echo "WARNING: reuse not installed (pip install reuse)" >&2
        exit 0
    fi
    set -uo pipefail
    source scripts/scripts/for-each-repo.sh
    if [[ -n "{{ repo }}" ]]; then
        dir="{{ repo }}"
        [[ "$dir" == "root" || "$dir" == "." ]] && dir="."
        echo "── {{ repo }} ──"
        (cd "$dir" && reuse lint 2>&1) || true
    else
        _reuse_repo() {
            local label="$1" dir="$2"
            echo "── $label ──"
            (cd "$dir" && reuse lint 2>&1 | tail -3) || true
            echo ""
        }
        for_each_repo _reuse_repo
    fi

# Search by drift-detector concept (uses concept aliases from driftconfig.toml)
# Usage: just concept exchange     (finds exchange + proximity + qr + nfc + ble + audio + prekey)
#        just concept security     (finds security + auth + attacks + spoofing + passwords)
[group('tools')]
[no-cd]
[script]
concept name:
    set -euo pipefail
    CONFIG="driftconfig.toml"
    if [[ ! -f "$CONFIG" ]]; then
        echo "ERROR: $CONFIG not found" >&2
        exit 1
    fi
    # Build a regex pattern from concept + aliases
    # Extract aliases that resolve to this concept
    aliases=("{{ name }}")
    while IFS= read -r line; do
        # Lines like: "qr-code" = ["exchange", "qr"]  or  "proximity" = "exchange"
        key=$(echo "$line" | sed -n 's/^"\([^"]*\)".*/\1/p')
        [[ -z "$key" ]] && continue
        # Check if value contains our concept
        if echo "$line" | grep -qF "\"{{ name }}\""; then
            aliases+=("$key")
        fi
    done < <(sed -n '/^\[concepts\.aliases\]/,/^\[/p' "$CONFIG" | grep '^"')
    # Also add aliases that ARE the concept (concept = something)
    while IFS= read -r line; do
        key=$(echo "$line" | sed -n 's/^"\([^"]*\)".*/\1/p')
        [[ -z "$key" || "$key" != "{{ name }}" ]] && continue
        vals=$(echo "$line" | sed -n 's/.*= *"\([^"]*\)".*/\1/p')
        if [[ -n "$vals" ]]; then
            aliases+=("$vals")
        fi
    done < <(sed -n '/^\[concepts\.aliases\]/,/^\[/p' "$CONFIG" | grep '^"')
    # Deduplicate
    unique=($(printf '%s\n' "${aliases[@]}" | sort -u))
    # Build regex: join with | for alternation, replace - with [-_] for flexible matching
    pattern=$(printf '%s\n' "${unique[@]}" | sed 's/-/[-_]/g' | paste -sd'|' -)
    echo "Concept: {{ name }}"
    echo "Aliases: ${unique[*]}"
    echo "Pattern: $pattern"
    echo ""
    echo "── Feature scenarios ──"
    rg -i "$pattern" features/ --glob '*.feature' -n --color=never 2>/dev/null | grep -iE "Scenario|Feature:" | head -30 || echo "  (none)"
    echo ""
    echo "── Tests ──"
    rg -i "$pattern" core/vauchi-core/tests/ core/vauchi-platform/tests/ e2e/ cli/ tui/ relay/ linux-gtk/tests/ \
        --glob '*.rs' -l --color=never 2>/dev/null | head -20 || echo "  (none)"
    echo ""
    echo "── Source ──"
    rg -i "$pattern" core/vauchi-core/src/ relay/src/ linux-gtk/src/ \
        --glob '*.rs' -l --color=never 2>/dev/null | head -20 || echo "  (none)"
    echo ""
    echo "── Docs ──"
    rg -i "$pattern" docs/ _private/docs/ \
        --glob '*.md' -l --color=never 2>/dev/null | head -20 || echo "  (none)"

# Check for tests missing @scenario annotations
# Usage: just check-annotations [repo]
[group('tools')]
[no-cd]
[script]
check-annotations repo='core':
    set -uo pipefail
    case "{{ repo }}" in
        core) dirs="core/vauchi-core/tests core/vauchi-platform/tests" ;;
        e2e)  dirs="e2e/tests" ;;
        relay) dirs="relay/tests" ;;
        cli)  dirs="cli/tests" ;;
        tui)  dirs="tui/tests" ;;
        all)  dirs="core/vauchi-core/tests core/vauchi-platform/tests e2e/tests relay/tests cli/tests tui/tests" ;;
        *)    echo "Unknown repo: {{ repo }}"; exit 1 ;;
    esac
    total=0
    annotated=0
    missing=()
    for dir in $dirs; do
        [[ ! -d "$dir" ]] && continue
        while IFS= read -r file; do
            while IFS= read -r test_name; do
                line_num=$(echo "$test_name" | cut -d: -f1)
                fn_name=$(echo "$test_name" | sed 's/.*fn //' | sed 's/(.*//')
                total=$((total + 1))
                # Check if preceding lines have @scenario annotation
                prev_lines=$(head -n "$line_num" "$file" | tail -5)
                if echo "$prev_lines" | grep -q "@scenario:"; then
                    annotated=$((annotated + 1))
                else
                    missing+=("$file:$line_num $fn_name")
                fi
            done < <(grep -n '#\[test\]' "$file" | while IFS= read -r test_line; do
                num=$(echo "$test_line" | cut -d: -f1)
                # Get the fn line after #[test]
                fn_line=$(sed -n "$((num+1)),$((num+5))p" "$file" | grep -m1 'fn ')
                if [[ -n "$fn_line" ]]; then
                    echo "$num:$fn_line"
                fi
            done)
        done < <(find $dir -name '*.rs' -type f 2>/dev/null)
    done
    echo "Annotation coverage: $annotated/$total tests have @scenario"
    pct=0
    [[ "$total" -gt 0 ]] && pct=$((annotated * 100 / total))
    echo "Coverage: ${pct}%"
    echo ""
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing @scenario annotations (${#missing[@]}):"
        printf '  %s\n' "${missing[@]}" | head -30
        [[ ${#missing[@]} -gt 30 ]] && echo "  ... and $((${#missing[@]} - 30)) more"
    fi

# Validate feature lifecycle tags (@implemented/@planned/@wip)
# Every Scenario and Scenario Outline must have exactly one lifecycle tag
[group('tools')]
[no-cd]
[script]
check-lifecycle:
    set -uo pipefail
    echo "Checking feature lifecycle tags..."
    echo ""
    errors=0
    total=0
    while IFS= read -r file; do
        line_num=0
        while IFS= read -r line; do
            line_num=$((line_num + 1))
            # Find Scenario/Scenario Outline lines
            if echo "$line" | grep -qE '^\s*(Scenario|Scenario Outline):'; then
                total=$((total + 1))
                # Look back up to 5 lines for lifecycle tags
                start=$((line_num - 5))
                [[ "$start" -lt 1 ]] && start=1
                context=$(sed -n "${start},${line_num}p" "$file")
                has_impl=$(echo "$context" | grep -c '@implemented' || true)
                has_planned=$(echo "$context" | grep -c '@planned' || true)
                has_wip=$(echo "$context" | grep -c '@wip' || true)
                tag_count=$((has_impl + has_planned + has_wip))
                if [[ "$tag_count" -eq 0 ]]; then
                    scenario=$(echo "$line" | sed 's/^[[:space:]]*//')
                    echo "  MISSING: $file:$line_num"
                    echo "    $scenario"
                    errors=$((errors + 1))
                elif [[ "$tag_count" -gt 1 ]]; then
                    scenario=$(echo "$line" | sed 's/^[[:space:]]*//')
                    echo "  MULTIPLE: $file:$line_num (has $tag_count lifecycle tags)"
                    echo "    $scenario"
                    errors=$((errors + 1))
                fi
            fi
        done < "$file"
    done < <(find features/ -name '*.feature' -type f 2>/dev/null | sort)
    echo ""
    echo "Checked $total scenarios, $errors issues"
    if [[ "$errors" -gt 0 ]]; then
        echo "FAIL: Fix missing/duplicate lifecycle tags above"
        exit 1
    else
        echo "OK: All scenarios have exactly one lifecycle tag"
    fi

# Check that just-commands.md documents all public recipes
# Self-healing: run `just check-just-docs fix` to append missing recipes
[group('tools')]
[no-cd]
check-just-docs action='check':
    #!/usr/bin/env bash
    set -uo pipefail
    DOC="{{ justfile_directory() }}/.claude/docs/just-commands.md"
    MISSING=()
    # Extract all public recipe names from just --list
    while IFS= read -r line; do
        recipe=$(echo "$line" | sed 's/^[[:space:]]*//' | cut -d' ' -f1)
        [[ -z "$recipe" ]] && continue
        [[ "$recipe" =~ ^\[ ]] && continue     # skip [group] headers
        [[ "$recipe" == "Available" ]] && continue
        # Check if recipe name appears in docs (word boundary match)
        if ! grep -qE "(^|[^a-z-])${recipe}([^a-z-]|$)" "$DOC" 2>/dev/null; then
            MISSING+=("$recipe")
        fi
    done < <(just --list --unsorted 2>/dev/null)
    if [[ ${#MISSING[@]} -eq 0 ]]; then
        echo "OK: All recipes documented in $DOC"
    elif [[ "{{ action }}" == "fix" ]]; then
        echo "Appending ${#MISSING[@]} missing recipes to $DOC..."
        echo "" >> "$DOC"
        echo "#### Undocumented (auto-detected)" >> "$DOC"
        echo "" >> "$DOC"
        echo '```bash' >> "$DOC"
        for r in "${MISSING[@]}"; do
            echo "just $r" >> "$DOC"
        done
        echo '```' >> "$DOC"
        echo "Done. Review and categorize the additions in $DOC"
    else
        echo "FAIL: ${#MISSING[@]} recipes not in $DOC:"
        for r in "${MISSING[@]}"; do
            echo "  - $r"
        done
        echo ""
        echo "Run 'just check-just-docs fix' to auto-append them."
        exit 1
    fi

# Find downstream consumers of a core function/type across repos
# Usage: just consumers ExchangeSession
#        just consumers "fn get_card"
[group('tools')]
[no-cd]
[script]
consumers pattern:
    set -uo pipefail
    echo "Searching for '{{ pattern }}' across downstream repos..."
    echo ""
    DOWNSTREAM_DIRS=(cli tui e2e relay linux-gtk)
    for dir in "${DOWNSTREAM_DIRS[@]}"; do
        [[ ! -d "$dir" ]] && continue
        label=$(basename "$dir")
        results=$(rg "{{ pattern }}" "$dir" \
            --glob '*.rs' --glob '*.ts' --glob '*.tsx' \
            --glob '!target/' --glob '!node_modules/' --glob '!dist/' \
            -n --color=never 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            count=$(echo "$results" | wc -l | tr -d ' ')
            echo "── $label ($count matches) ──"
            echo "$results"
            echo ""
        fi
    done
    # Also check mobile bindings
    for dir in android ios; do
        [[ ! -d "$dir" ]] && continue
        results=$(rg "{{ pattern }}" "$dir" \
            --glob '*.kt' --glob '*.swift' \
            --glob '!build/' --glob '!.gradle/' \
            -n --color=never 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            count=$(echo "$results" | wc -l | tr -d ' ')
            echo "── $dir ($count matches) ──"
            echo "$results"
            echo ""
        fi
    done

# ═══════════════════════════════════════════════════════════════════
# DOCUMENTATION LINTING
# ═══════════════════════════════════════════════════════════════════

# Lint documentation: naming convention, broken links, license text
[group('tools')]
[script]
lint-docs:
    set -euo pipefail
    ERRORS=0

    # Only scan repos we author (not generated repos like vauchi-platform-*)
    # Note: docs/ is now a mkdocs site without date-prefix convention
    REPOS=("." "_private" "scripts" "assets")

    echo "═══ Checking doc naming convention ═══"
    for repo in "${REPOS[@]}"; do
      [ -d "$repo" ] || continue
      while IFS= read -r -d '' file; do
        filename=$(basename "$file")
        dirname=$(dirname "$file")

        # Skip well-known filenames that don't need date prefixes
        case "$filename" in
          README.md|CLAUDE.md|roadmap.md|VISIBILITY_POLICY.md) continue ;;
          STRUCTURE.md|ARCHITECTURE.md|SECURITY.md|CHECKLIST.md) continue ;;
          investigation.md|implementation-plan.md|retrospective.md|post-mortem.md|rejected-solutions.md) continue ;;
        esac

        # Skip directories where date prefix convention doesn't apply
        echo "$dirname" | grep -q "diagrams" && continue
        echo "$dirname" | grep -q "ideas" && continue
        echo "$dirname" | grep -q "strategy" && continue
        echo "$dirname" | grep -q "infra" && continue
        echo "$dirname" | grep -q "knowledge" && continue
        [ "$dirname" = "$repo" ] && continue
        echo "$dirname" | grep -q "/\." && continue

        # Skip non-doc repos (code repos and assets have their own conventions)
        echo "$file" | grep -qE "^\./?(core|relay|cli|tui|android|ios|e2e|features|assets|macos|windows|linux-gtk|linux-qt|web-demo)/" && continue

        if ! echo "$filename" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-'; then
          echo "  FAIL: $file (missing date prefix)"
          ERRORS=$((ERRORS + 1))
        fi
      done < <(find "$repo" -name "*.md" -not -path "*/node_modules/*" -not -path "*/target/*" -not -path "*/.git/*" -not -path "*/.spm-packages/*" -print0)
    done

    echo ""
    echo "═══ Checking for wrong license references ═══"
    # Only check files that declare OUR license (## License sections, CONTRIBUTING, README footers)
    # Grep for lines that say we are MIT-licensed — not references to other projects' licenses
    WRONG_PATTERNS=(
      "licensed under MIT"
      "License: MIT"
    )
    for pattern in "${WRONG_PATTERNS[@]}"; do
      for repo in "${REPOS[@]}"; do
        [ -d "$repo" ] || continue
        MATCHES=$(grep -rn --include="*.md" -i "$pattern" "$repo" \
          --exclude-dir=node_modules --exclude-dir=target --exclude-dir=.git \
          --exclude-dir=.spm-packages --exclude-dir=knowledge \
          --exclude-dir=problems 2>/dev/null \
          | grep -iv "catppuccin\|dracula\|nord\|solarized\|gruvbox\|third.party\|external\|dependency" || true)
        if [ -n "$MATCHES" ]; then
          echo "$MATCHES"
          echo "  FAIL: Wrong license reference: '$pattern'"
          ERRORS=$((ERRORS + 1))
        fi
      done
    done

    echo ""
    echo "═══ Checking for broken links ═══"
    if command -v lychee &>/dev/null; then
      for repo in "${REPOS[@]}"; do
        [ -d "$repo" ] || continue
        echo "  Checking $repo/"
        lychee --offline --no-progress \
          --exclude-path node_modules \
          --exclude-path target \
          --exclude-path .git \
          --exclude-path .spm-packages \
          "$repo/**/*.md" 2>/dev/null || ERRORS=$((ERRORS + 1))
      done
    else
      echo "  SKIP: lychee not installed (brew install lychee / cargo install lychee)"
    fi

    echo ""
    if [ $ERRORS -gt 0 ]; then
      echo "FAILED: $ERRORS issue(s) found"
      exit 1
    fi
    echo "All documentation checks passed."

# Lint markdown files (line length with backtick-path exemption)
# Usage: just lint-markdown [fix] [paths...]
[group('tools')]
lint-markdown *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    RULE="_private/scripts/markdownlint-rule-line-length.js"
    if ! command -v markdownlint &>/dev/null; then
      echo "SKIP: markdownlint not installed"
      echo "  npm i -g markdownlint-cli"
      exit 0
    fi
    if [ ! -f "$RULE" ]; then
      echo "SKIP: custom rule not found at $RULE"
      exit 0
    fi
    ARGS="{{ ARGS }}"
    FIX=""
    PATHS=""
    for arg in $ARGS; do
      if [ "$arg" = "fix" ]; then
        FIX="--fix"
      else
        PATHS="$PATHS $arg"
      fi
    done
    if [ -z "$PATHS" ]; then
      PATHS="_private/docs/"
    fi
    # Use _private config when scanning _private docs
    CONFIG=""
    if [ -f "_private/.markdownlint.json" ]; then
      CONFIG="-c _private/.markdownlint.json"
    fi
    echo "═══ Markdown lint (backtick-path exempt) ═══"
    if [ -n "$FIX" ]; then
      echo "  Mode: auto-fix"
      markdownlint $CONFIG -r "$RULE" $FIX $PATHS
    else
      markdownlint $CONFIG -r "$RULE" $PATHS
    fi
    echo "All markdown checks passed."

# ═══════════════════════════════════════════════════════════════════
# I18N / LOCALES
# ═══════════════════════════════════════════════════════════════════

# Validate locale files (check for missing/extra keys)
[group('tools')]
sync-locales:
    ./scripts/scripts/sync-locales.sh

# Validate locale files strictly (fail on any issues, for CI)
[group('tools')]
sync-locales-strict:
    ./scripts/scripts/sync-locales.sh --strict

# ═══════════════════════════════════════════════════════════════════
# VISUAL REGRESSION TESTING
# ═══════════════════════════════════════════════════════════════════

# Generate cross-platform VRT gallery (iOS, Android, Desktop, TUI)
[group('tools')]
vrt-gallery:
    ./scripts/scripts/vrt-gallery.sh

# ═══════════════════════════════════════════════════════════════════
# DESIGN DOCS VALIDATION
# ═══════════════════════════════════════════════════════════════════

# Validate design docs: YAML syntax, component types, screen/component coverage, nav consistency
# Usage: just design-check [--verbose]
[group('tools')]
design-check *args:
    uv run _private/scripts/design-check.py {{ args }}

# ═══════════════════════════════════════════════════════════════════
# DRIFT DETECTION
# ═══════════════════════════════════════════════════════════════════

# Run drift audit (human-readable, fail on high severity by default)
# Usage: just drift [--severity=high] [--group-by=category] [--limit=50] [--verbose]
# Backward compat: just drift medium  (sets --fail-on=medium)
[group('tools')]
[script]
drift *args:
    set -euo pipefail
    cd drift-detector
    # Rebuild if dist/ missing or any source file is newer than dist/
    if [[ ! -d dist ]] || [[ -n "$(find src -newer dist/index.js -name '*.ts' 2>/dev/null | head -1)" ]]; then
        echo "Building drift-detector..."
        npm run build --silent
    fi
    # Backward compat: if first arg doesn't start with --, treat as --fail-on value
    EXTRA_ARGS=""
    FAIL_ON="high"
    FIRST=true
    for arg in {{args}}; do
        if $FIRST && [[ ! "$arg" == --* ]]; then
            FAIL_ON="$arg"
            FIRST=false
            continue
        fi
        FIRST=false
        EXTRA_ARGS="$EXTRA_ARGS $arg"
    done
    node dist/index.js --root .. audit --fail-on="$FAIL_ON" $EXTRA_ARGS

# Run drift audit with JSON output (for CI pipelines)
# Usage: just drift-ci [--severity=high] [--category=missing_test] [--limit=100]
[group('tools')]
[script]
drift-ci *args:
    set -euo pipefail
    cd drift-detector
    # Rebuild if dist/ missing or any source file is newer than dist/
    if [[ ! -d dist ]] || [[ -n "$(find src -newer dist/index.js -name '*.ts' 2>/dev/null | head -1)" ]]; then
        echo "Building drift-detector..."
        npm run build --silent
    fi
    EXTRA_ARGS=""
    FAIL_ON="high"
    FIRST=true
    for arg in {{args}}; do
        if $FIRST && [[ ! "$arg" == --* ]]; then
            FAIL_ON="$arg"
            FIRST=false
            continue
        fi
        FIRST=false
        EXTRA_ARGS="$EXTRA_ARGS $arg"
    done
    node dist/index.js --root .. audit --ci --fail-on="$FAIL_ON" $EXTRA_ARGS

# ═══════════════════════════════════════════════════════════════════
# AI/LLM TOOLS
# ═══════════════════════════════════════════════════════════════════

# Explore codebase with local LLM (e.g., just tell-me-about "iOS tests")
[group('tools')]
tell-me-about *topic:
    ./scripts/scripts/tell-me-about.sh {{topic}}

# Find all doc references to a pattern (SP number, problem slug, percentage)
# Use after implementation to find all docs that need updating.
# e.g., just doc-refs "SP-32" or just doc-refs "anonymous-sender"
[group('tools')]
doc-refs pattern:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== References to '{{pattern}}' ==="
    echo ""
    echo "── planning (master plan + roadmap + todos) ──"
    grep -rn "{{pattern}}" _private/docs/planning/ 2>/dev/null || echo "  (none)"
    echo ""
    echo "── active problem records ──"
    grep -rn "{{pattern}}" _private/docs/problems/*/README.md 2>/dev/null | grep -v "/done/" || echo "  (none)"
    echo ""
    echo "── design docs ──"
    grep -rn "{{pattern}}" _private/docs/designs/ 2>/dev/null || echo "  (none)"
    echo ""
    echo "When changing status or percentages, update ALL of the above in one commit."
