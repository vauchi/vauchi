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
public_repos := "gitlab-profile scripts assets core relay ohttp-relay cli tui e2e features android ios docs spec locales themes website vauchi-platform-swift macos windows linux-gtk linux-qt web-demo linux-hw apple-hw android-hw windows-hw"

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

import 'just/architecture.just'

[doc('Multi-repo git operations')]
mod git 'just/git.just'

[doc('GitLab MR, pipeline, and issue operations')]
mod gitlab 'just/gitlab.just'

[doc('Workspace slots — one session per full workspace clone')]
mod slot 'just/slot.just'

[doc('Device rig — one session at a time holds the exchange phones')]
mod rig 'just/rig.just'

[doc('Launch Codex/Kimi with their own claim session id')]
mod harness 'just/harness.just'

[doc('Blog drafts CMS and publishing')]
mod blog 'just/blog.just'

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
import 'just/release.just'

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
    source scripts/scripts/resolve-repo.sh
    if [[ -n "${_QR_REPO:-}" && "$_QR_REPO" != all ]] && [[ "$(repo_toolchain "$_QR_REPO")" == cmake ]]; then
        just cmake-check {{args}}
        exit $?
    fi
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
        fmt_pid=$!
        just lint ${_QR_REPO:-} --quiet &
        lint_pid=$!
        just test ${_QR_REPO:-} --quiet &
        test_pid=$!
        failed=0
        for child in "$fmt_pid" "$lint_pid" "$test_pid"; do
            wait "$child" || failed=1
        done
        qr_print_shared_summary "check" || failed=1
        [[ "$failed" = 0 ]] || exit 1
    else
        just fmt-check ${_QR_REPO:-}
        just lint ${_QR_REPO:-}
        just test ${_QR_REPO:-}
    fi
    # Layer 1 reachability gate — core-scoped, so only runs when
    # the caller targeted core (or all repos). Keeps `just check
    # <non-core-repo>` fast. Plan Task 1.4 Step 3.
    if [ -z "${_QR_REPO:-}" ] || [ "${_QR_REPO:-}" = "core" ]; then
        just reachability
    fi
    # Write TDD stamps for repos that passed all checks
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/stamp.sh
    repos=$(resolve_repo "${_QR_REPO:-}" "test")
    for r in $repos; do
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
    repos=$(resolve_repo "${_QR_REPO:-}" "build")
    for r in $repos; do
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
                mdbook)  (cd "$dir" && mdbook build 2>&1) ;;
                cmake)   bash scripts/scripts/cmake-check.sh "$dir" build ;;
                *)       echo "No build runner for $tc" >&2; return 1 ;;
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
    repos=$(resolve_repo "${_QR_REPO:-}" "test")
    for r in $repos; do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        if ! quiet_enabled; then echo "═══ test: $r ($tc) ═══"; fi
        tfeats=$(repo_test_features "$r")
        _do_step() {
            case "$tc" in
                rust)
                    # E2E tests spawn multiple CLI/relay processes per test and
                    # share the local loopback stack; running them concurrently
                    # exposes timing flakes (see
                    # _private/docs/problems/2026-08-04-e2e-bounded-clock-skew-still-flaky).
                    # Serialise the E2E suite while leaving other Rust repos
                    # at their default parallelism.
                    if [[ "$r" == "e2e" ]]; then
                        # E2E tests are serialised (--test-threads=1) because
                        # they spawn multiple CLI/relay processes per test and
                        # share the local loopback stack. The bounded clock-skew
                        # certification test is still sensitive to cumulative
                        # runner load, so we run it first while the process is
                        # fresh and then run the rest of the suite. See problem
                        # record 2026-08-04-e2e-bounded-clock-skew-still-flaky.
                        local skew_test="integration_six_device_bounded_clock_skew_converges_to_later_update"
                        (cd "$dir" && cargo test --workspace "$skew_test" -- --test-threads=1 2>&1)
                        (cd "$dir" && cargo test --workspace -- --test-threads=1 --skip "$skew_test" 2>&1)
                    else
                        if command -v cargo-nextest &>/dev/null; then
                            (cd "$dir" && cargo nextest run --workspace $tfeats 2>&1)
                        else
                            (cd "$dir" && cargo test --workspace $tfeats 2>&1)
                        fi
                    fi
                    ;;
                npm)     (cd "$dir" && npx playwright test --project=chromium --grep-invert "@visual|@a11y" 2>&1) ;;
                gradle)  (cd "$dir" && ./gradlew test 2>&1) ;;
                xcode)
                    local xc_dest='platform=iOS Simulator,name={{ ios_simulator }}'
                    [[ "$r" == "macos" ]] && xc_dest='platform=macOS'
                    # UI tests need a clean store or --reset-for-testing
                    # seeding fails (2026-05-10-ios-uitests-stale-sim-
                    # dependency). Erase EVERY sim matching the name —
                    # duplicate names across runtimes make single-name
                    # erase hit a different device than xcodebuild boots.
                    if [[ "$r" != "macos" && -z "${JUST_NO_SIM_ERASE:-}" ]]; then
                        xcrun simctl list devices | grep -F '{{ ios_simulator }} (' \
                            | grep -oE '[0-9A-F-]{36}' \
                            | while read -r udid; do
                                xcrun simctl shutdown "$udid" 2>/dev/null || true
                                xcrun simctl erase "$udid" || true
                              done
                    fi
                    (cd "$dir" && xcodebuild -scheme Vauchi -destination "$xc_dest" -skipPackageUpdates test -quiet 2>&1)
                    ;;
                mdbook)  (cd "$dir" && mdbook build 2>&1) ;;
                cmake)   bash scripts/scripts/cmake-check.sh "$dir" test ;;
                *)       echo "No test runner for $tc" >&2; return 1 ;;
            esac
        }
        run_step "$r" _do_step
    done
    print_summary "test" || exit 1

