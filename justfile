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

# ─── Modules ──────────────────────────────────────────────────────

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
check: fmt-check lint test

# Build core workspace
build:
    cd core && cargo build --workspace

# Run tests
test:
    cd core && cargo test --workspace

# Format code
fmt:
    cd core && cargo fmt --all

# Check formatting (no changes)
fmt-check:
    cd core && cargo fmt --all -- --check

# Run clippy lints
lint:
    cd core && cargo clippy --workspace -- -D warnings

# Interactive commit across repos with changes
commit:
    ./scripts/scripts/commit-interactive.sh

# ═══════════════════════════════════════════════════════════════════
# EXTENDED COMMANDS - Less frequently used
# ═══════════════════════════════════════════════════════════════════

# Run tests for specific crate
test-crate crate:
    cd core && cargo test -p {{crate}}

# Build release binaries
build-release:
    cd core && cargo build --workspace --release

# Run security audit
audit:
    cd core && cargo audit
    cd core && cargo deny check

# Auto-fix lint issues
fix:
    cd core && cargo fmt --all
    cd core && cargo clippy --workspace --fix --allow-dirty --allow-staged

# Watch for changes and run tests
watch:
    cd core && cargo watch -x "test --workspace"

# Run tests with coverage
coverage:
    cd core && cargo llvm-cov --workspace --html
    @echo "Report: core/target/llvm-cov/html/index.html"

# Generate and open Rust docs
docs:
    cd core && cargo doc --workspace --no-deps --open

# Install git hooks
install-hooks:
    cp scripts/hooks/* .git/hooks/
    chmod +x .git/hooks/*

# Show quick reference
help:
    #!/usr/bin/env bash
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
      just deploy-relay       Deploy relay via Kamal
      just runners-start      Start GitLab CI runners

    Full list:  just --list --list-submodules
    Git cmds:   just --list --list-submodules | grep git
    HELP

# ═══════════════════════════════════════════════════════════════════
# AI/LLM TOOLS
# ═══════════════════════════════════════════════════════════════════

# Explore codebase with local LLM (e.g., just tell-me-about "iOS tests")
tell-me-about *topic:
    ./scripts/scripts/tell-me-about.sh {{topic}}
