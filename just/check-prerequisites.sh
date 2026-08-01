#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Check that required tools are installed before setup.
# Called by: just check-prerequisites

set -euo pipefail

# Ensure Git's utilities (uname, head, etc.) are on PATH on Windows
if [[ -d "/usr/bin" ]] && [[ ":$PATH:" != *":/usr/bin:"* ]]; then
    export PATH="/usr/bin:$PATH"
fi

MISSING=0
WARN=0

echo "=== Checking prerequisites ==="
echo ""

# Ensure ~/.cargo/bin is on PATH (common on fresh installs)
if [[ -d "$HOME/.cargo/bin" ]] && [[ ":$PATH:" != *":$HOME/.cargo/bin:"* ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# Detect platform using bash built-in $OSTYPE (no external commands)
case "$OSTYPE" in
    darwin*)  PLATFORM="macos" ;;
    linux*)   PLATFORM="linux" ;;
    msys*|cygwin*|mingw*) PLATFORM="windows" ;;
    *)       PLATFORM="unknown" ;;
esac

# Resolving on PATH is not the same as working. cargo/rustc/rustfmt are
# rustup shims that exit non-zero when no default toolchain is
# configured; the old `|| ver="(installed)"` fallback turned that failure
# into a ✓, so setup reported "All required tools present" and then died
# on `cargo update` three repos later (2026-08-01).
probe_version() {
    local cmd="$1" ver
    if ver=$("$cmd" --version 2>/dev/null | head -1) && [[ -n "$ver" ]]; then
        printf '%s' "$ver"
        return 0
    fi
    return 1
}

report_broken() {
    local cmd="$1"
    case "$cmd" in
        cargo|rustc|rustfmt|clippy-driver)
            echo "    A rustup shim with no toolchain does this — try: rustup default stable"
            ;;
        *)
            echo "    It resolves on PATH but exits non-zero — reinstall it."
            ;;
    esac
}

check_required() {
    local cmd="$1" purpose="$2" install_hint="$3" ver
    if ! command -v "$cmd" &>/dev/null; then
        echo "  ✗ $cmd — MISSING ($purpose)"
        echo "    Install: $install_hint"
        MISSING=$((MISSING + 1))
        return
    fi
    if ver=$(probe_version "$cmd"); then
        echo "  ✓ $cmd — $ver"
        return
    fi
    echo "  ✗ $cmd — not runnable ($purpose)"
    report_broken "$cmd"
    MISSING=$((MISSING + 1))
}

check_recommended() {
    local cmd="$1" purpose="$2" install_hint="$3" ver
    if ! command -v "$cmd" &>/dev/null; then
        echo "  ~ $cmd — not found ($purpose)"
        echo "    Install: $install_hint"
        WARN=$((WARN + 1))
        return
    fi
    if ver=$(probe_version "$cmd"); then
        echo "  ✓ $cmd — $ver"
        return
    fi
    echo "  ~ $cmd — not runnable ($purpose)"
    report_broken "$cmd"
    WARN=$((WARN + 1))
}

# ── Required ──────────────────────────────────────────────────────
echo "── Required ──"

check_required "git" "version control" \
    "https://git-scm.com/downloads"

case "$PLATFORM" in
    windows) RUSTUP_HINT="winget install Rustlang.Rustup  (or https://rustup.rs)" ;;
    *)       RUSTUP_HINT="curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" ;;
esac

check_required "rustup" "Rust toolchain manager" "$RUSTUP_HINT"
check_required "cargo" "Rust build tool" "install via rustup (above)"
check_required "rustc" "Rust compiler" "install via rustup (above)"

case "$PLATFORM" in
    macos)   JUST_HINT="brew install just" ;;
    linux)   JUST_HINT="cargo install just  (or https://just.systems/man/en/packages.html)" ;;
    windows) JUST_HINT="winget install Casey.Just  (or cargo install just)" ;;
    *)       JUST_HINT="cargo install just" ;;
esac
check_required "just" "command runner (all build/test/deploy recipes)" "$JUST_HINT"

echo ""

# ── Recommended ───────────────────────────────────────────────────
echo "── Recommended ──"

case "$PLATFORM" in
    macos)
        check_recommended "glab" "GitLab CLI for MRs and pipelines" \
            "brew install glab"
        check_recommended "node" "JavaScript runtime (web-demo, docs)" \
            "brew install node"
        check_recommended "jq" "JSON processing" \
            "brew install jq"
        ;;
    linux)
        check_recommended "glab" "GitLab CLI for MRs and pipelines" \
            "https://gitlab.com/gitlab-org/cli#installation"
        check_recommended "node" "JavaScript runtime (web-demo, docs)" \
            "https://nodejs.org/en/download"
        check_recommended "jq" "JSON processing" \
            "sudo apt install jq  (or your package manager)"
        ;;
    windows)
        check_recommended "glab" "GitLab CLI for MRs and pipelines" \
            "winget install glab  (or scoop install glab)"
        check_recommended "node" "JavaScript runtime (web-demo, docs)" \
            "winget install OpenJS.NodeJS.LTS"
        check_recommended "jq" "JSON processing" \
            "winget install jqlang.jq  (or scoop install jq)"
        ;;
    *)
        check_recommended "glab" "GitLab CLI for MRs and pipelines" \
            "https://gitlab.com/gitlab-org/cli#installation"
        check_recommended "node" "JavaScript runtime (web-demo, docs)" \
            "https://nodejs.org/en/download"
        check_recommended "jq" "JSON processing" \
            "https://jqlang.github.io/jq/download/"
        ;;
esac

# ── Structured data tools (used by session-init, dev recipes) ─────
echo ""
echo "── Structured data tools ──"

