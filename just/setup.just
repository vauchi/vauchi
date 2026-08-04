# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Setup & maintenance recipes

# Verify Codex skill discovery avoids a sandbox-incompatible root symlink.
[group('tests')]
test-codex-layout:
    python3 "{{justfile_directory()}}/tests/test_codex_layout.py" "{{justfile_directory()}}"

# Verify the .claude layout gate flags real strays and only real strays.
[group('tests')]
test-claude-layout:
    python3 "{{justfile_directory()}}/tests/test_claude_layout.py" "{{justfile_directory()}}"

# Check that required tools are installed before setup
[group('setup')]
check-prerequisites:
    @source just/check-prerequisites.sh

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

    # Claude config layout (.claude symlink → _private/.claude)
    echo ""
    echo "── claude config ──"
    source just/claude-layout-lib.sh
    if check_claude_layout; then
        echo "  OK: .claude → _private/.claude"
    else
        WARN=1
    fi

    # Codex config layout (.codex real dir → symlinks into _private/.codex).
    # Deliberately the opposite shape to .claude: a symlinked .codex makes
    # bubblewrap refuse to start, breaking every sandboxed Codex command.
    echo ""
    echo "── codex config ──"
    source just/codex-layout-lib.sh
    if check_codex_layout; then
        echo "  OK: .codex dir → _private/.codex entries"
    else
        WARN=1
    fi

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

    # ── Path overrides health check ──
    # Verify that local cargo invocations actually resolve vauchi-core /
    # vauchi-app / vauchi-protocol / vauchi-relay to sibling repos and
    # not to the git rev pinned in Cargo.lock. A silent miss here means
    # every "verified locally in TUI/CLI/linux-gtk" claim is false.
    # See `2026-05-03-cargo-path-override-broken`.
    echo ""
    echo "── path overrides ──"
    if [[ -x scripts/scripts/path-overrides.sh ]]; then
        if ! bash scripts/scripts/path-overrides.sh check >/dev/null 2>&1; then
            echo "  WARNING: vauchi-* deps not resolving via path overrides."
            echo "  → run: just setup-path-overrides"
            WARN=1
        else
            echo "  OK: all consumers resolve vauchi-* via local paths"
        fi
        # Freshness check: surface drift between local override sources
        # (core/, relay/) and origin/main. Stale shipped APIs are how
        # "local-passes / CI-fails" silent breaks survive — the same
        # pathology that hid Wire Humble Tier 0 until cli/tui auto-vet
        # surfaced it on CI. Advisory only; show output verbatim so
        # WARN lines + recovery hints reach the developer.
        bash scripts/scripts/path-overrides.sh freshness 2>/dev/null \
            | sed 's/^/  /'
    else
        echo "  (path-overrides.sh missing — scripts/ out of date?)"
    fi

    # ── Deployed-service drift ──
    # Runs after fetch so origin/main is current. Advisory here (WARN,
    # not abort): the alarm exists because a stale docs deploy sat
    # unnoticed for 10 weeks (backlog 2026-07-10-docs-deploy-drift-alarm).
    echo ""
    echo "── deployed services ──"
    just deploy-check || WARN=1

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
        # Board uses priority-tiered headers since 2026-04 restructure:
        # `## Blocked`, `## CRITICAL — Next`, `## HIGH — Next`,
        # `## MEDIUM — Next`, `## LOW — Next`. NEXT aggregates
        # CRITICAL+HIGH `- [ ]` items including their indented
        # continuation lines (top of file = highest priority).
        # Limit lives INSIDE awk: `| head -10` closed the pipe early,
        # awk died with SIGPIPE (141), and pipefail+set -e killed the
        # whole session-init once NEXT grew past 10 lines.
        NEXT=$(awk '
            /^## (CRITICAL|HIGH) — Next$/ { p=1; next }
            /^## / { p=0 }
            !p { next }
            /^- \[ \]/ { if (++items > 10) exit; emit=1; print; next }
            emit && /^  / { print; next }
            { emit=0 }
        ' "$BOARD")
        if [[ -n "$NEXT" ]]; then
            echo "NEXT:"
            echo "$NEXT" | while IFS= read -r line; do echo "  $line"; done
        fi
        BLOCKED=$(awk '
            /^## Blocked$/ { p=1; next }
            /^## / { p=0 }
            !p { next }
            /^- \[ \]/ { emit=1; print; next }
            emit && /^  / { print; next }
            { emit=0 }
        ' "$BOARD")
        if [[ -n "$BLOCKED" ]]; then
            echo "BLOCKED:"
            echo "$BLOCKED" | while IFS= read -r line; do echo "  $line"; done
        fi
        # Sanity guard (CC-21): if board has `- [ ]` items but the
        # parser finds none, the headers may have changed again.
        TOTAL=$(grep -c '^- \[ \] ' "$BOARD" || true)
        if [[ "$TOTAL" -gt 0 && -z "$NEXT" && -z "$BLOCKED" ]]; then
            echo "  WARN: board has $TOTAL items but parser found none — check headers in $BOARD"
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

    # VGT05: claim-format check (warn-only at session end; _private CI
    # enforces). Page: _private/docs/lint-errors/vgt05-work-board-claims.md
    if [[ -x scripts/scripts/check-work-board.sh ]]; then
        scripts/scripts/check-work-board.sh || \
            echo "  WARN: work-board claim format issues (see above)"
    fi

    # VHC01: AI-harness config parity (warn at session-end; root CI enforces).
    # Page: _private/docs/lint-errors/vhc01-harness-parity.md
    if [[ -x scripts/scripts/check-harness-parity.sh ]]; then
        scripts/scripts/check-harness-parity.sh . || \
            echo "  WARN: harness config parity issues (see above)"
    fi

    # VIC01: shared .idea config hygiene (warn at session-end; root CI enforces).
    # Page: _private/docs/lint-errors/vic01-idea-config-hygiene.md
    if [[ -x scripts/scripts/check-idea-config.sh ]]; then
        scripts/scripts/check-idea-config.sh . || \
            echo "  WARN: .idea config hygiene issues (see above)"
    fi

    # VSP01: stale ci-template pins (warn at session-end; root CI enforces).
    # Page: _private/docs/lint-errors/vsp01-stale-ci-template-pin.md
    if [[ -x scripts/scripts/check-stale-ci-pin.sh ]]; then
        SE_RECENT="$SE_TMP/recent-ci-tags.txt"
        git -C scripts tag --sort=-v:refname 2>/dev/null | grep '^ci-templates-v' | head -8 > "$SE_RECENT" 2>/dev/null || true
        if [[ -s "$SE_RECENT" ]]; then
            while IFS= read -r _yaml; do
                scripts/scripts/check-stale-ci-pin.sh "$_yaml" "$SE_RECENT" "$_yaml" || \
                    echo "  WARN: stale ci-template pin in $_yaml (see above)"
            done < <(sh just/discover-ci-pipelines.sh .)
        fi
    fi

    # VFL01: flaky-quarantine SLA (warn at session-end; scheduled CI enforces).
    # Page: _private/docs/lint-errors/vfl01-flaky-sla.md
    if [[ -x scripts/scripts/check-flaky-sla.sh ]]; then
        for _repo in core cli tui e2e relay linux-gtk; do
            if [[ -d "$_repo" ]]; then
                scripts/scripts/check-flaky-sla.sh "$_repo" || \
                    echo "  WARN: flaky-SLA issues in $_repo (see above)"
            fi
        done
    fi

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
            # Path-override churn (fenced Cargo.toml + lock rewrite) is
            # documented persistent local-dev state — the pre-commit hook
            # refuses to commit it, so demanding a clean tree here only
            # trains bypasses (see 2026-06-11-session-end-override-false-
            # positives). Content-verified by the filter; missing filter
            # falls back to strict.
            if scripts/scripts/override-only-changes.sh "$d" >/dev/null 2>&1; then
                echo "  $label: path-override churn only (local-dev state, not committable)" >> "$SE_TMP/override-only.txt"
            else
                {
                    echo "  ERROR: $label has uncommitted changes"
                    git -C "$d" status --short 2>/dev/null | while IFS= read -r line; do echo "    $line"; done
                } >> "$SE_TMP/uncommitted.txt"
            fi
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
    if [[ -s "$SE_TMP/override-only.txt" ]]; then
        sort "$SE_TMP/override-only.txt"
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

        # Check for emerging patterns (3+ same category = system problem).
        # The ledger is append-only — cumulative counts grow forever, so a
        # bare "14071 occurrences" tells you nothing about whether the hook
        # is working. Cross-reference each category against installed hooks
        # and add today's count: trajectory > tally. Categories without a
        # hook still get the "consider a hook fix" warning.
        if [[ -f "$LEDGER" ]]; then
            echo ""
            echo "── pattern detection (all sessions) ──"

            # Category → hook filename. Empty means no hook is installed
            # for that pattern yet (the 3-strike warning still fires).
            _hook_for_category() {
                case "$1" in
                    excessive-reread) echo "pretool-read-cap.sh" ;;
                    excessive-reedit) echo "pretool-edit-cap.sh" ;;
                    wrong-tool)       echo "check-bash-grep.sh" ;;
                    cwd-drift)        echo "check-cd-git.sh" ;;
                    read-nudge)       echo "pre-read-nudge.sh" ;;
                    raw-cargo|raw-glab|raw-mv-archive) echo "check-use-just.sh" ;;
                    *) echo "" ;;
                esac
            }

            PATTERNS=$(jq -rR 'fromjson? | select(.category != null) | .category' "$LEDGER" 2>/dev/null \
                | sort | uniq -c | sort -rn | head -5 || true)
            echo "$PATTERNS" | while read -r count cat; do
                if [[ -z "$count" || -z "$cat" ]]; then continue; fi
                today=0
                if [[ -f "$SESSION_LOG" ]]; then
                    today=$(jq -rR --arg c "$cat" \
                        'fromjson? | select(.category == $c) | 1' \
                        "$SESSION_LOG" 2>/dev/null | wc -l | tr -d ' ')
                fi
                hook=$(_hook_for_category "$cat")
                if [[ -n "$hook" && -f ".claude/hooks/$hook" ]]; then
                    echo "  • $cat ($count cumulative, $today today) — hook active: $hook"
                elif [[ "$count" -ge 3 ]] 2>/dev/null; then
                    echo "  ⚠ $cat ($count cumulative, $today today) — consider a hook fix (3-strike rule)"
                else
                    echo "    $cat ($count cumulative, $today today)"
                fi
            done
        fi

        # Clear session logs — must always run so a malformed line in one
        # session doesn't lock the log forever.
        rm -f "$SESSION_LOG"
        rm -f ".claude/.session-reads"
        rm -f ".claude/.session-edits"
        rm -f ".claude/.session-reads-meta"
    else
        echo "  No hook blocks recorded"
    fi

    # ── Work board claim check ──
    # Only `- [ ]` / `- [x]` items count as claims. Prose like
    # "(none — ...)" inside the In Progress section is a status comment
    # written by maintainers and must NOT be reported as an active claim.
    echo ""
    echo "── work board claims ──"
    BOARD="_private/docs/work-board.md"
    if [[ -f "$BOARD" ]]; then
        IN_PROGRESS=$(sed -n '/^## In Progress$/,/^## /p' "$BOARD" \
            | grep -E '^- \[[ x]\]' || true)
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
                    _private/docs/backlog/*/README.md \
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

    # ── Backlog review ──
    # Advisory count of backlog items. Staleness is checked by drift detection.
    echo ""
    echo "── backlog ──"
    BACKLOG_COUNT=$(find _private/docs/backlog -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    echo "  $BACKLOG_COUNT problem records in backlog"

    # ── Intake backlog ──
    # CLAUDE.md alert threshold: 5+ problems in intake. Advisory, not an
    # ERRORS gate — gating session exit on triage debt would only train
    # ignoring the gate. Matches table (| **Status** | intake |), heading
    # (## Status: intake), and bold-colon (**Status**: intake) forms.
    echo ""
    echo "── intake backlog ──"
    INTAKE_COUNT=$( (grep -liE '^(\| *)?(#+ *)?(\*\*)?status(\*\*)? *[|:] *`?intake' \
        _private/docs/problems/*/README.md 2>/dev/null || true) | wc -l | tr -d ' ')
    if [[ "$INTAKE_COUNT" -ge 5 ]]; then
        echo "  $INTAKE_COUNT problem records in intake (alert threshold: 5)"
        echo "  → triage into a lifecycle phase, defer, or reject"
    else
        echo "  OK ($INTAKE_COUNT in intake)"
    fi

    # ── Work board size ──
    # Advisory. 1200-line threshold calibrated to the 941-line live floor
    # measured 2026-06-11 after the first Done-section archive pass.
    echo ""
    echo "── work board size ──"
    BOARD_LINES=$(wc -l < "$BOARD" 2>/dev/null || echo 0)
    if [[ "$BOARD_LINES" -gt 1200 ]]; then
        echo "  work-board.md: ${BOARD_LINES} lines (>1200)"
        echo "  → archive old '## Done' entries to work-board-archive.md"
    else
        echo "  OK (${BOARD_LINES} lines)"
    fi

    # ── Claude config layout ──
    echo ""
    echo "── claude config layout ──"
    source just/claude-layout-lib.sh
    if check_claude_layout; then
        echo "  OK: .claude → _private/.claude, no strays"
    else
        ERRORS=1
    fi

    # ── Codex config layout ──
    # Gates the shape, not just the contents: a session that left .codex as a
    # symlink hands the next Codex run a sandbox that cannot start at all.
    echo ""
    echo "── codex config layout ──"
    source just/codex-layout-lib.sh
    if check_codex_layout; then
        echo "  OK: .codex dir → _private/.codex entries, no strays"
    else
        ERRORS=1
    fi

    # ── CLAUDE.md ↔ .claude/docs consistency ──
    # Replaces the retired root-repo CI job lint:claude-md: root CI
    # checkouts no longer contain .claude (it lives in _private), so
    # the workspace — the only place both sides exist — runs the check.
    echo ""
    echo "── claude-md references ──"
    if CMD_OUT=$(./scripts/scripts/check-claude-md.sh 2>&1); then
        echo "  OK"
    else
        echo "$CMD_OUT" | sed 's/^/  /' | head -20
        ERRORS=1
    fi

    # ── subagent-spawn signal (observe-only, never an error) ──
    # Subagent tokens are the top cost driver yet invisible per session
    # (log-subagent-spawn.sh tallies them). Surface the count so a heavy
    # session is noticed live; weekly cost trend is `just token-report`.
    SE_LEDGER=".claude/.session-errors"
    if [[ -f "$SE_LEDGER" ]]; then
        SPAWNS=$(grep -c '"category":"subagent-spawn"' "$SE_LEDGER" 2>/dev/null || true)
        SPAWNS=${SPAWNS:-0}
        if [[ "$SPAWNS" -gt 0 ]]; then
            echo ""
            echo "── subagent spawns this session: $SPAWNS ──"
            grep '"category":"subagent-spawn"' "$SE_LEDGER" 2>/dev/null \
                | jq -r '.agent' 2>/dev/null | sort | uniq -c | sort -rn | head -6 \
                | while read -r n a; do echo "    $n  $a"; done
            echo "  Heavy? Check per-week cost with: just token-report"
        fi
    fi

    # ── intervention ledger (observe-only; meta-churn direction 0) ──
    # Evidence base ranking the 2026-07-21 audit records:
    # _private/docs/backlog/2026-07-21-process-meta-churn-ratio.md
    IL="_private/docs/intervention-ledger.md"
    if [[ -f "$IL" ]]; then
        WEEK_AGO=$(date -d '7 days ago' +%F 2>/dev/null || date -v-7d +%F)
        N7=$(awk -v w="$WEEK_AGO" '/^- 20[0-9][0-9]-/{if ($2 >= w) n++} END{print n+0}' "$IL")
        echo ""
        echo "── intervention ledger: $N7 entries in last 7 days ──"
        echo "  Maintainer interruptions beyond normal feature work this"
        echo "  session? Append one line each, no quotes needed:"
        echo "    just ledger <fanout|vet|gate|other> <lt5m|5-30m|gt30m>"
        echo "         <authoring|retry|review|wait>"
        echo "         <prevented-defect|mechanical|false-positive> [note...]"
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

