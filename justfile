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
check repo='':
    just fmt-check {{repo}}
    just lint {{repo}}
    just test {{repo}}

# Build workspace or specific repo
[group('daily')]
[script('bash')]
build repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    for r in $(resolve_repo "{{repo}}" "build"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        echo "═══ build: $r ($tc) ═══"
        case "$tc" in
            rust)    (cd "$dir" && cargo build --workspace 2>&1) || exit 1 ;;
            npm)     (cd "$dir" && npm ci --silent && npm run build 2>&1) || exit 1 ;;
            gradle)  (cd "$dir" && ./gradlew assembleDebug 2>&1) || exit 1 ;;
            xcode)   (cd "$dir" && xcodebuild -scheme Vauchi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build -quiet 2>&1) || exit 1 ;;
            mkdocs)  (cd "$dir" && mkdocs build --strict 2>&1) || exit 1 ;;
            *)       echo "  (no build step for $tc)" ;;
        esac
    done

# Run tests
[group('daily')]
[script('bash')]
test repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    for r in $(resolve_repo "{{repo}}" "test"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        echo "═══ test: $r ($tc) ═══"
        case "$tc" in
            rust)
                if command -v cargo-nextest &>/dev/null; then
                    (cd "$dir" && cargo nextest run --workspace 2>&1) || exit 1
                else
                    (cd "$dir" && cargo test --workspace 2>&1) || exit 1
                fi
                ;;
            npm)     (cd "$dir" && npx playwright test --project=chromium --grep-invert "@visual|@a11y" 2>&1) || exit 1 ;;
            gradle)  (cd "$dir" && ./gradlew test 2>&1) || exit 1 ;;
            xcode)   (cd "$dir" && xcodebuild -scheme Vauchi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -quiet 2>&1) || exit 1 ;;
            mkdocs)  (cd "$dir" && mkdocs build --strict 2>&1) || exit 1 ;;
            *)       echo "  (no test step for $tc)" ;;
        esac
    done

# Format code
[group('daily')]
[script('bash')]
fmt repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    for r in $(resolve_repo "{{repo}}" "fmt"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        echo "═══ fmt: $r ($tc) ═══"
        case "$tc" in
            rust)    (cd "$dir" && cargo fmt --all 2>&1) || exit 1 ;;
            npm)     (cd "$dir" && npx prettier --write src/ 2>&1) || exit 1 ;;
            xcode)   (cd "$dir" && swiftformat . 2>&1) || exit 1 ;;
            *)       echo "  (no fmt step for $tc)" ;;
        esac
    done

# Check formatting (no changes)
[group('daily')]
[script('bash')]
fmt-check repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    for r in $(resolve_repo "{{repo}}" "fmt"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        echo "═══ fmt-check: $r ($tc) ═══"
        case "$tc" in
            rust)    (cd "$dir" && cargo fmt --all -- --check 2>&1) || exit 1 ;;
            npm)     (cd "$dir" && npx prettier --check src/ 2>&1) || exit 1 ;;
            xcode)   (cd "$dir" && swiftformat --lint . 2>&1) || exit 1 ;;
            *)       echo "  (no fmt-check step for $tc)" ;;
        esac
    done

# Run lints
[group('daily')]
[script('bash')]
lint repo='':
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    for r in $(resolve_repo "{{repo}}" "lint"); do
        dir=$(repo_dir "$r")
        tc=$(repo_toolchain "$r")
        echo "═══ lint: $r ($tc) ═══"
        case "$tc" in
            rust)    (cd "$dir" && cargo clippy --workspace -- -D warnings 2>&1) || exit 1 ;;
            npm)     (cd "$dir" && npm run lint 2>&1 && npm run lint:css 2>&1) || exit 1 ;;
            gradle)  (cd "$dir" && ./gradlew lint 2>&1) || exit 1 ;;
            xcode)   (cd "$dir" && swiftlint lint --strict --quiet 2>&1 && swiftformat --lint . 2>&1) || exit 1 ;;
            mkdocs)  (cd "$dir" && markdownlint '**/*.md' 2>&1) || exit 1 ;;
            python)
                if [[ -f "$dir/scripts/validate.py" ]]; then
                    (cd "$dir" && python3 scripts/validate.py 2>&1) || exit 1
                fi
                ;;
            gherkin) echo "  (gherkin lint: advisory only)" ;;
            shell)   (cd "$dir" && shellcheck scripts/*.sh 2>&1) || exit 1 ;;
            html)    (cd "$dir" && htmlhint public/**/*.html 2>&1) || exit 1 ;;
            *)       echo "  (no lint step for $tc)" ;;
        esac
    done

# Interactive commit across repos with changes
[group('daily')]
commit:
    ./scripts/scripts/commit-interactive.sh

# ═══════════════════════════════════════════════════════════════════
# EXTENDED COMMANDS - Less frequently used
# ═══════════════════════════════════════════════════════════════════

# Run tests for specific crate (within core workspace)
[group('extended')]
[working-directory('core')]
test-crate crate:
    cargo test -p {{crate}}

# Build release binaries
[group('extended')]
[working-directory('core')]
build-release:
    cargo build --workspace --release

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

# Run tests with coverage
[group('extended')]
[working-directory('core')]
coverage:
    cargo llvm-cov --workspace --html
    @echo "Report: core/target/llvm-cov/html/index.html"

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

      Repo argument: omit = auto-detect from pwd (or all from workspace root)
      Examples: just test core, just lint cli, just check desktop
      Valid repos: core cli relay tui e2e desktop android ios docs
                   locales themes features website scripts

    GitLab:
      just gitlab mr-list [repo]            List open MRs
      just gitlab mr-view <id> [repo]       View MR details
      just gitlab mr-create [repo]          Create MR from current branch
      just gitlab mr-approve <id> [repo]    Approve MR
      just gitlab mr-merge <id> [repo]      Merge MR
      just gitlab pipeline-status [repo]    Pipeline status (current branch)
      just gitlab pipeline-list [repo]      Recent pipelines
      just gitlab pipeline-log <id> [repo]  Job log output
      just gitlab issue-list [repo]         List open issues
      just gitlab issue-create <t> [repo]   Create issue

    Git (multi-repo):
      just git main           Stash → checkout main → pull (all repos)
      just git status         Show status across all repos
      just git pull-all       Pull latest in all repos
      just git push-all       Push repos with commits ahead
      just git fetch          Fetch all repos
      just git branches       Show branches across repos
      just git cleanup        Preview merged branch cleanup (dry run)
      just git cleanup run    Delete merged branches + prune stale refs

    Apps:
      just run <platform>     Run app (cli|tui|desktop|relay|android|ios)
      just relay              Start relay server
      just tui                Run TUI

    Extended:
      just test-crate <crate> Test specific crate in core workspace
      just audit [repo]       Security audit (Rust repos)
      just coverage           Coverage report (core)
      just watch              Watch + test (core)
      just build-release      Release build (core)

    Setup:
      just setup              Clone all repos, init workspace
      just install-dev-deps   Install toolchain (Homebrew + Cargo)
      just clean              Clean all build artifacts

    Other:
      just metrics            Engineering metrics dashboard
      just lint-docs          Check doc naming, links, license text
      just sync-locales       Validate locale files
      just vrt-gallery        Cross-platform VRT gallery

    Full list:  just --list --list-submodules
    HELP

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
    if [[ ! -d dist ]]; then
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
    if [[ ! -d dist ]]; then
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
