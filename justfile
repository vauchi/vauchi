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

# GitLab base URL
gitlab_base := "git@gitlab.com:vauchi"

# Public repositories (mirrored to GitHub)
public_repos := "gitlab-profile scripts assets core relay cli tui desktop e2e features android ios docs locales themes website vauchi-mobile-swift vauchi-mobile-android"

# Private repository (consolidated, cloned as _private)
private_repo := "private"

# Tooling repositories (url,dir format, outside vauchi group)
tooling_repos := "git@gitlab.com:megloff1/drift-detector.git,drift-detector git@gitlab.com:megloff1/markdown-plan.git,markdown-plan"

# ─── Aliases ─────────────────────────────────────────────────────

alias b := build
alias t := test
alias c := check
alias f := fmt

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

# ═══════════════════════════════════════════════════════════════════
# DAILY COMMANDS - Use these regularly
# ═══════════════════════════════════════════════════════════════════

# Run all checks: format-check → lint → test
[group('daily')]
[script('bash')]
check *args:
    set -euo pipefail
    source scripts/scripts/quiet-runner.sh
    _qr_parse_args {{args}}
    if quiet_enabled; then
        _QR_TOTAL_START=$SECONDS
        export _QR_SHARED_DIR
        _QR_SHARED_DIR=$(mktemp -d)
        trap 'rm -rf "$_QR_SHARED_DIR"' EXIT
        just fmt-check ${_QR_REPO:-} --quiet || true
        just lint ${_QR_REPO:-} --quiet || true
        just test ${_QR_REPO:-} --quiet || true
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
[script('bash')]
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
                xcode)   (cd "$dir" && xcodebuild -scheme Vauchi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build -quiet 2>&1) ;;
                mkdocs)  (cd "$dir" && mkdocs build --strict 2>&1) ;;
                *)       echo "  (no build step for $tc)"; return 0 ;;
            esac
        }
        run_step "$r" _do_step
    done
    print_summary "build" || exit 1

# Run tests
[group('daily')]
[script('bash')]
test *args:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/quiet-runner.sh
    _qr_parse_args {{args}}
    for r in $(resolve_repo "${_QR_REPO:-}" "test"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        if ! quiet_enabled; then echo "═══ test: $r ($tc) ═══"; fi
        _do_step() {
            case "$tc" in
                rust)
                    if command -v cargo-nextest &>/dev/null; then
                        (cd "$dir" && cargo nextest run --workspace 2>&1)
                    else
                        (cd "$dir" && cargo test --workspace 2>&1)
                    fi
                    ;;
                npm)     (cd "$dir" && npx playwright test --project=chromium --grep-invert "@visual|@a11y" 2>&1) ;;
                gradle)  (cd "$dir" && ./gradlew test 2>&1) ;;
                xcode)   (cd "$dir" && xcodebuild -scheme Vauchi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -quiet 2>&1) ;;
                mkdocs)  (cd "$dir" && mkdocs build --strict 2>&1) ;;
                *)       echo "  (no test step for $tc)"; return 0 ;;
            esac
        }
        run_step "$r" _do_step
    done
    print_summary "test" || exit 1

# Format code
[group('daily')]
[script('bash')]
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
[script('bash')]
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
[script('bash')]
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
[script('bash')]
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
    echo "=== $label ==="
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
    cargo test -p {{crate}}

# Run a single test file by name
# Usage: just test-file identity_test           (searches core/)
#        just test-file exchange_test relay      (searches relay/)
[group('extended')]
[no-cd]
[script('bash')]
test-file name repo='core':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    repos=$(resolve_repo "{{ repo }}" "test")
    for r in $repos; do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        case "$tc" in
            rust)
                echo "=== $r: cargo test --test {{ name }} ==="
                (cd "$dir" && cargo test --test "{{ name }}" 2>&1) || true
                ;;
            npm)
                echo "=== $r: npx vitest {{ name }} ==="
                (cd "$dir" && npx vitest run "{{ name }}" 2>&1) || true
                ;;
            gradle)
                echo "=== $r: ./gradlew test --tests *{{ name }}* ==="
                (cd "$dir" && ./gradlew test --tests "*{{ name }}*" 2>&1) || true
                ;;
            *)
                echo "=== $r: test-file not supported for $tc ==="
                ;;
        esac
    done