# Append one line to the maintainer intervention ledger
# (_private/docs/intervention-ledger.md) — the evidence base for
# _private/docs/backlog/2026-07-21-process-meta-churn-ratio.md
# (direction 0). Note words need no quotes:
#   just ledger vet 5-30m retry mechanical exemption resync flapped
[group('setup')]
[script]
ledger area bucket kind outcome *note:
    set -euo pipefail
    LEDGER="_private/docs/intervention-ledger.md"
    case "{{ area }}" in fanout|vet|gate|other) ;; *)
        echo "area must be: fanout|vet|gate|other"; exit 1 ;; esac
    case "{{ bucket }}" in lt5m|5-30m|gt30m) ;; *)
        echo "bucket must be: lt5m|5-30m|gt30m"; exit 1 ;; esac
    case "{{ kind }}" in authoring|retry|review|wait) ;; *)
        echo "kind must be: authoring|retry|review|wait"; exit 1 ;; esac
    case "{{ outcome }}" in prevented-defect|mechanical|false-positive) ;; *)
        echo "outcome must be: prevented-defect|mechanical|false-positive"
        exit 1 ;; esac
    if [[ ! -f "$LEDGER" ]]; then
        echo "missing $LEDGER — merge the _private ledger MR first"
        exit 1
    fi
    LINE="- $(date +%F) | {{ area }} | {{ bucket }} | {{ kind }} | {{ outcome }}"
    NOTE="{{ note }}"
    if [[ -n "$NOTE" ]]; then
        LINE="$LINE | $NOTE"
    fi
    # 80-col cap keeps the ledger inside the _private markdownlint gate.
    if [[ "${#LINE}" -gt 80 ]]; then
        echo "entry is ${#LINE} chars (>80, markdownlint) — shorten the note"
        exit 1
    fi
    # MD022/MD032: first entry needs a blank line after "## Entries"
    # (formatters strip a pre-seeded trailing blank, so ensure it here).
    if [[ "$(tail -n 1 "$LEDGER")" == "## Entries" ]]; then
        printf '\n' >> "$LEDGER"
    fi
    printf '%s\n' "$LINE" >> "$LEDGER"
    echo "appended: $LINE"
    echo "commit it with the session's _private doc updates"