# Run the Rust tests behind web-demo's WASM boundary, then prove that the same
# crate still builds for the browser target. The generic web test recipe
# exercises the TypeScript shell.
[group('extended')]
[script]
test-web-wasm:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    dir=$(repo_dir web-demo)
    [[ "$dir" = /* && -d "$dir/wasm" ]] || {
        echo "Invalid web-demo WASM path: $dir/wasm" >&2
        exit 1
    }
    cd "$dir/wasm"
    command -v wasm-pack >/dev/null 2>&1 || {
        echo "wasm-pack is required for the browser-target build" >&2
        exit 1
    }
    if command -v cargo-nextest >/dev/null 2>&1; then
        cargo nextest run --locked
    else
        cargo test --locked
    fi
    wasm-pack build --target web -- --locked

# Refresh a Rust consumer's Core lock entries without loading path overrides
# from the coordinator checkout. Cargo discovers config from its invocation
# directory, so run from a temporary directory outside the workspace.
[group('tools')]
[script]
refresh-core-lock repo:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    repo={{ quote(repo) }}
    dir=$(repo_dir "$repo")
    [[ "$dir" = /* ]] || {
        echo "Repository path must be absolute: $dir" >&2
        exit 1
    }
    case "$repo" in
        web-demo) manifest="$dir/wasm/Cargo.toml" ;;
        cli|tui|linux-gtk|e2e) manifest="$dir/Cargo.toml" ;;
        *) echo "Unsupported Core consumer: $repo" >&2; exit 1 ;;
    esac
    manifest_dir=$(dirname "$manifest")
    if [[ -e "$dir/.cargo/config.toml" || -e "$dir/.cargo/config" \
       || -e "$manifest_dir/.cargo/config.toml" || -e "$manifest_dir/.cargo/config" ]]; then
        echo "Refusing to ignore repository-local Cargo config for $repo" >&2
        exit 1
    fi
    scratch=$(mktemp -d /tmp/vauchi-refresh-core-lock.XXXXXX)
    trap 'rm -rf "$scratch"' EXIT
    (cd "$scratch" && cargo update --manifest-path "$manifest" -p vauchi-core -p vauchi-app)

# Check binding/artifact UniFFI ABI parity (Layer 2 gate).
# Plan: _private/docs/planning/todo/2026-04-20-frontend-correctness-strategy-plan.md Task 2.1.
#
# Usage: just check-binding-abi android | just check-binding-abi ios
#
# Checks the freshly-built pair in `core/target/bindings/` — same
# pair CI's `check:binding-abi-*` validates and `_dt-package-*`
# runs. Run after `just bindings` / `just rebuild-{android,ios}`.
# The previous version pointed at the local-dev mirrors under
# `android/app/src/...` and `ios/Vauchi/Generated/` which are
# populated by a separate copy step; those can drift when only
# `just bindings` runs, producing false-positive pass/fail.
[group('daily')]
[script]
check-binding-abi platform:
    set -euo pipefail
    WORKSPACE_ROOT="$(pwd)"
    case "{{ platform }}" in
        android)
            "$WORKSPACE_ROOT/scripts/scripts/check-binding-abi.sh" \
                --platform android \
                --artifact "$WORKSPACE_ROOT/core/target/aarch64-linux-android/release/libvauchi_platform.so" \
                --bindings "$WORKSPACE_ROOT/core/target/bindings/android/kotlin/uniffi/vauchi_platform/vauchi_platform.kt"
            ;;
        ios)
            "$WORKSPACE_ROOT/scripts/scripts/check-binding-abi.sh" \
                --platform ios \
                --artifact "$WORKSPACE_ROOT/core/target/aarch64-apple-ios/release/libvauchi_platform.a" \
                --bindings "$WORKSPACE_ROOT/core/target/bindings/ios/generated/vauchi_platform.swift"
            ;;
        *) echo "usage: just check-binding-abi {android|ios}" >&2; exit 2 ;;
    esac

# Run Layer 1 ScreenModel reachability tests (core, test-support feature).
# Plan: _private/docs/planning/todo/2026-04-20-frontend-correctness-strategy-plan.md Task 1.4.
#
# Two CC-22 gates run before the test suite (closes audit R-4 / F4):
#   (1) every `impl WorkflowEngine` has a matching
#       `tests/reachability/<snake>.rs` or sits on
#       `tests/reachability/.coverage-baseline`
#   (2) every baseline entry has NO matching test (the list ratchets
#       down only — landing a test forces removal in the same MR)
[group('daily')]
[script]
reachability:
    set -euo pipefail
    ./scripts/scripts/check-reachability-coverage.sh
    if command -v cargo-nextest &>/dev/null; then
        (cd core && cargo nextest run --manifest-path vauchi-app/Cargo.toml --test reachability --features vauchi-app/test-support)
    else
        (cd core && cargo test --manifest-path vauchi-app/Cargo.toml --test reachability --features vauchi-app/test-support)
    fi

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
    repos=$(resolve_repo "${_QR_REPO:-}" "fmt")
    for r in $repos; do
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
    repos=$(resolve_repo "${_QR_REPO:-}" "fmt")
    for r in $repos; do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        if ! quiet_enabled; then echo "═══ fmt-check: $r ($tc) ═══"; fi
        _do_step() {
            case "$tc" in
                rust)    (cd "$dir" && cargo fmt --all -- --check 2>&1) ;;
                npm)     (cd "$dir" && npx prettier --check src/ 2>&1) ;;
                xcode)   (cd "$dir" && swiftformat --lint . 2>&1) ;;
                *)       echo "No format-check runner for $tc" >&2; return 1 ;;
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
    repos=$(resolve_repo "${_QR_REPO:-}" "lint")
    for r in $repos; do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        if ! quiet_enabled; then echo "═══ lint: $r ($tc) ═══"; fi
        _do_step() {
            case "$tc" in
                rust)
                    # Every checker below carries `|| return 1`: run_step calls
                    # this function in a `||` context, which disables `set -e`
                    # inside it, so a bare failing command is not fatal and the
                    # arm's status becomes whatever its last statement returns.
                    # A trailing repo-conditional then reports 0 and the failure
                    # is lost. Guarded by tests/test_lint_recipe_reports_failure.py.
                    (cd "$dir" && cargo clippy --workspace --all-targets -- -D warnings 2>&1) || return 1
                    # Pure-functional-core seal (program Phase 1): vauchi-core
                    # state machines own NO ambient time/rng/sleep. Hard-fail
                    # if any core_* counter regresses above 0. Runs from the
                    # workspace root (the audit scans core/vauchi-core/src and
                    # already exempts the seam files + tests + diagnostic
                    # perf-timers). core-only; other Rust repos skip it.
                    if [[ "$r" == "core" ]]; then
                        scripts/scripts/audit-mobile-surface.sh --check-core-purity 2>&1 || return 1
                        # VRS03: mirror of CI lint:no-default-features —
                        # the no-default build prunes feature-gated paths
                        # and surfaces dead code the default `just check`
                        # never compiles (this class previously appeared
                        # only after push). Page:
                        # _private/docs/lint-errors/vrs03-no-default-features.md
                        (cd "$dir" && RUSTFLAGS="-D warnings" cargo check -p vauchi-app --no-default-features 2>&1) || return 1
                    fi
                    ;;
                npm)     (cd "$dir" && npm run lint 2>&1 && npm run lint:css 2>&1) ;;
                gradle)
                    # `|| return 1` on every checker — see the rust arm above.
                    (cd "$dir" && ./gradlew lint 2>&1) || return 1
                    # §1A pure-renderer guard — fences view-layer
                    # `.isImported` reads. Only meaningful for the
                    # `android` repo (scope: app/src/main/kotlin/app/vauchi/ui/).
                    if [[ "$r" == "android" ]]; then
                        scripts/scripts/check-no-isimported-in-views.sh "$(pwd)" 2>&1 || return 1
                        # G5 lint guard — fences view-layer reads of
                        # isVerified / isRecoveryTrusted / isHidden /
                        # reciprocity / trustLevel / isFailed. Pairs with
                        # G1–G4 typed view-state APIs.
                        scripts/scripts/check-no-domain-conditionals-in-views.sh "$(pwd)" 2>&1 || return 1
                        # Clipboard protection — fences view-layer
                        # direct setPrimaryClip(). Routes must go
                        # through ClipboardUtils.copy{,WithAutoClear}.
                        scripts/scripts/check-no-direct-clipboard-writes.sh "$(pwd)" 2>&1 || return 1
                        # Phase 1 of 2026-05-01-android-humble-ui-deep-retirement.
                        # --strict (enforcing): Phase 4.6 closed 2026-06-08
                        # after the MainViewModel diet (1,881 -> 537 LOC).
                        # Fences new Mobile* imports + identity/biometric
                        # branches in views; allowlist covers coreui/,
                        # MainViewModel.kt, MainActivity.kt, theme/Theme.kt.
                        scripts/scripts/check-no-domain-imports-in-views.sh "$(pwd)" --strict 2>&1 || return 1
                    fi
                    ;;
                xcode)
                    # `|| return 1` on every checker — see the rust arm above.
                    (cd "$dir" && swiftlint lint --strict --quiet 2>&1 && swiftformat --lint . 2>&1) || return 1
                    # §1A pure-renderer guard — fences view-layer
                    # `.isImported` reads. Only meaningful for the
                    # `ios` repo (scope: ios/Vauchi/Views/). macOS / other
                    # xcode repos don't carry the duplication.
                    if [[ "$r" == "ios" ]]; then
                        scripts/scripts/check-no-isimported-in-views.sh "$(pwd)" 2>&1 || return 1
                        # G5 lint guard — see android arm above.
                        scripts/scripts/check-no-domain-conditionals-in-views.sh "$(pwd)" 2>&1 || return 1
                        # Clipboard protection — fences view-layer
                        # direct UIPasteboard.general writes. Routes
                        # must go through ContactActions.copyToClipboard.
                        scripts/scripts/check-no-direct-clipboard-writes.sh "$(pwd)" 2>&1 || return 1
                    fi
                    # Humble UI ratchet — fences any new domain-named
                    # view files in Vauchi/Views/ outside the per-repo
                    # allow-list. Drives the iOS / macOS retirement
                    # records (2026-05-02-{ios,macos}-humble-ui-{deep-,}retirement).
                    if [[ "$r" == "ios" || "$r" == "macos" ]]; then
                        scripts/scripts/check-domain-named-views.sh "$dir" 2>&1 || return 1
                    fi
                    # Humble UI G3/G4 ratchet — caps the count of
                    # hardcoded `Text("Foo")` literals at the per-repo
                    # `.text-literal-baseline` integer. Each retirement
                    # / localisation MR ratchets the number down. iOS
                    # scope is `Vauchi/Views/`; macOS extends to
                    # `Vauchi/CoreUI/` and `Vauchi/VauchiApp.swift`
                    # (matches the audit grep).
                    if [[ "$r" == "ios" ]]; then
                        scripts/scripts/check-text-literal-count.sh \
                            "$dir" Vauchi/Views/ 2>&1 || return 1
                    fi
                    if [[ "$r" == "macos" ]]; then
                        scripts/scripts/check-text-literal-count.sh \
                            "$dir" Vauchi/Views/ Vauchi/CoreUI/ \
                            Vauchi/VauchiApp.swift 2>&1 || return 1
                    fi
                    ;;
                mdbook)  (cd "$dir" && markdownlint '**/*.md' 2>&1) ;;
                python)
                    if [[ -f "$dir/scripts/validate.py" ]]; then
                        (cd "$dir" && python3 scripts/validate.py 2>&1)
                    fi
                    ;;
                gherkin) echo "  (gherkin lint: advisory only)"; return 0 ;;
                shell)   (cd "$dir" && shellcheck scripts/*.sh 2>&1 \
                            && bash scripts/check-seeded-violation-tests.sh 2>&1) ;;
                html)    (cd "$dir" && htmlhint public/**/*.html 2>&1) ;;
                *)       echo "No lint runner for $tc" >&2; return 1 ;;
            esac
        }
        run_step "$r" _do_step
    done
    print_summary "lint" || exit 1
    # Humble-UI source ratchets (Lever 3 enforcement keystone, ADR-043 Am4 §4
    # / ADR-044 Am1 §3). These audits scan BOTH android/ and ios/ source in a
    # single pass, so they live at the workspace level — not the per-repo loop
    # above — and run only on a full-workspace lint (`just lint` with no repo
    # arg, which `just check` invokes). Ratchet semantics: counts may DROP as
    # retirement lands, never RISE; baselines locked at 0. Detectors are
    # self-tested in scripts/scripts/tests/audit-{frontend-vocab,dispatch-purity}.test.sh
    # (non-tautological per CC-20/CC-21). Safe where a frontend tree is absent
    # (e.g. single-repo CI): counts fall to 0 ≤ baseline and pass — fail-on-rise
    # only fires in the workspace where both trees coexist. Plan:
    # _private/docs/planning/todo/2026-05-26-humble-ui-vocab-fast-path-plan.md (L3.1/L3.2).
    if [ -z "${_QR_REPO:-}" ]; then
        if ! quiet_enabled; then echo "═══ lint: humble-ui source ratchets (workspace) ═══"; fi
        scripts/scripts/audit-frontend-vocab.sh --check scripts/scripts/audit-frontend-vocab.baseline.json
        scripts/scripts/audit-dispatch-purity.sh --check scripts/scripts/audit-dispatch-purity.baseline.json
        scripts/scripts/audit-app-preferences.sh --check scripts/scripts/audit-app-preferences.baseline.json
        # Humble-UI domain-mutation ratchet for the Rust/C++/C# frontends
        # (tui, cli, linux-gtk, linux-qt, windows) — the analogue of
        # audit-frontend-vocab.sh's mobile (Swift/Kotlin) coverage. Closes
        # the ungated-scope gap from 2026-06-02-humble-ui-enforcement-mobile-only:
        # counts domain-mutating verb calls (save_/configure_/setup_/validate_)
        # + vauchi_core::types:: construction; baseline may DROP, never RISE.
        scripts/scripts/audit-frontend-domain-calls.sh --check scripts/scripts/audit-frontend-domain-calls.baseline.json
        # Hardcoded-English ratchet over core's ScreenModel builders
        # (M3 S2 of 2026-07-03-core-screens-bypass-i18n, design D3.4):
        # counts string literals in title:/label:/hint:/placeholder:/
        # subtitle:/detail:/content: positions of production
        # core/vauchi-app/src/ui code. The i18n threading slices burn
        # the baseline down; it may DROP, never RISE.
        scripts/scripts/audit-ui-literals.sh --check scripts/scripts/audit-ui-literals.baseline.json
        # Hardcoded-English ratchet over the remaining frontends that do not
        # have a dedicated i18n string lint (Android Kotlin, Windows XAML,
        # linux-qt C++, linux-gtk Rust, TUI Rust, CLI Rust). Core and the
        # SwiftUI frontends are covered by audit-ui-literals.sh and
        # check-text-literal-count.sh respectively. The baseline may DROP as
        # strings are routed through locales; it may never RISE.
        scripts/scripts/audit-frontend-i18n-strings.sh --check scripts/scripts/audit-frontend-i18n-strings.baseline.json
        # Shell-surface ratchet (2026-07-18 planning-coherence audit):
        # frontend Mobile* type refs (iOS/Android/macOS) + hardware-executor
        # domain vocabulary — the residual "frontends are shells" debt now
        # that mobile_pub_fns is 0. Baseline may DROP, never RISE.
        scripts/scripts/audit-shell-surface.sh --check scripts/scripts/audit-shell-surface.baseline.json
        # Frontend handwritten-LOC budget — "less code is better":
        # per-frontend LOC may DROP as logic moves to core, never RISE.
        scripts/scripts/loc-budget.sh --check scripts/scripts/loc-budget.baseline.json
    fi

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

