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
public_repos := "gitlab-profile scripts assets core relay cli tui desktop e2e features android ios docs locales website vauchi-mobile-swift vauchi-mobile-android"

# Private repository (consolidated, cloned as _private)
private_repo := "private"

# Tooling repositories (url,dir format, outside vauchi group)
tooling_repos := "git@gitlab.com:megloff1/drift-detector.git,drift-detector"

# ─── Aliases ─────────────────────────────────────────────────────

alias b := build
alias t := test
alias c := check
alias f := fmt

# ─── Modules ──────────────────────────────────────────────────────

[doc('Multi-repo git operations')]
mod git 'just/git.just'

import 'just/apps.just'
import 'just/setup.just'
import 'just/mobile.just'
import 'just/e2e.just'
import 'just/deploy.just'
import 'just/runners.just'
import 'just/dev.just'

# ═══════════════════════════════════════════════════════════════════
# DAILY COMMANDS - Use these regularly
# ═══════════════════════════════════════════════════════════════════

# Run all checks (format, lint, test)
[group('daily')]
check: fmt-check lint test

# Build core workspace
[group('daily')]
[working-directory('core')]
build:
    cargo build --workspace

# Run tests
[group('daily')]
[working-directory('core')]
test:
    cargo test --workspace

# Format code
[group('daily')]
[working-directory('core')]
fmt:
    cargo fmt --all

# Check formatting (no changes)
[private]
[working-directory('core')]
fmt-check:
    cargo fmt --all -- --check

# Run clippy lints
[group('daily')]
[working-directory('core')]
lint:
    cargo clippy --workspace -- -D warnings

# Interactive commit across repos with changes
[group('daily')]
commit:
    ./scripts/scripts/commit-interactive.sh

# ═══════════════════════════════════════════════════════════════════
# EXTENDED COMMANDS - Less frequently used
# ═══════════════════════════════════════════════════════════════════

# Run tests for specific crate
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
[working-directory('core')]
audit:
    cargo audit
    cargo deny check

# Auto-fix lint issues
[group('extended')]
[working-directory('core')]
fix:
    cargo fmt --all
    cargo clippy --workspace --fix --allow-dirty --allow-staged

# Watch for changes and run tests
[group('extended')]
[working-directory('core')]
watch:
    cargo watch -x "test --workspace"

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

# Install git hooks
[group('extended')]
install-hooks:
    cp scripts/hooks/* .git/hooks/
    chmod +x .git/hooks/*

# Show quick reference
[group('tools')]
[script('bash')]
help:
    cat <<'HELP'
    Vauchi Development Commands
    ═══════════════════════════

    Daily workflow:
      just check              Format + lint + test (core/)
      just build              Build core workspace
      just test               Run tests
      just fmt                Format code
      just fix                Auto-fix lint issues
      just commit             Interactive commit across repos

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

    Setup:
      just setup              Clone all repos, init workspace
      just install-dev-deps   Install toolchain (Homebrew + Cargo)
      just clean              Clean all build artifacts

    Mobile:
      just check-ios          iOS lint + build + test
      just check-android      Android lint + build + test
      just check-mobile       Both

    E2E:
      just e2e                List available tests
      just e2e-run <name>     Run E2E test (or 'all')
      just e2e-smoke          Fast smoke tests

    Other:
      just coverage           Test coverage report
      just docs               Open Rust docs
      just audit              Security audit
      just lint-docs          Check doc naming, links, license text
      just vrt-gallery        Cross-platform VRT screenshot gallery
      just validate            Pre-flight deployment checks
      just deploy              Deploy relay + landing via Kamal
      just runners-start      Start GitLab CI runners

    Full list:  just --list --list-submodules
    Git cmds:   just --list --list-submodules | grep git
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
# AI/LLM TOOLS
# ═══════════════════════════════════════════════════════════════════

# Explore codebase with local LLM (e.g., just tell-me-about "iOS tests")
[group('tools')]
tell-me-about *topic:
    ./scripts/scripts/tell-me-about.sh {{topic}}
