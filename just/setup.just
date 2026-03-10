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
    cargo_tools=(cargo-watch cargo-audit cargo-deny cargo-llvm-cov sccache cargo-duplicates cargo-bloat)
    for tool in "${cargo_tools[@]}"; do
        bin_name="$tool"
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

# Configure sccache + mold for faster Rust builds (idempotent)
[group('setup')]
[script('bash')]
setup-fast-builds:
    set -euo pipefail

    CARGO_CONFIG="$HOME/.cargo/config.toml"
    CHANGED=0

    echo "=== Configuring fast Rust builds ==="
    echo ""

    # Ensure file exists
    touch "$CARGO_CONFIG"

    # ── sccache ──────────────────────────────────────────────────────
    if command -v sccache &>/dev/null; then
        SCCACHE_PATH=$(command -v sccache)
        if grep -q 'rustc-wrapper' "$CARGO_CONFIG" 2>/dev/null; then
            echo "  sccache: already configured"
        else
            echo "" >> "$CARGO_CONFIG"
            echo "[build]" >> "$CARGO_CONFIG"
            echo "rustc-wrapper = \"$SCCACHE_PATH\"" >> "$CARGO_CONFIG"
            echo "  sccache: configured ($SCCACHE_PATH)"
            CHANGED=1
        fi
    else
        echo "  sccache: not installed (install with: cargo install sccache)"
    fi

    # ── mold linker ──────────────────────────────────────────────────
    if command -v mold &>/dev/null; then
        MOLD_PATH=$(command -v mold)
        case "$(uname -s)-$(uname -m)" in
            Linux-x86_64)  TARGET_KEY="x86_64-unknown-linux-gnu" ;;
            Linux-aarch64) TARGET_KEY="aarch64-unknown-linux-gnu" ;;
            Darwin-arm64)  TARGET_KEY="aarch64-apple-darwin" ;;
            Darwin-x86_64) TARGET_KEY="x86_64-apple-darwin" ;;
            *)             TARGET_KEY="" ;;
        esac
        if [[ -z "$TARGET_KEY" ]]; then
            echo "  mold: unsupported platform ($(uname -s)-$(uname -m))"
        elif grep -q "$TARGET_KEY" "$CARGO_CONFIG" 2>/dev/null; then
            echo "  mold: already configured ($TARGET_KEY)"
        else
            echo "" >> "$CARGO_CONFIG"
            echo "[target.$TARGET_KEY]" >> "$CARGO_CONFIG"
            echo "linker = \"clang\"" >> "$CARGO_CONFIG"
            echo "rustflags = [\"-C\", \"link-arg=-fuse-ld=$MOLD_PATH\"]" >> "$CARGO_CONFIG"
            echo "  mold: configured for $TARGET_KEY ($MOLD_PATH)"
            CHANGED=1
        fi
    else
        echo "  mold: not installed"
        case "$(uname)" in
            Linux)  echo "         install with: sudo pacman -S mold  (or apt install mold)" ;;
            Darwin) echo "         install with: brew install mold" ;;
        esac
    fi

    echo ""
    if [[ "$CHANGED" == "1" ]]; then
        echo "Updated $CARGO_CONFIG"
        echo ""
        echo "Current config:"
        cat "$CARGO_CONFIG"
    else
        echo "No changes needed."
    fi

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
        elif command -v pip3 &>/dev/null; then
            pip3 install --user ./markdown-plan/python
        elif command -v pip &>/dev/null; then
            pip install --user ./markdown-plan/python
        else
            echo "Error: pip/pip3/pipx not found. Install with: brew install pipx" >&2
            exit 1
        fi
    fi

# Clean all build artifacts
[group('setup')]
[confirm('This will remove all build artifacts, node_modules, and caches. Continue?')]
[script('bash')]
clean:
    echo "Cleaning build artifacts..."

    # Rust targets
    for dir in core relay cli tui e2e linux-gtk web-demo/wasm; do
        if [[ -d "$dir/target" ]]; then
            echo "  Cleaning $dir/target"
            rm -rf "$dir/target"
        fi
    done

    # Node modules and build outputs
    for dir in _private/website web-demo; do
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
    for dir in core relay cli tui e2e linux-gtk web-demo/wasm; do
        if [[ -d "$dir/target" ]]; then
            echo "  $dir/target"
            rm -rf "$dir/target"
        fi
    done
    echo "Done!"