# Wait for GitLab CI pipeline on the current branch
# Usage: just ci-wait           (uses repo inferred from cwd)
#        just ci-wait core      (wait for vauchi/core pipeline)
[group('daily')]
[no-cd]
ci-wait repo='':
    just gitlab pipeline-wait "{{ repo }}"

# ═══════════════════════════════════════════════════════════════════
# EXTENDED COMMANDS - Less frequently used
# ═══════════════════════════════════════════════════════════════════

# Run tests for specific crate (within core workspace)
[group('extended')]
test-crate crate:
    cd core && cargo test -p {{crate}} --features vauchi-core/testing

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
                echo "── $r: ./gradlew testDebugUnitTest --tests *{{ name }}* ──"
                (cd "$dir" && ./gradlew testDebugUnitTest --tests "*{{ name }}*" 2>&1) || true
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
test-name pattern repo='core' package='' target='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    repos=$(resolve_repo "{{ repo }}" "test")
    # Every repo runs even after one fails, and the recipe still exits
    # non-zero; `|| true` here used to report failing tests as a pass (#590).
    failed=""
    # cargo exits 0 when the filter matches nothing, so a misspelled or
    # renamed test passed as green (#996); count what actually ran.
    cargo_ran=""
    ran=0
    log=$(mktemp)
    trap 'rm -f "$log"' EXIT
    for r in $repos; do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        tfeats=$(repo_test_features "$r")
        case "$tc" in
            rust)
                # --no-fail-fast: a failing test binary must not hide the
                # matching tests in the others (#590).
                scope=()
                [[ -z "{{ package }}" ]] || scope+=(-p "{{ package }}")
                case "{{ target }}" in
                    '') ;;
                    lib) scope+=(--lib) ;;
                    *) scope+=(--test "{{ target }}") ;;
                esac
                echo "── $r: cargo test --no-fail-fast ${scope[*]} {{ pattern }} $tfeats ──"
                (cd "$dir" && cargo test --no-fail-fast "${scope[@]}" $tfeats "{{ pattern }}" 2>&1) | tee "$log" || failed="$failed $r"
                cargo_ran=1
                ran=$((ran + $(sed -nE 's/^running ([0-9]+) tests?$/\1/p' "$log" | awk '{ n += $1 } END { print n + 0 }')))
                ;;
            npm)
                echo "── $r: npx vitest -t '{{ pattern }}' ──"
                (cd "$dir" && npx vitest run -t "{{ pattern }}" 2>&1) || failed="$failed $r"
                ;;
            gradle)
                echo "── $r: ./gradlew testDebugUnitTest --tests *{{ pattern }}* ──"
                (cd "$dir" && ./gradlew testDebugUnitTest --tests "*{{ pattern }}*" 2>&1) || failed="$failed $r"
                ;;
            *)
                echo "── $r: test-name not supported for $tc ──"
                ;;
        esac
    done
    for r in $failed; do
        echo "test-name: $r failed" >&2
    done
    if [[ -n "$cargo_ran" && "$ran" -eq 0 ]]; then
        echo "test-name: no test matched '{{ pattern }}'" >&2
        exit 1
    fi
    [[ -z "$failed" ]]

# Build release binaries
[group('extended')]
build-release:
    cd core && cargo build --workspace --release

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