# Generate a draft PreToolUse hook from observed patterns in
# .claude/.session-errors. Use after session-end flags a category
# under the 3-strike rule.
[group('setup')]
gen-hook-from-pattern category="" force="":
    @bash scripts/scripts/gen-hook-from-pattern.sh {{category}} {{force}}

# Weekly Claude Code cost-vs-output report: joins session-transcript token
# usage (incl. subagents) with git commits/lines to show cost-per-commit and
# subagent% trend. Answers "more tokens for fewer results?" empirically.
# Optional args: <workspace_root> <project_match> (both auto-detected).
[group('setup')]
[positional-arguments]
token-report *args:
    @python3 scripts/scripts/token-report.py "$@"

[group('tests')]
token-report-test scripts_root="scripts":
    #!/usr/bin/env bash
    set -euo pipefail
    tests=("{{ scripts_root }}"/scripts/tests/token-report-*.test.py)
    if [[ ! -e "${tests[0]}" ]]; then
        echo "ERROR: no token-report tests under {{ scripts_root }}/scripts/tests" >&2
        exit 1
    fi
    for test_file in "${tests[@]}"; do
        python3 "$test_file"
    done

[group('tests')]
session-efficiency-test private_root="_private":
    #!/usr/bin/env bash
    set -euo pipefail
    tests=("{{ private_root }}"/scripts/tests/session-efficiency-*.test.py)
    if [[ ! -e "${tests[0]}" ]]; then
        echo "ERROR: no session-efficiency tests under {{ private_root }}/scripts/tests" >&2
        exit 1
    fi
    for test_file in "${tests[@]}"; do
        python3 "$test_file"
    done