# Run tests matching a name pattern
# Usage: just test-name exchange_round_trip          (searches core/)
#        just test-name relay_failover e2e           (searches e2e/)
[group('extended')]
[no-cd]
[script('bash')]
test-name pattern repo='core':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    repos=$(resolve_repo "{{ repo }}" "test")
    for r in $repos; do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        case "$tc" in
            rust)
                echo "=== $r: cargo test {{ pattern }} ==="
                (cd "$dir" && cargo test "{{ pattern }}" 2>&1) || true
                ;;
            npm)
                echo "=== $r: npx vitest -t '{{ pattern }}' ==="
                (cd "$dir" && npx vitest run -t "{{ pattern }}" 2>&1) || true
                ;;
            gradle)
                echo "=== $r: ./gradlew test --tests *{{ pattern }}* ==="
                (cd "$dir" && ./gradlew test --tests "*{{ pattern }}*" 2>&1) || true
                ;;
            *)
                echo "=== $r: test-name not supported for $tc ==="
                ;;
        esac
    done

# Build release binaries
[group('extended')]
[working-directory('core')]
build-release:
    cargo build --workspace --release

# Create a dev tag for fast CI feedback (lint + test only)
# Usage: just release-dev [version]
# If no version given, reads from core/Cargo.toml and increments dev counter
[group('extended')]
[script('bash')]
release-dev version="":
    set -euo pipefail
    if [[ -n "{{ version }}" ]]; then
        TAG="v{{ version }}"
    else
        BASE=$(grep -A5 '^\[workspace\.package\]' core/Cargo.toml | grep '^version' | sed 's/.*"\(.*\)"/\1/')
        BASE=$(echo "$BASE" | sed 's/-.*//')
        LAST=$(git -C core tag -l "v${BASE}-dev.*" | sort -V | tail -1 || true)
        if [[ -n "$LAST" ]]; then
            N=$(echo "$LAST" | grep -oE '[0-9]+$')
            N=$((N + 1))
        else
            N=1
        fi
        TAG="v${BASE}-dev.${N}"
    fi
    echo "Creating dev tag: $TAG"
    echo "  This will trigger a lightweight pipeline (lint + test only)"
    echo ""
    BRANCH=$(git -C core rev-parse --abbrev-ref HEAD)
    if [[ "$BRANCH" != "main" ]]; then
        echo "ERROR: Must be on main branch (currently on $BRANCH)"
        exit 1
    fi
    git -C core tag -a "$TAG" -m "Dev release $TAG"
    git -C core push origin "$TAG"
    echo "Created and pushed $TAG"
    echo "  Pipeline: https://gitlab.com/vauchi/core/-/pipelines"

# Create an RC tag for full quality gate (coverage, mutation, bench)
# Usage: just release-rc [version]
[group('extended')]
[script('bash')]
release-rc version="":
    set -euo pipefail
    if [[ -n "{{ version }}" ]]; then
        TAG="v{{ version }}"
    else
        BASE=$(grep -A5 '^\[workspace\.package\]' core/Cargo.toml | grep '^version' | sed 's/.*"\(.*\)"/\1/')
        BASE=$(echo "$BASE" | sed 's/-.*//')
        LAST=$(git -C core tag -l "v${BASE}-rc.*" | sort -V | tail -1 || true)
        if [[ -n "$LAST" ]]; then
            N=$(echo "$LAST" | grep -oE '[0-9]+$')
            N=$((N + 1))
        else
            N=1
        fi
        TAG="v${BASE}-rc.${N}"
    fi
    echo "Creating RC tag: $TAG"
    echo "  This will trigger a full quality gate (coverage, mutation, bench, security)"
    echo "  NO publish, deploy, or mobile binding trigger"
    echo ""
    BRANCH=$(git -C core rev-parse --abbrev-ref HEAD)
    if [[ "$BRANCH" != "main" ]]; then
        echo "ERROR: Must be on main branch (currently on $BRANCH)"
        exit 1
    fi
    git -C core tag -a "$TAG" -m "Release candidate $TAG"
    git -C core push origin "$TAG"
    echo "Created and pushed $TAG"
    echo "  Pipeline: https://gitlab.com/vauchi/core/-/pipelines"