# Bump core workspace version and regenerate Cargo.lock.
# Usage: just bump-core <version>   e.g. just bump-core 0.19.9
[group('core')]
[script]
bump-core version:
    # Ordering: every step that EDITS the manifest happens before the
    # first step that can FAIL, so a failed bump leaves Cargo.toml and
    # Cargo.lock in a consistent partial state.
    set -euo pipefail
    if [ -z "{{ version }}" ]; then
        echo "Usage: just bump-core <version>"
        exit 1
    fi
    echo "Bumping core workspace to {{ version }}..."
    cd core
    # 1. [workspace.package].version (top-level `version = "X.Y.Z"`).
    sed -i.bak 's/^version = ".*"/version = "{{ version }}"/' Cargo.toml && rm Cargo.toml.bak
    # 2. [workspace.dependencies] hardcoded version refs for the
    #    intra-workspace crates. Each line looks like:
    #      vauchi-core = { path = "vauchi-core", version = "0.X.Y", ... }
    #    Cargo refuses to resolve a path-member at a stale published
    #    version if the constraint excludes the new workspace version,
    #    so these stay in lockstep.
    for crate in vauchi-core vauchi-app vauchi-protocol; do
        sed -i.bak "s|^\\($crate = { path = \"$crate\", version = \"\\)[^\"]*\\(\".*\\)|\\1{{ version }}\\2|" Cargo.toml && rm Cargo.toml.bak
    done
    # 3. Minimal lockfile update restricted to the 5 workspace crates.
    #    `cargo generate-lockfile` (the old recipe's call) regenerates
    #    from scratch and pulls newest compatible versions of every
    #    transitive dep — 44-line Cargo.lock churn vs the convention's
    #    10 lines. `cargo update -p` touches only the named packages.
    cargo update -p vauchi-core -p vauchi-app -p vauchi-cabi -p vauchi-platform -p vauchi-protocol 2>&1 | tail -10
    echo "Regenerating cargo-vet exemptions..."
    cargo vet regenerate exemptions 2>&1
    cargo vet fmt 2>&1
    echo "✓ Core bumped to {{ version }}. Review changes and commit."

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
    just release-gates
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
    # Include origin tags even when the local clone has not fetched them.
    TAGS=$({
        git -C core tag -l "v${BASE}*" 2>/dev/null
        git -C core ls-remote --tags --refs origin "refs/tags/v${BASE}*" 2>/dev/null \
            | awk '{sub("^refs/tags/", "", $2); print $2}'
    } | sort -Vu)
    if [[ -z "$TAGS" ]]; then
        echo "  No tags for v${BASE}"
    else
        echo "$TAGS" | while read -r tag; do
            DATE=$(git -C core log -1 --format=%ci "$tag" 2>/dev/null | cut -d' ' -f1 || true)
            if echo "$tag" | grep -q "dev"; then
                CLASS="dev"
            elif echo "$tag" | grep -q "rc"; then
                CLASS="RC"
            else
                CLASS="PROD"
            fi
            if [[ -n "$DATE" ]]; then
                echo "  $tag  ($DATE)  [$CLASS]"
            else
                echo "  $tag  [$CLASS]"
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
        DIST_TAGS=$(git -C "${dist_repo}" ls-remote --tags --refs origin \
            "refs/tags/v${BASE}*" 2>/dev/null \
            | awk '{sub("^refs/tags/", "", $2); print $2}' \
            | sort -Vu)
        if [[ -n "$DIST_TAGS" ]]; then
            echo "  Published tags: $(echo "$DIST_TAGS" | paste -sd, -)"
        else
            echo "  No published tags for v${BASE}"
        fi
        if command -v glab &>/dev/null && glab auth status &>/dev/null 2>&1; then
            MRS=$(glab mr list -R "vauchi/${dist_repo}" --all \
                --search "${BASE}" --per-page 5 -F json 2>/dev/null \
                | jq -r '.[] | "!\(.iid) [\(.state)] \(.title) — \(.web_url)"' \
                || true)
            if [[ -n "$MRS" ]]; then
                echo "  Matching MRs:"
                echo "$MRS" | sed 's/^/    /'
            else
                echo "  No matching MRs for v${BASE}"
            fi
            LATEST=$(glab ci list -R "vauchi/${dist_repo}" --per-page 1 \
                -F json 2>/dev/null \
                | jq -r '.[0] | select(.) | "#\(.id) [\(.status)] ref=\(.ref) \(.web_url)"' \
                || true)
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
            MRS=$(glab mr list -R "vauchi/${app_repo}" --all \
                --search "${BASE}" --per-page 5 -F json 2>/dev/null \
                | jq -r '.[] | "!\(.iid) [\(.state)] \(.title) — \(.web_url)"' \
                || true)
            if [[ -n "$MRS" ]]; then
                echo "  Matching MRs:"
                echo "$MRS" | sed 's/^/    /'
            else
                echo "  No matching MRs for v${BASE}"
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
    failed=0
    for r in $repos; do
        dir=$(repo_dir "$r")
        echo "═══ audit: $r ═══"
        if ! (cd "$dir" && cargo audit 2>&1); then
            echo "ERROR: cargo audit failed for $r" >&2
            failed=1
        fi
        if ! (cd "$dir" && cargo deny check 2>&1); then
            echo "ERROR: cargo deny check failed for $r" >&2
            failed=1
        fi
    done
    exit "$failed"

# Regenerate cargo-vet exemptions to match each repo's CI strategy.
# Repos with custom CI scripts (cli, tui, relay): regenerate lockfile without path overrides.
# Repos using the shared template (core, ohttp-relay): vet against committed lockfile (--locked).
# Usage: just vet-fix [repo]   e.g. just vet-fix cli
[group('extended')]
[script]
vet-fix repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    VET_REPOS="cli tui relay ohttp-relay core"
    # Repos whose CI uses `cargo vet --locked` (shared template, no lockfile regeneration)
    LOCKED_REPOS="core ohttp-relay"
    if [[ -n "{{repo}}" ]]; then
        VET_REPOS="{{repo}}"
    fi
    for r in $VET_REPOS; do
        dir=$(repo_dir "$r")
        echo "═══ vet-fix: $r ═══"
        config="$dir/.cargo/config.toml"
        had_config=false
        if [[ -f "$config" ]]; then
            had_config=true
            mv "$config" "$config.bak"
        fi
        is_locked=false
        for lr in $LOCKED_REPOS; do [[ "$r" == "$lr" ]] && is_locked=true; done
        (
            cd "$dir"
            if $is_locked; then
                echo "  (--locked mode: vetting committed lockfile)"
                cargo generate-lockfile 2>&1 | tail -3
                cargo vet regenerate exemptions 2>&1
                cargo vet fmt 2>&1
                cargo vet --locked 2>&1 && echo "✓ $r passed" || echo "✗ $r failed"
            else
                echo "  (regenerate mode: fresh lockfile without path overrides)"
                cargo generate-lockfile 2>&1 | tail -3
                cargo vet regenerate exemptions 2>&1
                cargo vet fmt 2>&1
                cargo vet 2>&1 && echo "✓ $r passed" || echo "✗ $r failed"
            fi
        )
        if $had_config; then
            mv "$config.bak" "$config"
        fi
        echo ""
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
watch:
    cd core && cargo watch -x "test --workspace"

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
                    (cd "$dir" && cargo llvm-cov --workspace --html --ignore-run-fail $tfeats 2>&1)
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

# Diff-scoped mutation testing — on-demand signal on changed code only.
# Runs cargo-mutants against just the lines changed vs origin/main
# (committed + uncommitted), per Rust repo. Deliberately NOT a push or
# commit gate: each mutant reruns the suite, so it costs minutes even on a
# small diff — that conflicts with fast push/commit feedback. Full-crate
# mutation runs nightly in CI (see core/ci/mutation-and-fuzz.yml). Picks up
# each repo's .cargo/mutants.toml automatically. Extra args after the repo
# forward to cargo-mutants. Exits non-zero if any mutant survives or errors.
# Usage: `just mutants-diff` (all changed Rust repos) | `just mutants-diff core`
[group('extended')]
[script]
mutants-diff *args:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    # core mutants load themes/locales at runtime (see CI before_script).
    [ -d themes ]  && export VAUCHI_THEMES_DIR="$(cd themes && pwd)"
    [ -d locales ] && export VAUCHI_LOCALES_DIR="$(cd locales && pwd)"
    # jobs: min(8, ncpu) — cargo-mutants warns that >8 overloads the box.
    # MUTANTS_JOBS lowers it: each job copies the tree (~2.5 GB for core).
    JOBS=${MUTANTS_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}
    [ "$JOBS" -gt 8 ] && JOBS=8
    set -- {{ args }}
    repo_arg="${1:-all}"; [ "$#" -gt 0 ] && shift || true
    ran=0; failed=0
    for r in $(resolve_repo "$repo_arg" "test"); do
        [ "$(repo_toolchain "$r")" = "rust" ] || continue
        dir=$(repo_dir "$r")
        # Diff from the merge-base, not origin/main directly: a branch behind
        # origin/main would otherwise see upstream-only files as "changed"
        # (two-dot diff is bidirectional). merge-base = this branch's work
        # plus uncommitted edits, nothing upstream.
        base=$(git -C "$dir" merge-base origin/main HEAD 2>/dev/null || echo origin/main)
        diff_file=$(mktemp)
        git -C "$dir" diff "$base" -- '*.rs' > "$diff_file" 2>/dev/null || true
        if [ ! -s "$diff_file" ]; then
            rm -f "$diff_file"
            continue
        fi
        ran=1
        echo "═══ mutants-diff: $r (changed Rust since branch point) ═══"
        (cd "$dir" && cargo mutants --in-diff "$diff_file" --jobs "$JOBS" "$@") || failed=1
        rm -f "$diff_file"
    done
    [ "$ran" = 1 ] || echo "No changed Rust files since branch point in any targeted repo — nothing to mutate."
    [ "$failed" = 0 ] || { echo "mutants-diff: surviving mutants or errors above (exit 1)"; exit 1; }