[group('reports')]
session-efficiency-report private_root="_private":
    @python3 "{{ private_root }}/scripts/session_efficiency_analyzer.py"

# Report hooks present in one agent harness's hook dir but not the other
# (.claude/hooks vs .kimi-code/hooks). Catches a guardrail added to one
# harness but never mirrored. --strict exits 1 on drift (for gating).
[group('setup')]
[positional-arguments]
check-hook-parity *args:
    @bash scripts/scripts/check-hook-parity.sh "$@"

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
    # cargo-nextest is required, not optional: `just test-name` / `just test-file`
    # and the coverage recipes in perf.just invoke `cargo nextest` directly, and
    # `just test` silently falls back to the slower `cargo test` without it.
    cargo_tools=(cargo-nextest cargo-watch cargo-audit cargo-deny cargo-llvm-cov sccache cargo-duplicates cargo-bloat cargo-sweep typos-cli)
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

# Install shell completions for just (bash + zsh by default)
# Usage: just setup-completion [bash|zsh]
[group('setup')]
[script]
setup-completion shell="":
    set -euo pipefail

    install_bash() {
        local dir="$HOME/.local/share/bash-completion/completions"
        mkdir -p "$dir"
        just --completions bash > "$dir/just"
        echo "  bash: $dir/just"
    }

    install_zsh() {
        local dir="$HOME/.zfunc"
        mkdir -p "$dir"
        just --completions zsh > "$dir/_just"
        echo "  zsh:  $dir/_just"

        if [[ -f "$HOME/.zshrc" ]]; then
            if grep -qE 'fpath.*\.zfunc' "$HOME/.zshrc"; then
                echo "  zsh:  ~/.zfunc already in fpath"
            else
                local tmp
                tmp=$(mktemp)
                if grep -q 'compinit' "$HOME/.zshrc"; then
                    awk '/compinit/ && !inserted { print "fpath+=(~/.zfunc)"; inserted=1 } { print }' \
                        "$HOME/.zshrc" > "$tmp"
                else
                    cp "$HOME/.zshrc" "$tmp"
                    echo 'fpath+=(~/.zfunc)' >> "$tmp"
                fi
                mv "$tmp" "$HOME/.zshrc"
                echo "  zsh:  added ~/.zfunc to fpath in ~/.zshrc"
            fi
        fi
    }

    echo "── Installing just shell completions ──"
    if [[ -z "{{shell}}" || "{{shell}}" == "bash" ]]; then
        install_bash
    fi
    if [[ -z "{{shell}}" || "{{shell}}" == "zsh" ]]; then
        install_zsh
    fi
    echo "── Done ──"
    echo "Reload your shell or start a new terminal to use completions."

