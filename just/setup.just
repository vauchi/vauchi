# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Setup & maintenance recipes

# Check that required tools are installed before setup
[group('setup')]
check-prerequisites:
    @source scripts/check-prerequisites.sh

# Clone all repos and set up workspace (run first after cloning meta-repo)
[group('setup')]
setup: check-prerequisites clone-repos && install-hooks install-mdplan setup-path-overrides
    mkdir -p tmp cache
    @echo "Workspace ready! Run: just check"

# Sync shared infrastructure and hooks before a work session
[group('setup')]
[script]
session-init:
    set -euo pipefail

    echo "── Session init ──"
    WARN=0

    # Pull scripts repo (hooks, CI templates)
    echo ""
    echo "── scripts ──"
    if git -C scripts fetch origin main --quiet 2>/dev/null; then
        LOCAL=$(git -C scripts rev-parse HEAD 2>/dev/null)
        REMOTE=$(git -C scripts rev-parse origin/main 2>/dev/null)
        if [[ "$LOCAL" != "$REMOTE" ]]; then
            if git -C scripts merge-base --is-ancestor "$LOCAL" "$REMOTE" 2>/dev/null; then
                git -C scripts pull --ff-only origin main --quiet
                echo "  Updated to $(git -C scripts log --oneline -1)"
            else
                echo "  WARNING: scripts has local changes — skipping pull"
                WARN=1
            fi
        else
            echo "  Up to date"
        fi
    else
        echo "  WARNING: could not fetch scripts (offline?)"
        WARN=1
    fi

    # Pull root repo
    echo ""
    echo "── root ──"
    if git fetch origin main --quiet 2>/dev/null; then
        LOCAL=$(git rev-parse HEAD 2>/dev/null)
        REMOTE=$(git rev-parse origin/main 2>/dev/null)
        BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [[ "$BRANCH" == "main" && "$LOCAL" != "$REMOTE" ]]; then
            if git merge-base --is-ancestor "$LOCAL" "$REMOTE" 2>/dev/null; then
                git pull --ff-only origin main --quiet
                echo "  Updated to $(git log --oneline -1)"
            else
                echo "  WARNING: root has local changes — skipping pull"
                WARN=1
            fi
        elif [[ "$BRANCH" != "main" ]]; then
            echo "  On branch $BRANCH (not main — skipping pull)"
        else
            echo "  Up to date"
        fi
    else
        echo "  WARNING: could not fetch root (offline?)"
        WARN=1
    fi

    # Reinstall hooks
    echo ""
    echo "── hooks ──"
    bash scripts/install-hooks.sh 2>&1 | tail -1

    # Fetch all repos in parallel + prune stale refs
    echo ""
    echo "── fetch ──"
    for dir in . */; do
        [[ "$dir" == "." ]] && gitdir=".git" || gitdir="${dir}.git"
        [[ -d "$gitdir" ]] && git -C "$dir" fetch --all --prune --quiet 2>/dev/null &
    done
    wait
    echo "  All repos fetched + pruned"

    # ── Dashboard ──
    SI_TMP=$(mktemp -d)
    trap 'rm -rf "$SI_TMP"' EXIT

    # Open MRs (parallelize glab API calls)
    if command -v glab &>/dev/null && glab auth status &>/dev/null 2>&1; then
        source scripts/scripts/resolve-repo.sh
        for dir in . */; do
            if [[ "$dir" == "." ]]; then
                [[ ! -d ".git" ]] && continue
                label="root"
            else
                [[ -d "${dir}.git" ]] || continue
                label="${dir%/}"
            fi
            (
                gl_name=$(_dir_to_gitlab_name "$label")
                mrs=$(glab api "projects/vauchi%2F${gl_name}/merge_requests?state=opened&per_page=20" 2>/dev/null || true)
                count=$(echo "$mrs" | jq 'length' 2>/dev/null || echo "0")
                if [[ "$count" -gt 0 ]]; then
                    echo "$mrs" | jq -r '.[] | (.iid | tostring) + "\t" + .title' 2>/dev/null \
                        | while IFS=$'\t' read -r iid title; do
                            echo "  $label !${iid}  ${title}" >> "$SI_TMP/mrs.txt"
                        done
                fi
            ) &
        done
        wait
    fi

    echo ""
    echo "── dashboard ──"

    echo ""
    echo "OPEN MRs:"
    if [[ -f "$SI_TMP/mrs.txt" && -s "$SI_TMP/mrs.txt" ]]; then
        sort "$SI_TMP/mrs.txt"
    else
        echo "  (none)"
    fi

    # Local branches not on main
    echo ""
    echo "LOCAL BRANCHES (not main):"
    BRANCH_FOUND=0
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            [[ ! -d ".git" ]] && continue
            label="root"; d="."
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"; d="${dir%/}"
        fi
        branches=$(git -C "$d" branch --no-color 2>/dev/null | sed 's/^[* ]*//' | grep -v '^main$' || true)
        [[ -z "$branches" ]] && continue
        while IFS= read -r br; do
            [[ -z "$br" ]] && continue
            age_date=$(git -C "$d" log -1 --format=%ci "$br" 2>/dev/null | cut -d' ' -f1 || echo "?")
            last_epoch=$(git -C "$d" log -1 --format=%ct "$br" 2>/dev/null || echo "0")
            now=$(date +%s)
            age_days=$(( (now - last_epoch) / 86400 ))
            marker=""
            [[ "$age_days" -gt 14 ]] && marker=" STALE"
            echo "  $label ($br) last: $age_date (${age_days}d)$marker"
            BRANCH_FOUND=1
        done <<< "$branches"
    done
    [[ "$BRANCH_FOUND" == "0" ]] && echo "  (none)"

    # Uncommitted changes
    echo ""
    echo "UNCOMMITTED:"
    UNCOMMITTED=0
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            [[ ! -d ".git" ]] && continue
            label="root"; d="."
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"; d="${dir%/}"
        fi
        status=$(git -C "$d" status --porcelain 2>/dev/null || true)
        if [[ -n "$status" ]]; then
            count=$(echo "$status" | wc -l | tr -d ' ')
            echo "  $label: $count file(s) modified"
            UNCOMMITTED=1
            WARN=1
        fi
    done
    [[ "$UNCOMMITTED" == "0" ]] && echo "  (none)"

    # Stashes
    echo ""
    echo "STASHES:"
    STASH_FOUND=0
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            [[ ! -d ".git" ]] && continue
            label="root"; d="."
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"; d="${dir%/}"
        fi
        count=$(git -C "$d" stash list 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$count" -gt 0 ]]; then
            echo "  $label: $count stash(es)"
            STASH_FOUND=1
            WARN=1
        fi
    done
    [[ "$STASH_FOUND" == "0" ]] && echo "  (none)"

    echo ""
    if [[ "$WARN" == "0" ]]; then
        echo "── Ready to work ──"
    else
        echo "── Ready to work (with warnings) ──"
    fi

# Check session readiness before ending — ensures nothing is left behind
[group('setup')]
[script]
session-end:
    set -euo pipefail
    echo "── Session end ──"
    ERRORS=0

    # Check for uncommitted changes
    echo ""
    echo "── uncommitted changes ──"
    UC=0
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            [[ ! -d ".git" ]] && continue
            label="root"; d="."
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"; d="${dir%/}"
        fi
        status=$(git -C "$d" status --porcelain 2>/dev/null || true)
        if [[ -n "$status" ]]; then
            echo "  ERROR: $label has uncommitted changes"
            git -C "$d" status --short 2>/dev/null | sed 's/^/    /'
            ERRORS=1
            UC=1
        fi
    done
    [[ "$UC" == "0" ]] && echo "  All clean"

    # Check for unpushed commits
    echo ""
    echo "── unpushed commits ──"
    UP=0
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            [[ ! -d ".git" ]] && continue
            label="root"; d="."
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"; d="${dir%/}"
        fi
        branch=$(git -C "$d" branch --show-current 2>/dev/null)
        [[ -z "$branch" ]] && continue
        ahead=$(git -C "$d" rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
        if [[ "$ahead" -gt 0 ]]; then
            echo "  ERROR: $label ($branch) has $ahead unpushed commit(s)"
            ERRORS=1
            UP=1
        fi
    done
    [[ "$UP" == "0" ]] && echo "  All pushed"

    # Check for local branches without MRs
    echo ""
    echo "── branches without MRs ──"
    ORPHAN=0
    if command -v glab &>/dev/null && glab auth status &>/dev/null 2>&1; then
        source scripts/scripts/resolve-repo.sh
        for dir in . */; do
            if [[ "$dir" == "." ]]; then
                [[ ! -d ".git" ]] && continue
                label="root"; d="."
            else
                [[ ! -d "${dir}.git" ]] && continue
                label="${dir%/}"; d="${dir%/}"
            fi
            branch=$(git -C "$d" branch --show-current 2>/dev/null)
            [[ "$branch" == "main" || -z "$branch" ]] && continue
            gl_name=$(_dir_to_gitlab_name "$label")
            mr_count=$(glab api "projects/vauchi%2F${gl_name}/merge_requests?state=opened&source_branch=${branch}&per_page=1" 2>/dev/null \
                | jq 'length' 2>/dev/null || echo "0")
            if [[ "$mr_count" == "0" ]]; then
                echo "  WARN: $label ($branch) has no open MR"
                ORPHAN=1
            fi
        done
    fi
    [[ "$ORPHAN" == "0" ]] && echo "  All branches have MRs (or on main)"

    # Process session error log (from hooks that blocked)
    echo ""
    echo "── hook errors this session ──"
    SESSION_LOG=".claude/.session-errors"
    if [[ -f "$SESSION_LOG" && -s "$SESSION_LOG" ]]; then
        TOTAL=$(wc -l < "$SESSION_LOG" | tr -d ' ')
        echo "  $TOTAL hook block(s) recorded:"

        # Summarize by category
        jq -r '.category' "$SESSION_LOG" 2>/dev/null | sort | uniq -c | sort -rn | while read -r count cat; do
            echo "    $count × $cat"
        done

        # Append to durable ledger (one JSONL file, append-only)
        LEDGER="_private/docs/reference/error-ledger.jsonl"
        if [[ -d "_private/docs/reference" ]]; then
            cat "$SESSION_LOG" >> "$LEDGER"
            echo "  → appended to $LEDGER"
        fi

        # Check for emerging patterns (3+ same category = system problem)
        if [[ -f "$LEDGER" ]]; then
            echo ""
            echo "── pattern detection (all sessions) ──"
            PATTERNS=$(jq -r '.category' "$LEDGER" 2>/dev/null | sort | uniq -c | sort -rn | head -5)
            echo "$PATTERNS" | while read -r count cat; do
                if [[ "$count" -ge 3 ]]; then
                    echo "  ⚠ $cat ($count occurrences) — consider a hook fix (3-strike rule)"
                else
                    echo "    $cat ($count)"
                fi
            done
        fi

        # Clear session logs
        rm -f "$SESSION_LOG"
        rm -f ".claude/.session-reads"
        rm -f ".claude/.session-edits"
    else
        echo "  No hook blocks recorded"
    fi

    echo ""
    if [[ "$ERRORS" -gt 0 ]]; then
        echo "── Session end: ISSUES FOUND ──"
        echo "Fix before ending session:"
        echo "  Uncommitted changes → just git wip"
        echo "  Unpushed commits   → just git push-all"
        echo "  No MR              → just gitlab mr-create <repo>"
        exit 1
    else
        echo "── Session end: all clear ──"
    fi

# Install development dependencies (macOS via Homebrew + Cargo)
[group('setup')]
[script]
install-dev-deps:
    set -e

    echo "── Installing development dependencies ──"
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

    echo "── Done ──"
    echo ""
    echo "Optional (install manually if needed):"
    echo "  brew install kamal              # Relay deployment"
    echo "  brew install --cask android-studio  # Android SDK + emulator"
    echo ""
    echo "Next: just setup && just check"

# Configure sccache + mold for faster Rust builds (idempotent)
[group('setup')]
[script]
setup-fast-builds:
    set -euo pipefail

    CARGO_CONFIG="$HOME/.cargo/config.toml"
    CHANGED=0

    echo "── Configuring fast Rust builds ──"
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

# Create per-repo .cargo/config.toml with path overrides for local dev.
# These files are gitignored — CI resolves git deps from the remote.
# Run after `just setup` or when switching branches that changed core APIs.
[group('setup')]
[script]
setup-path-overrides:
    set -euo pipefail

    echo "── Setting up local Cargo path overrides ──"
    echo ""

    CORE_PATCH="[patch.'https://gitlab.com/vauchi/core.git']"
    CORE_DEP='vauchi-core = { path = "../core/vauchi-core" }'

    RELAY_PATCH="[patch.'https://gitlab.com/vauchi/relay.git']"
    RELAY_DEP='vauchi-relay = { path = "../relay" }'

    HEADER="# Auto-generated by: just setup-path-overrides
    # Local development path overrides — gitignored, not for CI."

    write_config() {
        local dir="$1"; shift
        mkdir -p "$dir/.cargo"
        local cfg="$dir/.cargo/config.toml"
        if [ -f "$cfg" ] && grep -q '\[patch\.' "$cfg" 2>/dev/null; then
            echo "  $dir (already configured)"
            return
        fi
        {
            echo "# Auto-generated by: just setup-path-overrides"
            echo "# Local development path overrides — gitignored, not for CI."
            echo ""
            for section in "$@"; do
                echo "$section"
            done
        } >> "$cfg"
        echo "  $dir (created)"
    }

    # Repos that depend on vauchi-core
    for dir in cli tui linux-gtk; do
        if [ -d "$dir" ]; then
            write_config "$dir" "$CORE_PATCH" "$CORE_DEP" ""
        fi
    done

    # e2e depends on both core and relay
    if [ -d "e2e" ]; then
        write_config "e2e" "$CORE_PATCH" "$CORE_DEP" "" "$RELAY_PATCH" "$RELAY_DEP" ""
    fi

    echo ""
    echo "Done. Path overrides point to local sibling repos (../core, ../relay)."
    echo "CI ignores these files — it resolves deps from git remotes."

# Clone all repositories
[private]
[script]
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
[script]
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
[script]
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
[script]
clean-rust:
    echo "Cleaning Rust targets..."
    for dir in core relay cli tui e2e linux-gtk web-demo/wasm; do
        if [[ -d "$dir/target" ]]; then
            echo "  $dir/target"
            rm -rf "$dir/target"
        fi
    done
    echo "Done!"