# Diff-scoped tests — fast changed-code feedback per toolchain. Runs only the
# repos whose tracked files changed vs origin/main, using each ecosystem's
# "changed files" mode where one exists. Skips repos you didn't touch and
# defers tests that need a foreign host (Windows/Linux/Apple) or a slow
# simulator — those run in CI. NOT a push/commit gate; invoke on demand.
# Usage: `just test-diff` (all changed repos) | `just test-diff web-demo`
[group('extended')]
[script]
test-diff *args:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    OS="$(uname -s)"
    set -- {{ args }}
    repo_arg="${1:-all}"
    ran=0; failed=0
    for r in $(resolve_repo "$repo_arg" "test"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        # merge-base, not origin/main: avoids flagging upstream-only files
        # when the branch is behind origin/main (same fix as mutants-diff).
        base=$(git -C "$dir" merge-base origin/main HEAD 2>/dev/null || echo origin/main)
        changed=$(git -C "$dir" diff --name-only "$base" 2>/dev/null || true)
        [ -n "$changed" ] || continue
        case "$tc" in
            rust)
                # .rs only — Cargo.toml/Cargo.lock are dirtied locally by
                # setup-path-overrides (known false positive). NOTE: nextest has
                # no changed-files mode, so this runs the repo's WHOLE suite —
                # scoped to repos you touched, not to changed lines.
                echo "$changed" | grep -qE '\.rs$' || continue
                if [ "$r" = "linux-gtk" ] && [ "$OS" != "Linux" ]; then
                    echo "═══ test-diff: $r — Linux-only deps; tests run in CI ═══"; continue
                fi
                ran=1
                tfeats=$(repo_test_features "$r")
                echo "═══ test-diff: $r (cargo nextest — whole repo suite) ═══"
                if command -v cargo-nextest >/dev/null 2>&1; then
                    (cd "$dir" && cargo nextest run $tfeats) || failed=1
                else
                    (cd "$dir" && cargo test $tfeats) || failed=1
                fi
                ;;
            npm)
                echo "$changed" | grep -qE '\.(ts|tsx|js|jsx|mjs|cjs|vue|svelte)$' || continue
                ran=1
                echo "═══ test-diff: $r (vitest --changed since branch point) ═══"
                (cd "$dir" && npx vitest run --changed "$base") || failed=1
                ;;
            gradle)
                echo "$changed" | grep -qE '\.(kt|kts|java)$' || continue
                ran=1
                # Use local UniFFI bindings only when FRESH — a stale
                # gitignored stub (older than the current version pin)
                # compiles against an outdated surface and yields a
                # misleading failure; fall back to the Maven AAR (CI's
                # source) instead. Mirrors gate-push.sh's staleness guard.
                GRADLE_ARGS=""
                _stub="$dir/app/src/local-bindings/kotlin/uniffi/vauchi_platform/vauchi_platform.kt"
                if [ -f "$_stub" ]; then
                    _sm=$(stat -f %m "$_stub" 2>/dev/null || stat -c %Y "$_stub" 2>/dev/null || echo 0)
                    _pm=$(git -C "$dir" log -1 --format=%ct -- app/build.gradle.kts 2>/dev/null || echo 0)
                    if [ "$_sm" -gt 0 ] && [ "$_sm" -ge "$_pm" ]; then
                        GRADLE_ARGS="-PlocalBindings"
                    else
                        echo "  (local bindings look stale vs the pin — using Maven AAR; 'just bindings-local' to refresh)"
                    fi
                fi
                echo "═══ test-diff: $r (gradle testDebugUnitTest) ═══"
                (cd "$dir" && ./gradlew $GRADLE_ARGS testDebugUnitTest) || failed=1
                ;;
            xcode)
                echo "$changed" | grep -qE '\.swift$' || continue
                # iOS sim launch is the latency floor and macOS unit tests
                # can't run locally (testmanagerd) — both run in CI. swiftlint
                # on these files is your fast local signal (gate-push runs it).
                echo "═══ test-diff: $r — Apple unit tests deferred to CI; swiftlint is the fast local check ═══"
                ;;
            dotnet)
                echo "$changed" | grep -qE '\.cs$' || continue
                echo "═══ test-diff: $r — WinUI build needs Windows; tests run in CI ═══"
                ;;
            cmake)
                echo "$changed" | grep -qE '\.(cpp|cc|cxx|h|hpp|py)$' || continue
                if [ "$OS" = "Linux" ] && [ -d "$dir/build" ]; then
                    ran=1
                    echo "═══ test-diff: $r (ctest) ═══"
                    (cd "$dir/build" && ctest --output-on-failure) || failed=1
                else
                    echo "═══ test-diff: $r — Qt/C++ needs Linux + configured build/; tests run in CI ═══"
                fi
                ;;
            *)
                continue
                ;;
        esac
    done
    [ "$ran" = 1 ] || echo "No locally-runnable changed tests since branch point in any targeted repo."
    [ "$failed" = 0 ] || { echo "test-diff: failures above (exit 1)"; exit 1; }

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
docs:
    cd core && cargo doc --workspace --no-deps --open

# Install git hooks (pre-commit + pre-push) across all repos
[group('extended')]
install-hooks:
    bash scripts/install-hooks.sh

# Usage: just socratic-review [repo] [codex|kimi|both]
#   just socratic-review core           # both reviewers
#   just socratic-review _private kimi  # one reviewer
#
# Codex and Kimi interrogate `origin/main...HEAD` and return questions
# only — no patches, no verdict. Provider diversity is the point: a
# Claude session reviewing its own diff with Claude agrees with itself.
# Advisory, not a gate.
#
# Socratic review of the current branch by Codex + Kimi (advisory)
[group('tools')]
[no-cd]
[script]
socratic-review repo='' reviewer='both':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    dir=$(repo_dir "{{repo}}")
    bash scripts/scripts/socratic-review.sh "$dir" "{{reviewer}}"

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

# Forbid `allow_direct: true` overrides outside the documented allow-list
# (ADR-037 privacy regression — see
# `_private/docs/problems/2026-04-17-ohttp-allow-direct-fallback/`).
[group('tools')]
[script]
check-no-allow-direct:
    set -euo pipefail
    scripts/scripts/check-no-allow-direct.sh core cli tui e2e

# Forbid view-layer reads of MobileContact.is_imported / .isImported.
# Core's ContactDetailEngine + vauchi-platform 0.24.0's
# `contact_detail_footer_action_id(contact_id)` own the choice; views
# dispatch on the returned action id instead. §1A pure-renderer rule —
# `_private/docs/problems/2026-04-25-isimported-frontend-cleanup/`.
# Scope: ios/Vauchi/Views/ + android/app/src/main/kotlin/app/vauchi/ui/.
# Pattern: `\.isImported\b` (member access only — initializer labels
# in struct/data-class constructors and #Preview fixtures are exempt).
[group('tools')]
[script]
lint-no-isimported-in-views:
    set -euo pipefail
    scripts/scripts/check-no-isimported-in-views.sh "$(pwd)"

# Forbid view-layer direct writes to the system clipboard. Routes
# must go through the per-frontend helper:
# - iOS:     ContactActions.copyToClipboard(_:)
# - Android: ClipboardUtils.copy{,WithAutoClear}(...)
# Reference + threat model:
# `_private/docs/reference/2026-05-02-clipboard-protection.md`.
# Scope: ios/Vauchi/Views/, ios/Vauchi/CoreUI/,
# android/app/src/main/kotlin/app/vauchi/ui/.
[group('tools')]
[script]
lint-no-direct-clipboard-writes:
    set -euo pipefail
    scripts/scripts/check-no-direct-clipboard-writes.sh "$(pwd)"

# Verify every hand-rolled frontend ScreenModel parser
# (linux-gtk, linux-qt, windows, android) covers every Component
# variant declared in core/vauchi-app/src/ui/component.rs. iOS / macOS
# come from UniFFI and are sync-by-construction.
# `_private/docs/problems/2026-05-01-screenmodel-parser-symmetry-gate/`.
[group('tools')]
[script]
lint-parser-parity:
    set -euo pipefail
    python3 scripts/scripts/check-component-parser-parity.py --protocol presentation

# G5 (ScreenModel API gaps): forbid view-layer reads of MobileContact /
# MobileDeliveryRecord domain conditionals that should be decided in
# core. Pairs with the G1–G4 typed view-state APIs (visible_fields,
# label_contacts, getFailedDeliveryRecords, contactDetailViewState).
# Scope: ios/Vauchi/Views/, ios/Vauchi/CoreUI/,
# android/app/src/main/kotlin/app/vauchi/ui/. Patterns: member-access
# `.isVerified` / `.isRecoveryTrusted` / `.isHidden` / `.isFailed`,
# equality comparisons against `.reciprocity` and `.trustLevel`.
# `_private/docs/problems/2026-04-27-screenmodel-api-gaps-symmetric-frontend-violations/`.
[group('tools')]
[script]
lint-no-domain-conditionals-in-views:
    set -euo pipefail
    scripts/scripts/check-no-domain-conditionals-in-views.sh "$(pwd)"

# Phase 1 of 2026-05-01-android-humble-ui-deep-retirement. Forbid
# Mobile* imports and identity/biometric conditionals in the Android
# view layer. Default warn-only; pass `--strict` to fail CI. Allowlist:
# coreui/, MainViewModel.kt, MainActivity.kt. Flips to default-strict
# at Phase 4.6 closeout.
[group('tools')]
[script]
lint-no-domain-imports-in-views *args:
    set -euo pipefail
    scripts/scripts/check-no-domain-imports-in-views.sh "$(pwd)" {{args}}

# Frontend-source domain-vocabulary deny-list (ADR-043 Am4 / ADR-044
# Am1). Ratchets navigate-by-domain-name string literals in handwritten
# Swift/Kotlin (e.g. navigateTo("ContactDetail")) against a committed
# baseline; fails if any count rises. Companion to
# lint-no-domain-imports-in-views: that fences Mobile* imports, this
# fences nav-target domain strings. Run with no args for the ratchet
# check; pass an empty arg to emit raw JSON counts.
[group('tools')]
[script]
lint-frontend-vocab *args:
    set -euo pipefail
    if [ -z "{{args}}" ]; then
        scripts/scripts/audit-frontend-vocab.sh --check scripts/scripts/audit-frontend-vocab.baseline.json
    else
        scripts/scripts/audit-frontend-vocab.sh {{args}}
    fi

