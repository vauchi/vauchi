# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Setup & maintenance recipes

# Clone all repos and set up workspace (run first after cloning meta-repo)
[group('setup')]
setup: clone-repos && install-hooks install-mdplan
    mkdir -p tmp cache
    @echo "Workspace ready! Run: just check"

# Install development dependencies (macOS via Homebrew + Cargo)
[group('setup')]
[script('bash')]
install-dev-deps:
    set -e

    echo "=== Installing development dependencies ==="
    echo ""

    # ── Homebrew packages ──────────────────────────────────────────
    echo "── Homebrew packages ──"
    brew_pkgs=(just node)
    for pkg in "${brew_pkgs[@]}"; do
        if brew list "$pkg" &>/dev/null; then
            echo "  $pkg (already installed)"
        else
            echo "  Installing $pkg..."
            brew install "$pkg"
        fi
    done
    echo ""

    # ── Rust toolchain ─────────────────────────────────────────────
    echo "── Rust toolchain ──"
    if command -v rustup &>/dev/null; then
        echo "  rustup (already installed)"
        echo "  Ensuring llvm-tools-preview component..."
        rustup component add llvm-tools-preview
    else
        echo "  Installing rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
        rustup component add llvm-tools-preview
    fi
    echo ""

    # ── cargo-binstall (pre-built binary installer) ─────────────────
    echo "── cargo-binstall ──"
    if command -v cargo-binstall &>/dev/null; then
        echo "  cargo-binstall (already installed)"
    else
        echo "  Installing cargo-binstall..."
        curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash
    fi
    echo ""

    # ── Cargo tools (via binstall for speed) ─────────────────────────
    echo "── Cargo tools ──"
    cargo_tools=(cargo-watch cargo-audit cargo-deny cargo-llvm-cov tauri-cli)
    for tool in "${cargo_tools[@]}"; do
        bin_name="$tool"
        # tauri-cli installs as "cargo-tauri"
        [[ "$tool" == "tauri-cli" ]] && bin_name="cargo-tauri"
        if cargo install --list | grep -q "^${tool} "; then
            echo "  $tool (already installed)"
        else
            echo "  Installing $tool..."
            cargo binstall "$tool" --no-confirm 2>/dev/null || cargo install "$tool"
        fi
    done
    echo ""

    # ── iOS targets (macOS only) ───────────────────────────────────
    echo "── iOS Rust targets ──"
    rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
    echo ""

    # ── Android targets (optional, skip if no NDK) ─────────────────
    echo "── Android Rust targets ──"
    rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android
    echo ""

    echo "=== Done ==="
    echo ""
    echo "Optional (install manually if needed):"
    echo "  brew install kamal              # Relay deployment"
    echo "  brew install --cask android-studio  # Android SDK + emulator"
    echo ""
    echo "Next: just setup && just check"

# Clone all repositories
[private]
[script('bash')]
clone-repos:
    set -e
    echo "Cloning public repositories..."
    for repo in {{public_repos}}; do
        if [[ -d "$repo" ]]; then
            echo "  $repo (exists)"
        else
            if git clone "{{gitlab_base}}/$repo.git" "$repo" 2>/dev/null; then
                echo "  $repo (cloned)"
            else
                echo "  $repo (skipped)"
            fi
        fi
    done
    echo "Cloning private repository..."
    if [[ -d "_private" ]]; then
        echo "  _private (exists)"
    else
        if git clone "{{gitlab_base}}/{{private_repo}}.git" "_private" 2>/dev/null; then
            echo "  _private (cloned)"
        else
            echo "  _private (skipped - no access?)"
        fi
    fi
    echo "Cloning tooling repositories..."
    for entry in {{tooling_repos}}; do
        url="${entry%%,*}"
        dir="${entry##*,}"
        if [[ -d "$dir" ]]; then
            echo "  $dir (exists)"
        else
            if git clone "$url" "$dir" 2>/dev/null; then
                echo "  $dir (cloned)"
            else
                echo "  $dir (skipped)"
            fi
        fi
    done

# Install markdown-plan CLI tool
[private]
[script('bash')]
install-mdplan:
    set -e
    if command -v mdplan &>/dev/null; then
        echo "  mdplan (already installed)"
    else
        echo "  Installing mdplan..."
        if command -v pipx &>/dev/null; then
            pipx install ./markdown-plan/python
        else
            pip install --user ./markdown-plan/python
        fi
    fi

# Clean all build artifacts
[group('setup')]
[confirm('This will remove all build artifacts, node_modules, and caches. Continue?')]
[script('bash')]
clean:
    echo "Cleaning build artifacts..."

    # Rust targets
    for dir in core relay cli tui desktop/src-tauri e2e; do
        if [[ -d "$dir/target" ]]; then
            echo "  Cleaning $dir/target"
            rm -rf "$dir/target"
        fi
    done

    # Node modules and build outputs
    for dir in desktop/ui _private/website; do
        if [[ -d "$dir/node_modules" ]]; then
            echo "  Cleaning $dir/node_modules"
            rm -rf "$dir/node_modules"
        fi
        if [[ -d "$dir/dist" ]]; then
            echo "  Cleaning $dir/dist"
            rm -rf "$dir/dist"
        fi
    done

    # Android build
    if [[ -d "android/app/build" ]]; then
        echo "  Cleaning android/app/build"
        rm -rf android/app/build
    fi

    # iOS build
    if [[ -d "ios/build" ]]; then
        echo "  Cleaning ios/build"
        rm -rf ios/build
    fi

    # Tmp and cache
    rm -rf tmp/* cache/*

    echo "Done!"

# Clean only Rust targets (faster)
[group('setup')]
[confirm('This will remove all Rust target directories. Continue?')]
[script('bash')]
clean-rust:
    echo "Cleaning Rust targets..."
    for dir in core relay cli tui desktop/src-tauri e2e; do
        if [[ -d "$dir/target" ]]; then
            echo "  $dir/target"
            rm -rf "$dir/target"
        fi
    done
    echo "Done!"
