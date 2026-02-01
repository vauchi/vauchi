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
public_repos := "gitlab-profile scripts assets core relay cli tui desktop e2e features android ios"

# Private repository (consolidated, cloned as _private)
private_repo := "private"

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
      just vrt-gallery        Cross-platform VRT screenshot gallery
      just validate            Pre-flight deployment checks
      just deploy              Deploy relay + landing via Kamal
      just runners-start      Start GitLab CI runners

    Full list:  just --list --list-submodules
    Git cmds:   just --list --list-submodules | grep git
    HELP

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