# Dispatch-wrapper purity gate (L3.2): ratchets impurity signals
# (collection transforms, formatters, statement branching) in the two
# frontend dispatch-extension files. Enforces ADR-043 Am3 §2's
# conditional sanction of dispatch_domain_command. Run with no args for
# the ratchet check; pass an empty arg to emit raw JSON counts.
[group('tools')]
[script]
lint-dispatch-purity *args:
    set -euo pipefail
    if [ -z "{{args}}" ]; then
        scripts/scripts/audit-dispatch-purity.sh --check scripts/scripts/audit-dispatch-purity.baseline.json
    else
        scripts/scripts/audit-dispatch-purity.sh {{args}}
    fi

# Deprecation-window lint (settings-storage S5): fails if a NEW frontend
# caller of the deprecated `Vauchi::app_preferences*` surface reappears
# between S4 (migration complete) and S6 (core surface deletion).
# Ratchets per-frontend caller counts against a committed baseline (0);
# counts may drop, never rise. Run with no args for the ratchet check;
# pass an empty arg to emit raw JSON counts.
[group('tools')]
[script]
lint-app-preferences *args:
    set -euo pipefail
    if [ -z "{{args}}" ]; then
        scripts/scripts/audit-app-preferences.sh --check scripts/scripts/audit-app-preferences.baseline.json
    else
        scripts/scripts/audit-app-preferences.sh {{args}}
    fi

