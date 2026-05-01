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
    source scripts/scripts/for-each-repo.sh
    _fetch_repo() { local label="$1" dir="$2"; git -C "$dir" fetch --all --prune --quiet 2>/dev/null; }
    for_each_repo_parallel _fetch_repo
    echo "  All repos fetched + pruned"

    # Record repo HEADs for staleness check
    SESSION_HEADS=".claude/.session-heads"
    : > "$SESSION_HEADS"
    _record_head() {
        local label="$1" dir="$2"
        [[ "$dir" == "." ]] && label="root"
        local head
        head=$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo "unknown")
        echo "$label $head" >> "$SESSION_HEADS"
    }
    for_each_repo _record_head

    # ── Dashboard ──
    SI_TMP=$(mktemp -d)
    trap 'rm -rf "$SI_TMP"' EXIT

    # Open MRs (parallelize glab API calls)
    if command -v glab &>/dev/null && glab auth status &>/dev/null 2>&1; then
        source scripts/scripts/resolve-repo.sh
        _check_mrs() {
            local label="$1" dir="$2"
            [[ "$dir" == "." ]] && label="root"
            local gl_name mrs count
            gl_name=$(_dir_to_gitlab_name "$label")
            mrs=$(glab api "projects/vauchi%2F${gl_name}/merge_requests?state=opened&per_page=20" 2>/dev/null || true)
            count=$(echo "$mrs" | jq 'length' 2>/dev/null || echo "0")
            if [[ "$count" -gt 0 ]]; then
                echo "$mrs" | jq -r '.[] | (.iid | tostring) + "\t" + .title' 2>/dev/null \
                    | while IFS=$'\t' read -r iid title; do
                        echo "  $label !${iid}  ${title}" >> "$SI_TMP/mrs.txt"
                    done
            fi
        }
        for_each_repo_parallel _check_mrs
    fi

    echo ""
    echo "── dashboard ──"

    # Platform binding versions (Gate 8: frontend architecture audit 2026-03-18)
    echo ""
    echo "BINDING VERSIONS:"
    SWIFT_LATEST=""
    if [[ -d "vauchi-platform-swift" ]]; then
        # Use ls-remote to get the actual latest tag from origin, not just
        # what's reachable from the local HEAD (git describe fails when HEAD
        # is behind the latest tag).
        SWIFT_LATEST=$(git -C vauchi-platform-swift ls-remote --tags origin 2>/dev/null \
            | grep -v '\^{}' \
            | sed -n 's|.*refs/tags/v\([0-9][0-9.]*\)$|\1|p' \
            | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 || true)
        [[ -n "$SWIFT_LATEST" ]] && SWIFT_LATEST="v$SWIFT_LATEST" || SWIFT_LATEST="?"
    fi
    IOS_PIN=""
    if [[ -f "ios/project.yml" ]]; then
        IOS_PIN=$(yq -r '.packages.VauchiPlatform.version // .packages.VauchiPlatform.from' ios/project.yml 2>/dev/null || echo "?")
        [[ "$IOS_PIN" == "null" ]] && IOS_PIN="?"
    fi
    MACOS_PIN=""
    if [[ -f "macos/project.yml" ]]; then
        MACOS_PIN=$(yq -r '.packages.VauchiPlatform.version // .packages.VauchiPlatform.from' macos/project.yml 2>/dev/null || echo "?")
        [[ "$MACOS_PIN" == "null" ]] && MACOS_PIN="?"
    fi
    ANDROID_PIN=""
    if [[ -f "android/app/build.gradle.kts" ]]; then
        ANDROID_PIN=$(grep 'app\.vauchi:vauchi-platform:' android/app/build.gradle.kts 2>/dev/null | head -1 | sed 's/.*:\([0-9].*\)".*/\1/' || echo "?")
    fi
    echo "  platform-swift latest: ${SWIFT_LATEST:-?}"
    [[ -n "$IOS_PIN" ]] && echo "  iOS pinned:           $IOS_PIN"
    [[ -n "$MACOS_PIN" ]] && echo "  macOS pinned:         $MACOS_PIN"
    [[ -n "$ANDROID_PIN" ]] && echo "  Android pinned:       $ANDROID_PIN"
    # Staleness alert: warn if any platform differs from latest
    _check_binding_drift() {
        local label="$1" pin="$2"
        if [[ -n "$SWIFT_LATEST" && -n "$pin" && "$SWIFT_LATEST" != "?" && "$pin" != "?" ]]; then
            local latest_num="${SWIFT_LATEST#v}"
            local pin_num="${pin#v}"
            if [[ "$latest_num" != "$pin_num" ]]; then
                echo "  WARNING: $label ($pin) differs from latest ($SWIFT_LATEST)"
            fi
        fi
    }
    _check_binding_drift "iOS" "$IOS_PIN"
    _check_binding_drift "macOS" "$MACOS_PIN"
    _check_binding_drift "Android" "$ANDROID_PIN"

    echo ""
    echo "OPEN MRs:"
    if [[ -f "$SI_TMP/mrs.txt" && -s "$SI_TMP/mrs.txt" ]]; then
        sort "$SI_TMP/mrs.txt"
    else
        echo "  (none)"
    fi

    # Local branches, uncommitted changes, stashes — scan all repos in parallel
    _scan_repo_status() {
        local label="$1" d="$2"
        [[ "$d" == "." ]] && label="root"
        # Branches not on main
        local branches br age_date last_epoch now age_days marker status count scount
        branches=$(git -C "$d" branch --no-color 2>/dev/null | sed 's/^[* ]*//' | grep -v '^main$' || true)
        if [[ -n "$branches" ]]; then
            while IFS= read -r br; do
                [[ -z "$br" ]] && continue
                age_date=$(git -C "$d" log -1 --format=%ci "$br" 2>/dev/null | cut -d' ' -f1 || echo "?")
                last_epoch=$(git -C "$d" log -1 --format=%ct "$br" 2>/dev/null || echo "0")
                now=$(date +%s)
                age_days=$(( (now - last_epoch) / 86400 ))
                marker=""
                [[ "$age_days" -gt 14 ]] && marker=" STALE"
                echo "  $label ($br) last: $age_date (${age_days}d)$marker" >> "$SI_TMP/branches.txt"
            done <<< "$branches"
        fi
        # Uncommitted changes
        status=$(git -C "$d" status --porcelain 2>/dev/null || true)
        if [[ -n "$status" ]]; then
            count=$(echo "$status" | wc -l | tr -d ' ')
            echo "  $label: $count file(s) modified" >> "$SI_TMP/uncommitted.txt"
        fi
        # Gone branches (remote deleted, local has unmerged commits — forgotten MRs)
        while IFS= read -r gone_br; do
            [[ -z "$gone_br" ]] && continue
            echo "  $label ($gone_br) — remote GONE, local has unmerged commits" >> "$SI_TMP/gone.txt"
        done < <(git -C "$d" branch -vv --no-color 2>/dev/null \
            | grep ': gone\]' | sed 's/^[* ]*//' | awk '{print $1}' || true)
        # Stashes
        scount=$(git -C "$d" stash list 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$scount" -gt 0 ]]; then
            echo "  $label: $scount stash(es)" >> "$SI_TMP/stashes.txt"
        fi
    }
    for_each_repo_parallel _scan_repo_status

    echo ""
    echo "LOCAL BRANCHES (not main):"
    if [[ -s "$SI_TMP/branches.txt" ]]; then
        sort "$SI_TMP/branches.txt"
    else
        echo "  (none)"
    fi

    echo ""
    echo "UNCOMMITTED:"
    if [[ -s "$SI_TMP/uncommitted.txt" ]]; then
        sort "$SI_TMP/uncommitted.txt"
        WARN=1
    else
        echo "  (none)"
    fi

    if [[ -s "$SI_TMP/gone.txt" ]]; then
        echo ""
        echo "GONE BRANCHES (remote deleted, unmerged local commits — re-push or delete):"
        sort "$SI_TMP/gone.txt"
        WARN=1
    fi

    echo ""
    echo "STASHES:"
    if [[ -s "$SI_TMP/stashes.txt" ]]; then
        sort "$SI_TMP/stashes.txt"
        WARN=1
    else
        echo "  (none)"
    fi

    # Check for stale Cargo.toml branch refs (self-healing: prevents CI
    # breakage when a feature branch is merged upstream but downstream
    # Cargo.toml still tracks the deleted branch name).
    _STALE_REFS=""
    for dir in */; do
        [[ -e "${dir}.git" ]] || continue
        local_branch=$(git -C "${dir%/}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        [[ "$local_branch" == "main" ]] || continue
        cargo_file="${dir}Cargo.toml"
        [[ -f "$cargo_file" ]] || continue
        while IFS= read -r ref; do
            [[ -z "$ref" || "$ref" == "main" ]] && continue
            _STALE_REFS+="  ${dir%/}: branch = \"$ref\" (expected \"main\")\n"
            WARN=1
        done < <(taplo get -f "$cargo_file" -o json 2>/dev/null \
                 | jq -r '.. | .branch? // empty' | sort -u)
    done
    if [[ -n "$_STALE_REFS" ]]; then
        echo ""
        echo "STALE CARGO BRANCH REFS (CI may be broken):"
        printf '%b' "$_STALE_REFS"
    fi

    # Sweep stale Cargo incremental artifacts (prevents unbounded growth).
    # Two-pass strategy:
    #   1. Time-based: remove artifacts older than 2 days (keeps same-day builds fast)
    #   2. Size-based: if any target/ exceeds 20 GB, aggressively sweep to 1 day
    # This is self-healing — even without manual cleanup, targets stay bounded.
    if command -v cargo-sweep &>/dev/null; then
        echo ""
        echo "SWEEP (cargo artifacts):"
        total_freed=0
        for dir in $(repos_by_toolchain rust); do
            [[ -d "$dir/target" ]] || continue
            before=$(du -sm "$dir/target" 2>/dev/null | cut -f1)
            # Pass 1: time-based (2 days)
            cargo sweep --time 2 "$dir" 2>/dev/null
            after=$(du -sm "$dir/target" 2>/dev/null | cut -f1)
            # Pass 2: if still over 20 GB, sweep more aggressively (1 day)
            if [[ $after -gt 20480 ]]; then
                cargo sweep --time 1 "$dir" 2>/dev/null
                after=$(du -sm "$dir/target" 2>/dev/null | cut -f1)
            fi
            freed=$((before - after))
            total_freed=$((total_freed + freed))
            [[ $freed -gt 100 ]] && echo "  $dir: freed ${freed} MB (${before} → ${after} MB)"
        done
        if [[ $total_freed -gt 100 ]]; then
            echo "  Total freed: ${total_freed} MB"
        else
            echo "  (clean — <100 MB to sweep)"
        fi
    fi

    # ── Active claims (atomic locks on work items) ──
    if command -v glab &>/dev/null && glab auth status &>/dev/null 2>&1; then
        MY_SESSION=$(printf '%s:%s' "$(hostname -s)" "${CLAUDE_PROJECT_DIR:-$(pwd)}" | shasum -a 256 | cut -c1-12)
        CLAIMS=$(glab api "projects/vauchi%2Fprivate/repository/branches?search=claim/" 2>/dev/null \
            | tr -d '\000-\010\013-\037' \
            | jq '[.[] | {name: .name, msg: .commit.message}]' 2>/dev/null \
            || echo "[]")
        CLAIM_COUNT=$(echo "$CLAIMS" | jq 'length' 2>/dev/null || echo "0")
        if [[ "$CLAIM_COUNT" -gt 0 ]]; then
            echo ""
            echo "ACTIVE CLAIMS (do not duplicate this work):"
            echo "$CLAIMS" | jq -c '.[]' | while IFS= read -r b; do
                NAME=$(echo "$b" | jq -r '.name' | sed 's|^claim/||')
                MSG=$(echo "$b" | jq -r '.msg // ""')
                OWNER=$(echo "$MSG" | grep -oE 'session:[a-f0-9]+' | cut -d: -f2 || true)
                MARKER=""
                [[ "${OWNER:-}" == "$MY_SESSION" ]] && MARKER=" ← you"
                echo "  ⚡ $NAME (session:${OWNER:-unknown}${MARKER})"
            done
        fi
    fi

    # ── Work board ──
    echo ""
    echo "── work board ──"
    BOARD="_private/docs/work-board.md"
    if [[ -f "$BOARD" ]]; then
        IN_PROGRESS=$(sed -n '/^## In Progress$/,/^## /{ /^## /d; /^$/d; /^<!--/d; p; }' "$BOARD")
        if [[ -n "$IN_PROGRESS" ]]; then
            echo "IN PROGRESS:"
            echo "$IN_PROGRESS" | while IFS= read -r line; do echo "  $line"; done
        fi
        NEXT=$(sed -n '/^## v0\.5\.0 Next$/,/^## /{ /^## /d; /^$/d; p; }' "$BOARD" | head -5)
        if [[ -n "$NEXT" ]]; then
            echo "NEXT:"
            echo "$NEXT" | while IFS= read -r line; do echo "  $line"; done
        fi
        BLOCKED=$(sed -n '/^## v0\.5\.0 Blocked$/,/^## /{ /^## /d; /^$/d; p; }' "$BOARD")
        if [[ -n "$BLOCKED" ]]; then
            echo "BLOCKED:"
            echo "$BLOCKED" | while IFS= read -r line; do echo "  $line"; done
        fi
    else
        echo "  (no work board at $BOARD)"
    fi

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
    SE_TMP=$(mktemp -d)
    trap 'rm -rf "$SE_TMP"' EXIT

    # Source resolve-repo for MR check (if available)
    GLAB_OK=0
    if command -v glab &>/dev/null && glab auth status &>/dev/null 2>&1; then
        source scripts/scripts/resolve-repo.sh
        GLAB_OK=1
    fi

    # Scan all repos in parallel: uncommitted, unpushed, orphan branches
    source scripts/scripts/for-each-repo.sh
    _check_session_end() {
        local label="$1" d="$2"
        [[ "$d" == "." ]] && label="root"
        # Uncommitted changes
        local status branch ahead gl_name mr_count
        status=$(git -C "$d" status --porcelain 2>/dev/null || true)
        if [[ -n "$status" ]]; then
            {
                echo "  ERROR: $label has uncommitted changes"
                git -C "$d" status --short 2>/dev/null | while IFS= read -r line; do echo "    $line"; done
            } >> "$SE_TMP/uncommitted.txt"
        fi
        # Unpushed commits
        branch=$(git -C "$d" branch --show-current 2>/dev/null)
        if [[ -n "$branch" ]]; then
            ahead=$(git -C "$d" rev-list --count "@{u}..HEAD" 2>/dev/null || echo "0")
            if [[ "$ahead" -gt 0 ]]; then
                echo "  ERROR: $label ($branch) has $ahead unpushed commit(s)" >> "$SE_TMP/unpushed.txt"
            fi
        fi
        # Branches without MRs
        if [[ "$GLAB_OK" == "1" && "$branch" != "main" && -n "$branch" ]]; then
            gl_name=$(_dir_to_gitlab_name "$label")
            mr_count=$(glab api "projects/vauchi%2F${gl_name}/merge_requests?state=opened&source_branch=${branch}&per_page=1" 2>/dev/null \
                | jq 'length' 2>/dev/null || echo "0")
            if [[ "$mr_count" == "0" ]]; then
                echo "  WARN: $label ($branch) has no open MR" >> "$SE_TMP/orphan.txt"
            fi
        fi
    }
    for_each_repo_parallel _check_session_end

    echo ""
    echo "── uncommitted changes ──"
    if [[ -s "$SE_TMP/uncommitted.txt" ]]; then
        cat "$SE_TMP/uncommitted.txt"
        ERRORS=1
    else
        echo "  All clean"
    fi

    echo ""
    echo "── unpushed commits ──"
    if [[ -s "$SE_TMP/unpushed.txt" ]]; then
        sort "$SE_TMP/unpushed.txt"
        ERRORS=1
    else
        echo "  All pushed"
    fi

    echo ""
    echo "── branches without MRs ──"
    if [[ -s "$SE_TMP/orphan.txt" ]]; then
        sort "$SE_TMP/orphan.txt"
    else
        echo "  All branches have MRs (or on main)"
    fi

    # Process session error log (from hooks that blocked)
    echo ""
    echo "── hook errors this session ──"
    SESSION_LOG=".claude/.session-errors"
    if [[ -f "$SESSION_LOG" && -s "$SESSION_LOG" ]]; then
        TOTAL=$(wc -l < "$SESSION_LOG" | tr -d ' ')
        echo "  $TOTAL hook block(s) recorded:"

        # Summarize by category. `jq -R 'fromjson?'` skips malformed lines
        # silently so one bad entry can't kill the whole pipeline under
        # `set -euo pipefail` and leave the log uncleared next session.
        # `|| true` on each sub-pipeline guards the same failure path.
        (jq -rR 'fromjson? | .category' "$SESSION_LOG" 2>/dev/null \
            | sort | uniq -c | sort -rn \
            | while read -r count cat; do echo "    $count × $cat"; done) || true

        # Append to durable ledger (one JSONL file, append-only).
        # Malformed lines are appended verbatim — the ledger is for forensics,
        # not programmatic reads.
        LEDGER="_private/docs/reference/error-ledger.jsonl"
        if [[ -d "_private/docs/reference" ]]; then
            cat "$SESSION_LOG" >> "$LEDGER"
            echo "  → appended to $LEDGER"
        fi

        # Check for emerging patterns (3+ same category = system problem)
        if [[ -f "$LEDGER" ]]; then
            echo ""
            echo "── pattern detection (all sessions) ──"
            PATTERNS=$(jq -rR 'fromjson? | .category' "$LEDGER" 2>/dev/null \
                | sort | uniq -c | sort -rn | head -5 || true)
            echo "$PATTERNS" | while read -r count cat; do
                if [[ -z "$count" || -z "$cat" ]]; then continue; fi
                if [[ "$count" -ge 3 ]] 2>/dev/null; then
                    echo "  ⚠ $cat ($count occurrences) — consider a hook fix (3-strike rule)"
                else
                    echo "    $cat ($count)"
                fi
            done
        fi

        # Clear session logs — must always run so a malformed line in one
        # session doesn't lock the log forever.
        rm -f "$SESSION_LOG"
        rm -f ".claude/.session-reads"
        rm -f ".claude/.session-edits"
    else
        echo "  No hook blocks recorded"
    fi

    # ── Work board claim check ──
    echo ""
    echo "── work board claims ──"
    BOARD="_private/docs/work-board.md"
    if [[ -f "$BOARD" ]]; then
        IN_PROGRESS=$(sed -n '/^## In Progress$/,/^## /{ /^## /d; /^$/d; /^<!--/d; p; }' "$BOARD")
        if [[ -n "$IN_PROGRESS" ]]; then
            echo "  Items still In Progress on the board:"
            echo "$IN_PROGRESS" | while IFS= read -r line; do
                echo "    $line"
            done
            echo "  → Release or move them before ending session"
        else
            echo "  No active claims"
        fi
    fi

    # ── Doc staleness check ──
    echo ""
    echo "── doc staleness check ──"
    SESSION_HEADS=".claude/.session-heads"
    if [[ -f "$SESSION_HEADS" ]]; then
        CHANGED_REPOS=""
        while IFS=' ' read -r label old_head; do
            [[ "$label" == "root" ]] && dir="." || dir="$label"
            [[ -d "$dir/.git" ]] || continue
            new_head=$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo "unknown")
            if [[ "$old_head" != "$new_head" ]]; then
                CHANGED_REPOS="$CHANGED_REPOS $label"
            fi
        done < "$SESSION_HEADS"

        if [[ -n "$CHANGED_REPOS" ]]; then
            echo "  Changed repos:$CHANGED_REPOS"
            MATCHES=""
            for repo in $CHANGED_REPOS; do
                [[ "$repo" == "root" || "$repo" == "_private" ]] && continue
                while IFS= read -r f; do
                    MATCHES="$MATCHES  $f (references $repo/)\n"
                done < <(grep -rl "${repo}/" \
                    _private/docs/problems/*/README.md \
                    _private/docs/planning/todo/*.md 2>/dev/null \
                    | grep -v '/done/' \
                    | head -5)
            done
            if [[ -n "$MATCHES" ]]; then
                echo "  Docs referencing changed repos — review for staleness:"
                printf '%b' "$MATCHES" | head -10
            else
                echo "  No matching docs found"
            fi
        else
            echo "  No repos changed this session"
        fi
    else
        echo "  (no session heads — run session-init first)"
    fi

    # ── Disk pressure ──
    # Warn at >=90% — past that, agents start hitting "disk full" writing
    # to /tmp and Xcode/SPM rebuilds get unpredictable. Survey + reclaim
    # via `just disk` / `just disk-clean`.
    echo ""
    echo "── disk pressure ──"
    USE_PCT=$(df -P . 2>/dev/null | awk 'NR==2 {gsub("%",""); print $5}')
    if [[ -z "${USE_PCT:-}" ]]; then
        echo "  (could not read disk usage)"
    elif [[ "$USE_PCT" -ge 90 ]] 2>/dev/null; then
        AVAIL=$(df -h . 2>/dev/null | awk 'NR==2 {print $4}')
        echo "  WARN: workspace filesystem ${USE_PCT}% full (${AVAIL} free)"
        echo "  → \`just disk\` to survey, \`just disk-clean\` to reclaim"
    else
        echo "  ${USE_PCT}% used (OK)"
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

# Generate a draft PreToolUse hook from observed patterns in
# .claude/.session-errors. Use after session-end flags a category
# under the 3-strike rule.
[group('setup')]
gen-hook-from-pattern category="" force="":
    @bash scripts/scripts/gen-hook-from-pattern.sh {{category}} {{force}}

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
    cargo_tools=(cargo-watch cargo-audit cargo-deny cargo-llvm-cov sccache cargo-duplicates cargo-bloat cargo-sweep typos-cli)
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

    # ── npm global tools ────────────────────────────────────────────
    echo "── npm global tools ──"
    npm_tools=(markdownlint-cli)
    for tool in "${npm_tools[@]}"; do
        # npm ls -g exits non-zero if not found
        if npm ls -g "$tool" &>/dev/null; then
            echo "  $tool (already installed)"
        else
            echo "  Installing $tool..."
            npm i -g "$tool"
        fi
    done
    echo ""

    # ── REUSE (SPDX header compliance) ──────────────────────────────
    echo "── REUSE tool ──"
    if command -v reuse &>/dev/null; then
        echo "  reuse (already installed)"
    else
        echo "  Installing reuse..."
        if command -v pipx &>/dev/null; then
            pipx install reuse
        elif command -v brew &>/dev/null; then
            brew install reuse
        elif command -v pip3 &>/dev/null; then
            pip3 install --user reuse
        else
            echo "  SKIP: no pipx/brew/pip3 — install manually: pipx install reuse"
        fi
    fi
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
    APP_DEP='vauchi-app = { path = "../core/vauchi-app" }'
    PROTOCOL_DEP='vauchi-protocol = { path = "../core/vauchi-protocol" }'

    RELAY_PATCH="[patch.'https://gitlab.com/vauchi/relay.git']"
    RELAY_DEP='vauchi-relay = { path = "../relay" }'

    HEADER="# Auto-generated by: just setup-path-overrides
    # Local development path overrides — gitignored, not for CI."

    write_config() {
        local dir="$1"
        shift
        mkdir -p "$dir/.cargo"
        local cfg="$dir/.cargo/config.toml"
        # Always regenerate — file is auto-generated and gitignored.
        # Previous skip-if-exists logic caused stale configs when new
        # patches were added (vauchi-app was missing from cli/tui).
        echo "# Auto-generated by: just setup-path-overrides" > "$cfg"
        echo "# Local development path overrides — gitignored, not for CI." >> "$cfg"
        echo "" >> "$cfg"
        for section in "$@"
        do
            echo "$section" >> "$cfg"
        done
        echo "  $dir (updated)"
    }

    # Repos that depend on vauchi-core + vauchi-app
    for dir in cli tui linux-gtk; do
        if [ -d "$dir" ]; then
            write_config "$dir" "$CORE_PATCH" "$CORE_DEP" "$APP_DEP" ""
        fi
    done

    # web-demo/wasm depends on vauchi-core + vauchi-app (nested Cargo workspace)
    if [ -d "web-demo/wasm" ]; then
        WASM_CORE='vauchi-core = { path = "../../core/vauchi-core" }'
        WASM_APP='vauchi-app = { path = "../../core/vauchi-app" }'
        write_config "web-demo/wasm" "$CORE_PATCH" "$WASM_CORE" "$WASM_APP" ""
    fi

    # relay depends on vauchi-protocol (from core git URL)
    if [ -d "relay" ]; then
        write_config "relay" "$CORE_PATCH" "$PROTOCOL_DEP" ""
    fi

    # e2e depends on both core and relay
    if [ -d "e2e" ]; then
        write_config "e2e" "$CORE_PATCH" "$CORE_DEP" "$APP_DEP" "" "$RELAY_PATCH" "$RELAY_DEP" ""
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

    # Rust targets (repos + nested wasm workspace)
    source scripts/scripts/resolve-repo.sh
    for dir in $(repos_by_toolchain rust) web-demo/wasm; do
        if [[ -d "$dir/target" ]]; then
            echo "  Cleaning $dir/target"
            rm -rf "$dir/target"
        fi
    done

    # Node modules and build outputs
    for dir in website web-demo; do
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
    source scripts/scripts/resolve-repo.sh
    echo "Cleaning Rust targets..."
    for dir in $(repos_by_toolchain rust) web-demo/wasm; do
        if [[ -d "$dir/target" ]]; then
            echo "  $dir/target"
            rm -rf "$dir/target"
        fi
    done
    echo "Done!"

# Compact git repos — aggressive gc on repos with large binary history.
# Binding repos (kotlin, ios, swift) accumulate native binaries (.so, .a)
# across releases. git gc reduces pack size ~30%.
[group('setup')]
[script]
git-compact:
    set -euo pipefail
    echo "── Compacting git repos ──"
    source scripts/scripts/for-each-repo.sh
    # Only gc repos >50MB — small repos don't benefit
    _compact_repo() {
        local label="$1" dir="$2"
        local size_kb size_mb new_kb new_mb freed
        size_kb=$(du -sk "${dir}/.git" 2>/dev/null | cut -f1)
        size_mb=$((size_kb / 1024))
        if [[ $size_mb -gt 50 ]]; then
            echo -n "  $label (${size_mb} MB) → "
            git -C "$dir" gc --aggressive --prune=now 2>/dev/null
            new_kb=$(du -sk "${dir}/.git" 2>/dev/null | cut -f1)
            new_mb=$((new_kb / 1024))
            freed=$((size_mb - new_mb))
            echo "${new_mb} MB (freed ${freed} MB)"
        fi
    }
    for_each_repo --no-root _compact_repo
    echo "Done!"

# Lint shell scripts for portability (shellcheck + GNU/BSD pattern checker)
[group('setup')]
[script]
shell-lint *files:
    set -euo pipefail
    ROOT="{{justfile_directory()}}"

    if [[ -z "{{ files }}" ]]; then
        echo "Scanning all .sh and .just files..."
        mapfile -t targets < <(find "$ROOT" -name '*.sh' -not -path '*/.git/*' -not -path '*/target/*' -not -path '*/node_modules/*' | sort)
        mapfile -t just_targets < <(find "$ROOT/just" -name '*.just' -not -path '*/.git/*' | sort)
        targets+=("${just_targets[@]}")
    else
        IFS=' ' read -ra targets <<< "{{ files }}"
    fi

    ERRORS=0

    # shellcheck (language-level portability)
    if command -v shellcheck &>/dev/null; then
        echo "── shellcheck ──"
        for f in "${targets[@]}"; do
            [[ "$f" == *.sh || "$f" == *.bash ]] || continue
            [[ -f "$f" ]] || continue
            if ! shellcheck -S warning "$f" 2>&1; then
                ERRORS=$((ERRORS + 1))
            fi
        done
        echo "  shellcheck done"
    else
        echo "  (shellcheck not installed — brew install shellcheck)"
    fi

    # Custom GNU/BSD portability checks
    echo "── portable-shell ──"
    if ! "$ROOT/scripts/hooks/check-portable-shell.sh" "${targets[@]}"; then
        ERRORS=$((ERRORS + 1))
    fi

    if [[ "$ERRORS" -gt 0 ]]; then
        echo ""
        echo "Shell lint found issues. See .claude/rules/portable-shell.md"
        exit 1
    fi
    echo ""
    echo "All shell scripts portable ✓"