# Create a PROD release tag (full pipeline + publish + deploy + mobile triggers)
# Usage: just release-prod
# Reads version from core/Cargo.toml — must be a clean version (no -dev/-rc suffix)
[group('extended')]
[script('bash')]
release-prod:
    set -euo pipefail
    VERSION=$(grep -A5 '^\[workspace\.package\]' core/Cargo.toml | grep '^version' | sed 's/.*"\(.*\)"/\1/')
    if echo "$VERSION" | grep -qE '-(dev|rc)\.'; then
        echo "ERROR: Cargo.toml has pre-release version $VERSION"
        echo "  Update Cargo.toml to a clean version (e.g., 0.2.3) before PROD release"
        exit 1
    fi
    TAG="v${VERSION}"
    echo "Creating PROD tag: $TAG"
    echo "  This will trigger the FULL release pipeline:"
    echo "    - Build + test + coverage + mutation"
    echo "    - Package iOS/Android bindings"
    echo "    - Publish to GitLab package registry"
    echo "    - Create GitLab release"
    echo "    - Trigger mobile binding repos -> iOS/Android apps"
    echo ""
    echo "  Promotion chain for this version:"
    git -C core tag -l "v${VERSION}*" 2>/dev/null | sort -V | sed 's/^/    /' || true
    echo "    $TAG  <- YOU ARE HERE"
    echo ""
    read -p "Proceed? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 1
    fi
    BRANCH=$(git -C core rev-parse --abbrev-ref HEAD)
    if [[ "$BRANCH" != "main" ]]; then
        echo "ERROR: Must be on main branch (currently on $BRANCH)"
        exit 1
    fi
    git -C core tag -a "$TAG" -m "Release $TAG"
    git -C core push origin "$TAG"
    echo "Created and pushed $TAG"

# Show version promotion history for a given base version
[group('extended')]
[script('bash')]
release-history version="":
    set -euo pipefail
    if [[ -n "{{ version }}" ]]; then
        BASE="{{ version }}"
    else
        BASE=$(grep -A5 '^\[workspace\.package\]' core/Cargo.toml | grep '^version' | sed 's/.*"\(.*\)"/\1/' | sed 's/-.*//')
    fi
    echo "Version promotion history for v${BASE}:"
    echo ""
    git -C core tag -l "v${BASE}*" | sort -V | while read -r tag; do
        DATE=$(git -C core log -1 --format=%ci "$tag" 2>/dev/null | cut -d' ' -f1)
        if echo "$tag" | grep -q "dev"; then
            echo "  $tag  ($DATE)  [dev]"
        elif echo "$tag" | grep -q "rc"; then
            echo "  $tag  ($DATE)  [RC]"
        else
            echo "  $tag  ($DATE)  [PROD]"
        fi
    done