# Count caller sites for a method on a frontend repo, with the corrected
# pattern that excludes Kotlin/Swift extension-method **declaration**
# signatures (which silently inflated the Phase 4a Android audit's
# caller counts and masked ~1040 LOC of orphan code — see
# `_private/docs/investigations/measurements/2026-05-03-android-mainviewmodel-orphan-audit.md`).
#
# Usage:
#   just orphan-callers android tryTriggerAhaMoment
#   just orphan-callers ios     tryTriggerAhaMoment
#
# Output: one line per caller site, plus a header reporting the count
# and an explicit "ORPHAN" verdict at zero. Exit code 0 always (this is
# a measurement, not a gate).
[group('tools')]
[script]
orphan-callers repo method:
    set -euo pipefail
    case "{{repo}}" in
        android)
            roots="android/app/src/main android/app/src/test android/app/src/androidTest android/app/src/screenshotTest"
            ext_filter='--include=*.kt'
            # ViewModel-mediated callers only — excludes the
            # PlatformAppEngineDomainDispatch.kt extension declarations.
            # `\b` rejects substring matches: `viewModel.sync` must not
            # match `viewModel.syncState`.
            pattern='viewModel\.{{method}}\b\|coreAppViewModel\.{{method}}\b\|mainViewModel\.{{method}}\b'
            ;;
        ios)
            roots="ios/Vauchi ios/VauchiTests ios/VauchiSnapshotTests ios/VauchiUITests"
            ext_filter='--include=*.swift'
            pattern='viewModel\.{{method}}\b\|appViewModel\.{{method}}\b\|coreAppViewModel\.{{method}}\b'
            ;;
        *)
            echo "Usage: just orphan-callers (android|ios) <method>"
            exit 2
            ;;
    esac
    # Note the deliberately omitted `\.{{method}}(` form: it would
    # match `func PlatformAppEngine.{{method}}(...)` extension
    # declarations and break the audit (see referenced note).
    matches=$(grep -rn "$pattern" $roots $ext_filter 2>/dev/null \
                | grep -v "Generated/\|local-bindings/" || true)
    count=$(printf '%s\n' "$matches" | grep -c . || true)
    if [[ "$count" == "0" ]]; then
        printf "ORPHAN: 0 view-layer callers of %s in %s.\n" "{{method}}" "{{repo}}"
    else
        printf "%d view-layer caller site(s) of %s in %s:\n" "$count" "{{method}}" "{{repo}}"
        printf '%s\n' "$matches"
    fi

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
                   linux-hw apple-hw android-hw windows-hw

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
      just gitlab test-report <id> [repo]   Failed tests + assertion messages
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

    Workspace slots (parallel sessions — one full workspace clone each):
      just slot status        Show every slot, its holder, repos off main/dirty
      just slot acquire       Hold this slot (session-init does this)
      just slot release       Release this slot (session-end does this)
      (include root to nest the other repos in it, as in the workspace)

    Device rig (phones shared by every slot; one holder per phone):
      just rig status                 Who holds each phone, last hand-over notes
      just rig claim [phones] [note]  Hold phones while this session runs
                                      (default: the exchange pair pixel,iphone)
      just rig install-wrappers       adb/ios/maestro wrappers that honour it
      just rig check [phones]         Exit 1 if another session holds them (scripts)
      just rig release [phones] [note]  Release them, noting build, identity,
                                      permissions, and whether you reinstalled

    Agent harnesses:
      just harness codex [args]  Start Codex with its own claim session id
      just harness kimi [args]   Start Kimi with its own claim session id

    Apps:
      just run <platform>     Run app (cli|tui|relay|android|ios)
      just relay              Start relay server
      just tui                Run TUI

    Deploy:
      just deploy-latest <svc> Mint a fresh CI deploy button (relay|landing|docs|ohttp-relay)
      just deploy-check       Check deployed versions vs origin/main
      just core-freshness     Check if bindings/consumers are up to date with core
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
      just setup-completion [bash|zsh]  Install shell completions
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

    # 12. Stale problem records (14d intake, 30d other phases)
    # Uses git last-modified date (not directory creation date) for accuracy.
    # A record updated yesterday is not stale even if created months ago.
    section "Stale problem records"
    stale_problems=0
    now_epoch=$(date +%s)
    for dir in _private/docs/problems/*/; do
        [[ ! -f "${dir}README.md" ]] && continue
        dirname=$(basename "$dir")
        [[ "$dirname" == "done" ]] && continue
        # Extract status from first 50 lines using sed. Extended regex
        # (`-nE`) is required: BSD sed (macOS) treats `\?` as a literal
        # `?`, so the basic-regex form left every record classified as
        # "unknown" and the threshold check unguarded. head -50 covers
        # records whose **Status** table cell sits below a long preamble
        # (e.g. the 2026-02-15-e2e-proximity-simulation record at line 22).
        # The `(\*\*)?Status(\*\*)?` group catches both the bold-table
        # form (`| **Status** | intake |`) and the markdown-heading form
        # (`## Status: intake`) used by some 2026-04-27 records.
        status=$(head -50 "${dir}README.md" | sed -nE 's/.*(\*\*)?Status(\*\*)?[[:space:]]*[|:][[:space:]]*`?([a-zA-Z]*).*/\3/p' | head -1 || true)
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

    # 13. Linked worktrees — parallel sessions use slots (`just slot status`)
    section "Linked worktrees"
    source just/slot-lib.sh
    stray_worktrees=$(slot_linked_worktrees .)
    if [[ -n "$stray_worktrees" ]]; then
        printf '%s\n' "$stray_worktrees" | sed 's/^/    /'
        echo "  -> Merge their work, then: git -C <repo> worktree remove <path>"
        ISSUES=$((ISSUES + $(printf '%s\n' "$stray_worktrees" | wc -l | tr -d ' ')))
    else
        echo "  None"
    fi

    # 14. Orphaned test temp dirs (vauchi-core tests leak TempDir on SIGKILL)
    section "Orphaned test temp dirs"
    # Only count .tmp* dirs containing vauchi.db (test databases), skip others
    # find /tmp exits 1 on foreign-user EPERM entries even with stderr
    # nulled — guard it or pipefail aborts the whole recipe here.
    test_tmp_count=$( (find /tmp -maxdepth 2 -user "$(whoami)" -name 'vauchi.db' -path '/tmp/.tmp*' 2>/dev/null || true) | wc -l | tr -d ' ')
    tmp_total=$( (find /tmp -maxdepth 1 -user "$(whoami)" -name '.tmp*' -type d 2>/dev/null || true) | wc -l | tr -d ' ')
    if [[ "$test_tmp_count" -gt 0 ]]; then
        # Only clean dirs with no open file handles (safe)
        stale=$( (find /tmp -maxdepth 2 -user "$(whoami)" -name 'vauchi.db' -path '/tmp/.tmp*' -mmin +5 2>/dev/null || true) | wc -l | tr -d ' ')
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

    # 15. Cargo target sizes
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

    # 16. Cargo.toml ref check (branch = "main")
    section "Cargo.toml branch refs"
    ref_output=$(just check-refs 2>&1 || true)
    if echo "$ref_output" | grep -q "not pointing to main"; then
        echo "$ref_output" | grep "not pointing to main" | sed 's/^/  /'
        bad_refs=$(echo "$ref_output" | grep -c "not pointing to main" || true)
        ISSUES=$((ISSUES + bad_refs))
    else
        echo "  All refs point to main"
    fi

    # 17. Just recipe documentation freshness
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
        # Skip generated/vendor dirs. --hidden includes dotfiles
        # (.gitlab-ci.yml, .github/, .cargo/config.toml, .dockerignore, …)
        # which rg otherwise skips by default. The explicit !.git/ glob
        # keeps git's own metadata out.
        results=$(rg "{{ pattern }}" "$dir" \
            --hidden --no-heading --color=never \
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

# Fix Cargo.lock entries missing `source = "git+..."` after path-override
# contamination. Scopes to one repo. Re-resolves vauchi-* deps cleanly by
# moving .cargo/config.toml aside, resetting Cargo.lock from origin/main,
# running cargo update, then restoring config.toml.
#
# Usage: just fix-lockfile-sources <repo>
[group('tools')]
[no-cd]
[script]
fix-lockfile-sources repo:
    set -euo pipefail
    dir="{{repo}}"
    if [[ ! -f "$dir/Cargo.lock" ]]; then
        echo "  Skipping $dir: no Cargo.lock"
        exit 0
    fi
    if [[ ! -f "$dir/Cargo.toml" ]]; then
        echo "  Skipping $dir: no Cargo.toml"
        exit 0
    fi
    # Find git dependencies in Cargo.toml
    deps=$(awk '
        /^\[/ { in_dep = /^\[(dependencies|dev-dependencies|build-dependencies|workspace\.dependencies)\]/ }
        in_dep && /^[a-zA-Z0-9_-]+ *=.*[^a-zA-Z_]git *=/ { print $1 }
    ' "$dir/Cargo.toml" | sort -u)
    if [[ -z "$deps" ]]; then
        echo "  No git dependencies in $dir/Cargo.toml — nothing to fix"
        exit 0
    fi
    echo "═══ fix-lockfile-sources: $dir ═══"
    # Move path-override config aside (if present)
    config="$dir/.cargo/config.toml"
    moved=0
    if [[ -f "$config" ]]; then
        mv "$config" "$config.bak"
        moved=1
    fi
    # Reset Cargo.lock to origin/main so we start from a known-good state
    if git -C "$dir" show origin/main:Cargo.lock > /tmp/cargo-lock-main.$$ 2>/dev/null; then
        cp /tmp/cargo-lock-main.$$ "$dir/Cargo.lock"
        rm -f /tmp/cargo-lock-main.$$
    fi
    # Run cargo update per dep (ignore failures — some deps may already be correct)
    update_args=""
    for dep in $deps; do
        update_args="$update_args -p $dep"
    done
    echo "  cargo update$update_args"
    (cd "$dir" && cargo update $update_args 2>&1 | tail -10) || true
    # Restore config.toml
    if [[ $moved -eq 1 ]]; then
        mv "$config.bak" "$config"
    fi
    echo ""
    echo "  Verify: git -C $dir diff Cargo.lock"
    echo "  Commit: git -C $dir add Cargo.lock && git -C $dir commit --amend --no-edit"

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
# Delegates to scripts/check-claude-md.sh so CI and local runs share
# exactly one implementation. Portable to BusyBox (alpine CI).
# Usage: just check-claude-md
[group('tools')]
[no-cd]
check-claude-md:
    ./scripts/scripts/check-claude-md.sh

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

# Every @implemented scenario needs a test annotated with its name
# (vauchi/private#268). Reads the local checkouts, which may be on branches;
# features' lint:implemented-scenarios checks every repo's main.
# Usage: just check-implemented-scenarios [--strict]
[group('tools')]
[no-cd]
check-implemented-scenarios *args:
    python3 scripts/scripts/check-implemented-scenarios.py --features features \
        --baseline features/implemented-untested.baseline \
        --dangling-baseline features/dangling-annotations.baseline {{ args }} \
        core cli tui e2e relay ohttp-relay linux-gtk linux-qt windows web-demo ios macos android

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
    prev=""
    while IFS= read -r line; do
        recipe=$(echo "$line" | sed 's/^[[:space:]]*//' | cut -d' ' -f1)
        [[ -z "$recipe" ]] && continue
        [[ "$recipe" =~ ^\[ ]] && continue     # skip [group] headers
        [[ "$recipe" == "Available" ]] && continue
        # A doc comment is documentation: `just --list` shows it, so
        # just-commands.md stays the curated agent reference instead of an
        # exhaustive, context-loaded index of every recipe. For a long
        # signature, `just --list` prints the comment on the line above.
        if [[ "$line" == *"#"* || "$prev" =~ ^[[:space:]]*# ]]; then
            prev="$line"; continue
        fi
        prev="$line"
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
#
# Covers all in-tree consumers: the binding crates inside core/ (vauchi-app,
# vauchi-cabi, vauchi-platform), every Rust frontend, every native frontend
# (macos/ios/android Swift+Kotlin, windows C#, linux-gtk Rust, linux-qt C++),
# and web-demo/drift-detector (TypeScript). The list is broad on purpose —
# missing a consumer is what made the 2026-05-08 deep-modules audit drop
# linux-qt entirely. See .claude/docs/audit-scope.md.
[group('tools')]
[no-cd]
[script]
consumers pattern:
    set -uo pipefail
    echo "Searching for '{{ pattern }}' across in-tree consumers..."
    echo ""
    CONSUMER_DIRS=(
        core/vauchi-app core/vauchi-cabi core/vauchi-platform
        cli tui e2e relay
        linux-gtk linux-qt windows macos ios android
        web-demo drift-detector
    )
    for dir in "${CONSUMER_DIRS[@]}"; do
        [[ ! -d "$dir" ]] && continue
        label="$dir"
        results=$(rg "{{ pattern }}" "$dir" \
            --glob '*.rs' --glob '*.ts' --glob '*.tsx' \
            --glob '*.swift' --glob '*.kt' \
            --glob '*.cpp' --glob '*.h' --glob '*.hpp' \
            --glob '*.cs' \
            --glob '!target/' --glob '!build/' --glob '!.gradle/' \
            --glob '!node_modules/' --glob '!dist/' --glob '!.next/' \
            -n --color=never 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            count=$(echo "$results" | wc -l | tr -d ' ')
            echo "── $label ($count matches) ──"
            echo "$results"
            echo ""
        fi
    done

# Snapshot the public API surface of each core crate (deterministic, diffable).
# Usage: just public-api              # all crates + per-subsystem breakdown
#        just public-api vauchi-core  # one crate, full pub item listing
#
# Use this output (not narrative prose) as the anchor for any "deep vs.
# shallow" claim. If cargo-public-api is installed it produces
# authoritative output; otherwise it falls back to a grep snapshot.
# See .claude/docs/audit-scope.md for the audit coverage manifest.
[group('tools')]
[no-cd]
[script]
public-api crate="all":
    set -uo pipefail
    bash scripts/scripts/check-public-api.sh "{{ crate }}"

# ═══════════════════════════════════════════════════════════════════
# DOCUMENTATION LINTING
# ═══════════════════════════════════════════════════════════════════

# Regression check for repository scoping in lint-docs.
[group('tests')]
test-lint-docs:
    python3 "{{justfile_directory()}}/tests/test_lint_docs_recipe.py" "{{justfile_directory()}}/just/lint-docs.sh"

# Regression check: a tool on PATH that cannot run is not present.
[group('tests')]
test-check-prerequisites:
    python3 "{{justfile_directory()}}/tests/test_check_prerequisites.py" "{{justfile_directory()}}/just/check-prerequisites.sh"

# Regression check: a failing linter must fail the recipe, not just print.
[group('tests')]
test-check-recipe:
    python3 "{{justfile_directory()}}/tests/test_check_recipe_fail_closed.py"

# Configure, build and run registered native tests with sccache.
[group('daily')]
[script]
cmake-check *args:
    set -euo pipefail
    source scripts/scripts/quiet-runner.sh
    source scripts/scripts/resolve-repo.sh
    _qr_parse_args {{args}}
    repo=${_QR_REPO:-linux-qt}
    [[ "$(repo_toolchain "$repo")" == cmake ]] || { echo "Not a CMake repository: $repo" >&2; exit 1; }
    run_step "$repo" bash scripts/scripts/cmake-check.sh "$(repo_dir "$repo")"
    print_summary "CMake/CTest" || exit 1

# Regression check: a failing linter must fail the recipe, not just print.
[group('tests')]
test-lint-recipe:
    python3 "{{justfile_directory()}}/tests/test_lint_recipe_reports_failure.py" "{{justfile_directory()}}/justfile"

# Verify MR publication preserves normal push hooks.
[group('tests')]
test-mr-create-recipe:
    python3 tests/test_gitlab_mr_create_recipe.py

# Regression check: failing tests fail `test-name`, and every target runs.
[group('tests')]
test-test-name-recipe:
    python3 "{{justfile_directory()}}/tests/test_test_name_recipe.py" "{{justfile_directory()}}/justfile"

# Regression check: lint-ci-needs fails on a VCI06 finding and names the project.
[group('tests')]
test-lint-ci-needs-recipe:
    python3 "{{justfile_directory()}}/tests/test_lint_ci_needs_recipe.py" "{{justfile_directory()}}/justfile"

# VCI06: a hard needs: on a job a merge-request diff can skip rejects the
# whole pipeline. Sweeps each project's resolved main config (CI lint API).
# Usage: just lint-ci-needs [project...]   (default: every vauchi project)
[group('tools')]
[script]
lint-ci-needs *projects:
    set -euo pipefail
    checker="${VCI06_CHECKER:-{{justfile_directory()}}/scripts/scripts/check-ci-needs-rules.py}"
    # uv only when PyYAML is missing and uv exists; otherwise the checker
    # itself names a missing yaml module.
    run=(python3)
    if ! python3 -c 'import yaml' 2>/dev/null && command -v uv >/dev/null 2>&1; then
        run=(uv run -q --with pyyaml python3)
    fi
    projects="{{ projects }}"
    [ -n "$projects" ] || projects=$(glab api "groups/vauchi/projects?per_page=100&archived=false" | jq -r '.[].path')
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    failed=0
    for p in $projects; do
        if ! glab api "projects/vauchi%2F$p/ci/lint?content_ref=main&dry_run=false" > "$tmp/$p.json" 2>/dev/null; then
            echo "  $p: no resolved CI config (lint API refused)"
            continue
        fi
        jq -r '.merged_yaml // ""' "$tmp/$p.json" > "$tmp/$p.yml"
        if [ ! -s "$tmp/$p.yml" ]; then
            echo "  $p: no CI config"
            continue
        fi
        "${run[@]}" "$checker" "$tmp/$p.yml" | sed "s#$tmp/$p.yml#$p#" || failed=1
    done
    [ "$failed" -eq 0 ]

# Lint documentation: naming convention, broken links, license text
[group('tools')]
lint-docs:
    bash "{{justfile_directory()}}/just/lint-docs.sh"

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
    RULE_ARGS=(-r "$RULE")
    # gate-push.sh also loads VDC01; without it this recipe passed files the
    # push gate then refused (vauchi/private#417).
    ABS_RULE="scripts/ci-templates/markdownlint-rule-no-abs-paths.js"
    [ -f "$ABS_RULE" ] && RULE_ARGS+=(-r "$ABS_RULE")
    WS_ROOT="$(pwd)"
    ARGS="{{ ARGS }}"
    FIX=""
    PATHS=()
    for arg in $ARGS; do
      if [ "$arg" = "fix" ]; then
        FIX="--fix"
      else
        PATHS+=("$arg")
      fi
    done
    if [ ${#PATHS[@]} -eq 0 ]; then
      PATHS=("_private/docs/")
    fi
    # Resolve the markdownlint config for a path by finding its owning
    # repo root (nearest ancestor with a .git) and applying that repo's
    # config. Precedence mirrors scripts/hooks/pre-push so this recipe and
    # the push gate never disagree: repo-local > _private > workspace root.
    resolve_config() {
      local p="$1" dir root
      if [ -d "$p" ]; then dir="$p"; else dir="$(dirname "$p")"; fi
      dir="$(cd "$dir" 2>/dev/null && pwd || echo "$WS_ROOT")"
      root="$dir"
      while [ "$root" != "/" ]; do
        [ -e "$root/.git" ] && break
        root="$(dirname "$root")"
      done
      if [ -f "$root/.markdownlint.json" ]; then echo "$root/.markdownlint.json"; return; fi
      if [ -f "$root/.markdownlint.jsonc" ]; then echo "$root/.markdownlint.jsonc"; return; fi
      if [ -f "$WS_ROOT/_private/.markdownlint.json" ]; then echo "$WS_ROOT/_private/.markdownlint.json"; return; fi
      if [ -f "$WS_ROOT/.markdownlint.json" ]; then echo "$WS_ROOT/.markdownlint.json"; return; fi
      echo ""
    }
    echo "═══ Markdown lint (per-repo config, backtick-path exempt) ═══"
    [ -n "$FIX" ] && echo "  Mode: auto-fix"
    rc=0
    for p in "${PATHS[@]}"; do
      cfg="$(resolve_config "$p")"
      CONFIG=""
      [ -n "$cfg" ] && CONFIG="-c $cfg"
      echo "  $p  →  config: ${cfg:-(markdownlint default)}"
      if [ -n "$FIX" ]; then
        # Custom rules may need multiple fix passes to reach a stable state
        # (one wrap can create another over-long continuation line).
        pass=0
        while [ "$pass" -lt 5 ]; do
          pass=$((pass + 1))
          # shellcheck disable=SC2086
          if markdownlint $CONFIG "${RULE_ARGS[@]}" $FIX "$p" >/dev/null 2>&1; then
            break
          fi
        done
        # shellcheck disable=SC2086
        markdownlint $CONFIG "${RULE_ARGS[@]}" "$p" || rc=1
      else
        # shellcheck disable=SC2086
        markdownlint $CONFIG "${RULE_ARGS[@]}" $FIX "$p" || rc=1
      fi
    done
    if [ "$rc" -eq 0 ]; then
      echo "All markdown checks passed."
    else
      echo "FAILED: markdownlint found issues. Run 'just lint-markdown fix' to auto-fix."
      exit 1
    fi

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

# Verify literal i18n keys referenced in source exist in en.json.
# Catches typos in `get_string("foo.bar")` at MR time instead of
# the runtime fallback `Missing: <key>` at
# Audit inbound markdown links for record graduations in the push range.
#
# When a problem record moves between `_private/docs/problems/X/` and
# `_private/docs/problems/done/X/`, peer records that linked to the OLD
# path become broken. CI's `lint:links` job catches it, but only on the
# merge ref — after push. This recipe runs the same audit locally.
#
# Origin record:
#   `_private/docs/problems/2026-05-10-record-graduation-link-audit/`
#
# Exit codes:
#   0 — clean, or no graduations in range
#   1 — broken inbound links found
#   2 — script error (bad upstream ref, no docs tree)
#
# Usage:
#   just lint-graduation-links                # vs origin/main
#   just lint-graduation-links origin/develop # vs custom upstream
[group('tools')]
lint-graduation-links upstream='origin/main':
    bash _private/docs/scripts/audit-graduation-links.sh {{ upstream }}

# core/vauchi-app/src/i18n.rs:134. CI runs the same check via
# `lint:locale-key-coverage` in core/.gitlab-ci.yml.
#
# Variable-key call sites (`get_string(locale, &computed_key)`)
# are statically unreachable and not validated here — covered by
# test discipline + runtime fallback.
#
# Usage:
#   just lint-locale-keys                          # core/vauchi-app/src, rust
#   just lint-locale-keys core/vauchi-app/src rust # explicit
#   just lint-locale-keys ios/Vauchi swift         # frontend (Phase 4)
[group('tools')]
lint-locale-keys repo='core/vauchi-app/src' language='rust':
    bash locales/scripts/check-locale-key-coverage.sh \
        --language {{ language }} \
        --locales-dir locales \
        {{ repo }}

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
    # Self-heal: ensure dependencies and native modules match current Node ABI.
    # Without this, a Node upgrade silently breaks `just drift` (audit finding F3,
    # 2026-04-17): better-sqlite3's prebuilt .node file is ABI-versioned.
    # The check must instantiate a Database: the native binding loads lazily,
    # so a bare require() passes even when the .node file is missing (seen
    # 2026-07-24 when npm 12 allowScripts blocked the install script).
    if [[ ! -d node_modules ]]; then
        echo "Installing drift-detector dependencies..."
        npm install --silent
    elif ! node -e 'new (require("better-sqlite3"))(":memory:").close()' 2>/dev/null; then
        echo "Rebuilding drift-detector native modules (Node ABI mismatch)..."
        npm rebuild better-sqlite3 --silent
    fi
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
    # Self-heal: see comment in `drift` recipe above.
    if [[ ! -d node_modules ]]; then
        echo "Installing drift-detector dependencies..."
        npm install --silent
    elif ! node -e 'new (require("better-sqlite3"))(":memory:").close()' 2>/dev/null; then
        echo "Rebuilding drift-detector native modules (Node ABI mismatch)..."
        npm rebuild better-sqlite3 --silent
    fi
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

# Build/refresh the local semantic search index (Ollama embeddings, no API
# tokens). Incremental — re-embeds only changed files. Run once, then again
# after large changes. Index lives in .cache/semsearch.db (gitignored).
[group('tools')]
semindex root='.':
    python3 scripts/scripts/semsearch.py index {{root}}

# Semantic code search — "find code related to X" (e.g.
# just semsearch "daily rotating mailbox tokens"). Prefer over an Explore
# agent for locating code; grep still wins for exact strings. Append --code
# to exclude markdown docs (ADRs/plans) when you want only code. Optional
# trailing number caps results (default 8).
[group('tools')]
[positional-arguments]
semsearch *query:
    python3 scripts/scripts/semsearch.py query "$@"

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