case "$PLATFORM" in
    macos)
        check_recommended "taplo" "TOML parsing (Cargo.toml version/branch extraction)" \
            "brew install taplo"
        check_recommended "yq" "YAML parsing (project.yml binding version extraction)" \
            "brew install yq"
        ;;
    linux)
        check_recommended "taplo" "TOML parsing (Cargo.toml version/branch extraction)" \
            "cargo binstall taplo-cli  (or cargo install taplo-cli)"
        check_recommended "yq" "YAML parsing (project.yml binding version extraction)" \
            "https://github.com/mikefarah/yq#install"
        ;;
    windows)
        check_recommended "taplo" "TOML parsing (Cargo.toml version/branch extraction)" \
            "cargo install taplo-cli"
        check_recommended "yq" "YAML parsing (project.yml binding version extraction)" \
            "winget install MikeFarah.yq"
        ;;
    *)
        check_recommended "taplo" "TOML parsing (Cargo.toml version/branch extraction)" \
            "cargo install taplo-cli"
        check_recommended "yq" "YAML parsing (project.yml binding version extraction)" \
            "https://github.com/mikefarah/yq#install"
        ;;
esac

# ── Linting tools (used by gate-push hook) ────────────────────────
echo ""
echo "── Linting tools (gate-push hook) ──"

case "$PLATFORM" in
    macos)
        check_recommended "shellcheck" "shell script portability linting (pre-commit)" \
            "brew install shellcheck"
        check_recommended "markdownlint" "markdown linting (gate-push)" \
            "npm i -g markdownlint-cli"
        check_recommended "typos" "spellcheck (gate-push)" \
            "cargo binstall typos-cli  (or cargo install typos-cli)"
        check_recommended "reuse" "SPDX header compliance (gate-push)" \
            "uv tool install reuse  (or brew install reuse)"
        ;;
    linux)
        check_recommended "shellcheck" "shell script portability linting (pre-commit)" \
            "sudo apt install shellcheck"
        check_recommended "markdownlint" "markdown linting (gate-push)" \
            "npm i -g markdownlint-cli"
        check_recommended "typos" "spellcheck (gate-push)" \
            "cargo binstall typos-cli  (or cargo install typos-cli)"
        check_recommended "reuse" "SPDX header compliance (gate-push)" \
            "uv tool install reuse"
        ;;
    windows)
        check_recommended "shellcheck" "shell script portability linting (pre-commit)" \
            "scoop install shellcheck"
        check_recommended "markdownlint" "markdown linting (gate-push)" \
            "npm i -g markdownlint-cli"
        check_recommended "typos" "spellcheck (gate-push)" \
            "cargo install typos-cli"
        check_recommended "reuse" "SPDX header compliance (gate-push)" \
            "uv tool install reuse"
        ;;
    *)
        check_recommended "shellcheck" "shell script portability linting (pre-commit)" \
            "https://github.com/koalaman/shellcheck#installing"
        check_recommended "markdownlint" "markdown linting (gate-push)" \
            "npm i -g markdownlint-cli"
        check_recommended "typos" "spellcheck (gate-push)" \
            "cargo install typos-cli"
        check_recommended "reuse" "SPDX header compliance (gate-push)" \
            "uv tool install reuse"
        ;;
esac

echo ""

# uv — needed for: just design-check, reuse install, quick-install commands
case "$PLATFORM" in
    macos)   UV_HINT="brew install uv" ;;
    linux)   UV_HINT="curl -LsSf https://astral.sh/uv/install.sh | sh" ;;
    windows) UV_HINT="winget install astral-sh.uv" ;;
    *)       UV_HINT="curl -LsSf https://astral.sh/uv/install.sh | sh" ;;
esac
check_recommended "uv" "Python runner — needed for just design-check and reuse" "$UV_HINT"

echo ""

# ── Quick install ─────────────────────────────────────────────────
if [[ "$MISSING" -gt 0 || "$WARN" -gt 0 ]]; then
    echo "── Quick install ──"
    echo ""
    case "$PLATFORM" in
        macos)
            echo "  # Required + recommended (Homebrew):"
            echo "  brew install rustup node glab jq uv taplo yq shellcheck"
            echo "  rustup-init -y && source \"\$HOME/.cargo/env\""
            echo "  uv tool install reuse"
            echo "  cargo binstall typos-cli && npm i -g markdownlint-cli"
            ;;
        linux)
            echo "  # Required (rustup):"
            echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
            echo "  source \"\$HOME/.cargo/env\""
            echo ""
            echo "  # Recommended:"
            echo "  sudo apt install -y nodejs npm jq shellcheck"
            echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
            echo "  uv tool install reuse"
            echo "  cargo binstall typos-cli taplo-cli && npm i -g markdownlint-cli"
            echo "  # glab: https://gitlab.com/gitlab-org/cli#installation"
            echo "  # yq: https://github.com/mikefarah/yq#install"
            ;;
        windows)
            echo "  # Required + recommended (winget — run in PowerShell):"
            echo "  winget install Rustlang.Rustup astral-sh.uv MikeFarah.yq"
            echo "  winget install GitLab.Glab OpenJS.NodeJS.LTS jqlang.jq"
            echo "  uv tool install reuse"
            echo "  cargo install taplo-cli"
            echo ""
            echo "  Restart your terminal after installing to update PATH."
            ;;
    esac
    echo ""
fi

# ── Summary ───────────────────────────────────────────────────────
if [[ "$MISSING" -gt 0 ]]; then
    echo "✗ $MISSING required tool(s) missing or not runnable — fix them and re-run: just setup"
    exit 1
elif [[ "$WARN" -gt 0 ]]; then
    echo "✓ All required tools present ($WARN recommended tool(s) missing — setup will continue)"
else
    echo "✓ All tools present"
fi