# Inject `[patch]` blocks into each consumer repo's `Cargo.toml` so
# local cargo invocations resolve `vauchi-core` / `vauchi-app` /
# `vauchi-protocol` / `vauchi-relay` to the sibling clones rather than
# the git URL pinned in `Cargo.lock`.
#
# Why Cargo.toml and not `.cargo/config.toml`?
# Modern cargo only honours `[patch.<source>]` in `Cargo.toml`. The
# previous version of this recipe wrote to `.cargo/config.toml`, which
# cargo silently ignores — local "verified in TUI" claims have been
# false since the recipe was first written. See problem record
# `2026-05-03-cargo-path-override-broken`.
#
# Cargo.toml is tracked, so each block is fenced with sentinel lines:
#
#     # >>> setup-path-overrides BEGIN — DO NOT COMMIT
#     [patch.'https://gitlab.com/vauchi/core.git']
#     vauchi-core = { path = "../core/vauchi-core" }
#     # <<< setup-path-overrides END
#
# A pre-commit hook (`scripts/hooks/pre-commit`) blocks any commit that
# stages a Cargo.toml still carrying the fence. `just clean-path-overrides`
# strips it. `just check-path-overrides` verifies cargo actually picked
# up the patch.
#
# Run after `just setup` or when switching branches that changed core APIs.
[group('setup')]
[script]
setup-path-overrides:
    set -euo pipefail
    bash scripts/scripts/path-overrides.sh apply

# Strip the `# >>> setup-path-overrides BEGIN` fenced block from every
# consumer Cargo.toml. Run before committing if a stage trips the
# pre-commit hook, or on branch switch when you want a clean tree.
[group('setup')]
[script]
clean-path-overrides:
    set -euo pipefail
    bash scripts/scripts/path-overrides.sh clean

# Verify that `cargo metadata` resolves `vauchi-core` / `vauchi-app` /
# `vauchi-protocol` / `vauchi-relay` to local paths, not git URLs.
# Failing means `setup-path-overrides` either didn't run or was
# stripped — the local TUI/CLI/linux-gtk/relay/e2e are running against
# whatever git rev `Cargo.lock` is pinned to, not your local edits.
[group('setup')]
[script]
check-path-overrides:
    set -euo pipefail
    bash scripts/scripts/path-overrides.sh check

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