# Run security audit
[group('extended')]
[script('bash')]
audit repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    # Only Rust repos support cargo audit
    RUST_REPOS="core cli relay tui e2e desktop-rust"
    if [[ -z "{{repo}}" ]]; then
        repos="$RUST_REPOS"
    elif [[ "{{repo}}" == "all" ]]; then
        repos="$RUST_REPOS"
    elif [[ "{{repo}}" == "desktop" ]]; then
        repos="desktop-rust"
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
[script('bash')]
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
[script('bash')]
coverage *args:
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/quiet-runner.sh
    _qr_parse_args {{args}}
    for r in $(resolve_repo "${_QR_REPO:-}" "coverage"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        echo "═══ coverage: $r ($tc) ═══"
        _do_step() {
            case "$tc" in
                rust)
                    (cd "$dir" && cargo llvm-cov --workspace --html 2>&1)
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
                        -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
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
[script('bash')]
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

# Show quick reference
[group('tools')]
[script('bash')]
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
      Examples: just test core, just lint cli, just check desktop
      Valid repos: core cli relay tui e2e desktop android ios docs
                   locales themes features website scripts

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
      just git main           Stash → checkout main → pull (interactive)
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
      just run <platform>     Run app (cli|tui|desktop|relay|android|ios)
      just relay              Start relay server
      just tui                Run TUI

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
      just release-dev        Create dev tag (fast pipeline)
      just release-rc         Create RC tag (full quality gate)
      just release-prod       Create PROD tag (full release)
      just release-history    Show version promotion chain

    Setup:
      just setup              Clone all repos, init workspace
      just install-dev-deps   Install toolchain (Homebrew + Cargo)
      just clean              Clean all build artifacts

    Tools:
      just grep <pattern> [glob]  Search across all repos
      just concept <name>     Search by drift concept + aliases
      just consumers <pattern> Find downstream usage of core API
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

# Run all non-destructive health checks and print a summary
[group('daily')]
[script('bash')]
housekeeping:
    set -uo pipefail
    ISSUES=0
    SECTION=0

    section() {
        SECTION=$((SECTION + 1))
        echo ""
        echo "═══ [$SECTION] $1 ═══"
    }

    # 1. Uncommitted changes & untracked files
    section "Uncommitted changes"
    dirty=0
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            label="vauchi (root)"
            gitdir="."
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"
            gitdir="${dir%/}"
        fi
        status=$(git -C "$gitdir" status --porcelain 2>/dev/null || true)
        if [[ -n "$status" ]]; then
            modified=$(echo "$status" | grep -c '^ M\|^M \|^MM' || true)
            untracked=$(echo "$status" | grep -c '^??' || true)
            parts=()
            [[ "$modified" -gt 0 ]] && parts+=("$modified modified")
            [[ "$untracked" -gt 0 ]] && parts+=("$untracked untracked")
            detail=$(IFS=', '; echo "${parts[*]}")
            echo "  $label: $detail"
            dirty=$((dirty + modified + untracked))
        fi
    done
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
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            label="vauchi (root)"
            gitdir="."
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"
            gitdir="${dir%/}"
        fi
        stash_count=$(git -C "$gitdir" stash list 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$stash_count" -gt 0 ]]; then
            echo "  $label: $stash_count stash(es)"
            git -C "$gitdir" stash list 2>/dev/null | head -3 | sed 's/^/    /'
            [[ "$stash_count" -gt 3 ]] && echo "    ... and $((stash_count - 3)) more"
            stash_total=$((stash_total + stash_count))
        fi
    done
    if [[ "$stash_total" -eq 0 ]]; then
        echo "  None"
    else
        ISSUES=$((ISSUES + stash_total))
    fi

    # 4. Leftover WIP commits
    section "WIP commits (unsaved work)"
    wip_count=0
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            label="vauchi (root)"
            gitdir="."
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"
            gitdir="${dir%/}"
        fi
        head_msg=$(git -C "$gitdir" log -1 --format=%s 2>/dev/null || true)
        if [[ "$head_msg" == wip:* ]]; then
            branch=$(git -C "$gitdir" branch --show-current 2>/dev/null || echo "detached")
            echo "  $label ($branch): $head_msg"
            wip_count=$((wip_count + 1))
        fi
    done
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
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            label="vauchi (root)"
            gitdir="."
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"
            gitdir="${dir%/}"
        fi
        branches=$(git -C "$gitdir" branch --no-color 2>/dev/null | grep -v '^\* ' | grep -v 'main$' | sed 's/^[[:space:]]*//' || true)
        if [[ -n "$branches" ]]; then
            while IFS= read -r br; do
                [[ -z "$br" ]] && continue
                last_epoch=$(git -C "$gitdir" log -1 --format=%ct "$br" 2>/dev/null || echo "$now_epoch")
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
    done
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

    # 9. Drift (high severity only, quick)
    section "Drift (high severity)"
    drift_output=$(just drift --limit=5 2>&1 || true)
    if echo "$drift_output" | grep -q "0 high"; then
        echo "  No high-severity drift"
    else
        echo "$drift_output" | tail -5 | sed 's/^/  /'
    fi

    # Summary
    echo ""
    echo "==========================================="
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
[script('bash')]
grep pattern glob='':
    set -uo pipefail
    GLOB_ARGS=()
    if [[ -n "{{ glob }}" ]]; then
        GLOB_ARGS=(--glob "{{ glob }}")
    fi
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            label="vauchi (root)"
            search_dir="."
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"
            search_dir="${dir%/}"
        fi
        # Skip generated/vendor dirs
        results=$(rg "{{ pattern }}" "$search_dir" \
            --no-heading --color=never \
            --glob '!target/' --glob '!node_modules/' --glob '!dist/' \
            --glob '!*.lock' --glob '!.git/' \
            "${GLOB_ARGS[@]}" 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            echo "=== $label ==="
            echo "$results"
            echo ""
        fi
    done

# Verify Cargo.toml branch refs point to main
# Usage: just check-refs
[group('tools')]
[no-cd]
[script('bash')]
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

# Run REUSE compliance check (SPDX license headers)
# Usage: just reuse [repo]   (omit for all repos)
[group('tools')]
[no-cd]
[script('bash')]
reuse repo='':
    if ! command -v reuse &>/dev/null; then
        echo "WARNING: reuse not installed (pip install reuse)" >&2
        exit 0
    fi
    set -uo pipefail
    if [[ -n "{{ repo }}" ]]; then
        dir="{{ repo }}"
        [[ "$dir" == "root" || "$dir" == "." ]] && dir="."
        echo "=== {{ repo }} ==="
        (cd "$dir" && reuse lint 2>&1) || true
    else
        for dir in . */; do
            if [[ "$dir" == "." ]]; then
                label="vauchi (root)"
            else
                [[ ! -d "${dir}.git" ]] && continue
                label="${dir%/}"
                dir="${dir%/}"
            fi
            echo "=== $label ==="
            (cd "$dir" && reuse lint 2>&1 | tail -3) || true
            echo ""
        done
    fi

# Search by drift-detector concept (uses concept aliases from driftconfig.toml)
# Usage: just concept exchange     (finds exchange + proximity + qr + nfc + ble + audio + prekey)
#        just concept security     (finds security + auth + attacks + spoofing + passwords)
[group('tools')]
[no-cd]
[script('bash')]
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
    echo "=== Feature scenarios ==="
    rg -i "$pattern" features/ --glob '*.feature' -n --color=never 2>/dev/null | grep -iE "Scenario|Feature:" | head -30 || echo "  (none)"
    echo ""
    echo "=== Tests ==="
    rg -i "$pattern" core/vauchi-core/tests/ core/vauchi-mobile/tests/ e2e/ cli/ tui/ relay/ desktop/src-tauri/src/ \
        --glob '*.rs' -l --color=never 2>/dev/null | head -20 || echo "  (none)"
    echo ""
    echo "=== Source ==="
    rg -i "$pattern" core/vauchi-core/src/ relay/src/ \
        --glob '*.rs' -l --color=never 2>/dev/null | head -20 || echo "  (none)"
    echo ""
    echo "=== Docs ==="
    rg -i "$pattern" docs/ _private/docs/ \
        --glob '*.md' -l --color=never 2>/dev/null | head -20 || echo "  (none)"

# Check for tests missing @scenario annotations
# Usage: just check-annotations [repo]
[group('tools')]
[no-cd]
[script('bash')]
check-annotations repo='core':
    set -uo pipefail
    case "{{ repo }}" in
        core) dirs="core/vauchi-core/tests core/vauchi-mobile/tests" ;;
        e2e)  dirs="e2e/tests" ;;
        relay) dirs="relay/tests" ;;
        cli)  dirs="cli/tests" ;;
        tui)  dirs="tui/tests" ;;
        all)  dirs="core/vauchi-core/tests core/vauchi-mobile/tests e2e/tests relay/tests cli/tests tui/tests" ;;
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
[script('bash')]
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

# Find downstream consumers of a core function/type across repos
# Usage: just consumers ExchangeSession
#        just consumers "fn get_card"
[group('tools')]
[no-cd]
[script('bash')]
consumers pattern:
    set -uo pipefail
    echo "Searching for '{{ pattern }}' across downstream repos..."
    echo ""
    DOWNSTREAM_DIRS=(cli tui desktop/src-tauri e2e relay)
    for dir in "${DOWNSTREAM_DIRS[@]}"; do
        [[ ! -d "$dir" ]] && continue
        label=$(basename "$dir")
        [[ "$dir" == "desktop/src-tauri" ]] && label="desktop"
        results=$(rg "{{ pattern }}" "$dir" \
            --glob '*.rs' --glob '*.ts' --glob '*.tsx' \
            --glob '!target/' --glob '!node_modules/' --glob '!dist/' \
            -n --color=never 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            count=$(echo "$results" | wc -l | tr -d ' ')
            echo "=== $label ($count matches) ==="
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
            echo "=== $dir ($count matches) ==="
            echo "$results"
            echo ""
        fi
    done

# ═══════════════════════════════════════════════════════════════════
# DOCUMENTATION LINTING
# ═══════════════════════════════════════════════════════════════════

# Lint documentation: naming convention, broken links, license text
[group('tools')]
[script('bash')]
lint-docs:
    set -euo pipefail
    ERRORS=0

    # Only scan repos we author (not generated repos like vauchi-mobile-*)
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
        echo "$file" | grep -qE "^\./?(core|relay|cli|tui|desktop|android|ios|e2e|features|assets)/" && continue

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
# DRIFT DETECTION
# ═══════════════════════════════════════════════════════════════════

# Run drift audit (human-readable, fail on high severity by default)
# Usage: just drift [--severity=high] [--group-by=category] [--limit=50] [--verbose]
# Backward compat: just drift medium  (sets --fail-on=medium)
[group('tools')]
[script('bash')]
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
[script('bash')]
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
