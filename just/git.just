# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Multi-repo git commands
# Usage: just git <recipe>
#
# Split into focused files for maintainability:
#   git.just       — core daily operations (main, status, fetch, sync, push, pull, branch)
#   git-wip.just   — WIP save/restore/resume
#   git-audit.just — branch health, cleanup, stale detection

import 'git-wip.just'
import 'git-audit.just'

# Save changes, checkout main, and pull latest in all repos
# Usage: just git main          (interactive — prompts with wip/stash/abort)
#        just git main yes      (non-interactive — auto-stash without prompting)
#        just git main wip      (non-interactive — auto-WIP-commit without prompting)
#        just git main discard  (non-interactive — discard all uncommitted changes)
[no-cd]
[script]
main mode='':
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/for-each-repo.sh
    timer_start

    # First pass: collect dirty repos and show changes
    dirty_repos=()
    dirty_labels=()
    _collect_dirty() {
        local label="$1" dir="$2"
        if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
            dirty_repos+=("$dir")
            dirty_labels+=("$label")
        fi
    }
    for_each_repo _collect_dirty

    save_mode=""
    if [[ ${#dirty_repos[@]} -gt 0 ]]; then
        echo "Uncommitted changes in:"
        echo ""
        for i in "${!dirty_repos[@]}"; do
            dir="${dirty_repos[$i]}"
            label="${dirty_labels[$i]}"
            echo "── $label ──"
            git -C "$dir" status --short
            echo ""
        done
        if [[ "{{ mode }}" == "yes" ]]; then
            echo "(auto-stashing — non-interactive mode)"
            save_mode="stash"
        elif [[ "{{ mode }}" == "wip" ]]; then
            echo "(auto-WIP-commit — non-interactive mode)"
            save_mode="wip"
        elif [[ "{{ mode }}" == "discard" ]]; then
            echo "(discarding all uncommitted changes — non-interactive mode)"
            save_mode="discard"
        else
            echo "How to save? [w]ip commit (recommended), [s]tash, [d]iscard, [a]bort"
            read -rp "> " answer </dev/tty
            case "$answer" in
                w|W|wip) save_mode="wip" ;;
                s|S|stash) save_mode="stash" ;;
                d|D|discard) save_mode="discard" ;;
                *) echo "Aborted."; exit 0 ;;
            esac
        fi
        echo ""
    fi

    # Count repos for progress
    repo_total=1
    for dir in */; do [[ -d "${dir}.git" ]] && repo_total=$((repo_total + 1)); done
    repo_n=0
    fail_file=$(mktemp)
    trap 'rm -f "$fail_file"' EXIT
    echo 0 > "$fail_file"

    # Second pass: save changes, checkout main, and pull
    switch_to_main() {
        local label="$1"
        local dir="$2"
        local n="$3"
        local save_info=""
        cd "$dir" || return 1
        # Save if dirty
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            if [[ "$save_mode" == "wip" ]]; then
                local timestamp
                timestamp=$(date +%Y%m%d-%H%M%S)
                git add -A
                git commit -m "wip: checkpoint $timestamp" --quiet --no-verify
                save_info="wip saved → "
            elif [[ "$save_mode" == "discard" ]]; then
                git checkout -- . 2>/dev/null || true
                git clean -fd --quiet 2>/dev/null || true
                save_info="discarded → "
            else
                git stash push -m "auto-stash before switching to main" --quiet \
                    || echo "  WARN: stash failed for $label" >&2
                save_info="stashed → "
            fi
        fi
        # Checkout main and pull
        # Pre-flight: detect unmerged files
        local unmerged
        unmerged=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
        if [[ -n "$unmerged" ]]; then
            local files
            files=$(echo "$unmerged" | head -3 | tr '\n' ', ' | sed 's/,$//')
            progress_fail "$n" "$repo_total" "$label" "${save_info}unmerged files: $files — run: git restore --staged --worktree $files"
            echo $(( $(cat "$fail_file") + 1 )) > "$fail_file"
            return
        fi
        if git checkout main --quiet 2>/dev/null; then
            local output
            # `--autostash` keeps `git main` working when a consumer
            # Cargo.toml/Cargo.lock has local-only edits; mirrors the
            # `git sync` recipe.
            if output=$(git pull --rebase --autostash --quiet 2>&1); then
                if [[ -z "$output" ]] || echo "$output" | grep -qE "Already up to date|up to date|Current branch .* is up to date"; then
                    progress_ok "$n" "$repo_total" "$label" "${save_info}up to date"
                elif echo "$output" | grep -q "Applied autostash"; then
                    progress_ok "$n" "$repo_total" "$label" "${save_info}pulled main (autostash applied)"
                else
                    progress_ok "$n" "$repo_total" "$label" "${save_info}pulled main"
                fi
            else
                git rebase --abort 2>/dev/null || true
                local reason="pull --rebase failed"
                if echo "$output" | grep -q "CONFLICT"; then
                    reason="rebase conflict — resolve manually"
                elif echo "$output" | grep -q "Applying autostash resulted in conflicts"; then
                    reason="autostash conflict — resolve in worktree; recovery: git stash pop"
                elif echo "$output" | grep -q "uncommitted changes"; then
                    reason="dirty working tree — commit or stash first"
                fi
                progress_fail "$n" "$repo_total" "$label" "${save_info}$reason"
                echo $(( $(cat "$fail_file") + 1 )) > "$fail_file"
            fi
        else
            progress_fail "$n" "$repo_total" "$label" "${save_info}FAILED (no main branch?)"
            echo $(( $(cat "$fail_file") + 1 )) > "$fail_file"
        fi
    }
    # Root repo
    repo_n=$((repo_n + 1))
    switch_to_main "vauchi (root)" "." "$repo_n"
    # Sub-repos
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            repo_n=$((repo_n + 1))
            (switch_to_main "${dir%/}" "$dir" "$repo_n")
        fi
    done

    fail_count=$(cat "$fail_file")
    rm -f "$fail_file"
    ok_count=$((repo_total - fail_count))

    # Auto-cleanup: delete local branches already merged into main
    source scripts/scripts/git-helpers.sh
    cleaned=0
    cleanup_merged() {
        local label="$1" dir="$2"
        local merged
        merged=$(list_merged_branches "$dir")
        [[ -z "$merged" ]] && return 0
        while IFS= read -r b; do
            [[ -z "$b" ]] && continue
            if git -C "$dir" branch -D "$b" &>/dev/null; then
                status_ok "$label" "deleted merged branch '$b'"
                cleaned=$((cleaned + 1))
            fi
        done <<< "$merged"
    }
    for_each_repo cleanup_merged

    elapsed=$(timer_elapsed)
    summary_mix "$ok_count" "$fail_count" "$elapsed"
    if [[ "$cleaned" -gt 0 ]]; then
        echo "Cleaned up $cleaned merged branch(es)"
    fi

# Show git status for all repos
[no-cd]
default: status

[no-cd]
[script]
status:
    source scripts/scripts/output-helpers.sh
    shown=0
    show_repo_status() {
        local label="$1" dir="$2"
        local status branch ahead behind
        status=$(git -C "$dir" status --porcelain 2>/dev/null)
        branch=$(git -C "$dir" branch --show-current 2>/dev/null)
        ahead=$(git -C "$dir" rev-list --count @{u}..HEAD 2>/dev/null || echo "?")
        behind=$(git -C "$dir" rev-list --count HEAD..@{u} 2>/dev/null || echo "?")

        if [[ -n "$status" ]] || [[ "$branch" != "main" ]] || [[ "$ahead" != "0" ]] || [[ "$behind" != "0" ]]; then
            echo ""
            echo "── $label (${branch:-detached}) ──"
            [[ "$ahead" != "0" && "$ahead" != "?" ]] && printf "  ${GREEN}↑${NC} %s ahead\n" "$ahead"
            [[ "$behind" != "0" && "$behind" != "?" ]] && printf "  ${YELLOW}↓${NC} %s behind\n" "$behind"
            [[ -n "$status" ]] && echo "$status" | sed 's/^/  /'
            echo ""
            shown=$((shown + 1))
        fi
    }
    source scripts/scripts/for-each-repo.sh
    for_each_repo show_repo_status
    if [[ "$shown" -eq 0 ]]; then
        status_ok "all repos" "clean, on main"
    else
        printf "\n${DIM}Repos on main with no changes: not shown${NC}\n"
    fi

# Checkout main branch in all repos
[no-cd]
[script]
checkout-main:
    source scripts/scripts/output-helpers.sh
    out_begin
    checkout_repo() {
        local label="$1" dir="$2"
        local output
        output=$(git -C "$dir" checkout main 2>&1) || true
        if echo "$output" | grep -q "Already on"; then
            out_ok "$label" "already on main"
        elif echo "$output" | grep -q "Switched to"; then
            out_ok "$label" "switched to main"
        else
            out_fail "$label" "$(echo "$output" | tail -1)"
        fi
    }
    source scripts/scripts/for-each-repo.sh
    for_each_repo checkout_repo
    out_end

# Fetch all repos
[no-cd]
[script]
fetch:
    source scripts/scripts/output-helpers.sh
    timer_start
    out_begin
    fetch_repo() {
        local label="$1" dir="$2"
        local output fetched
        output=$(git -C "$dir" fetch --all 2>&1) || true
        fetched=$(echo "$output" | grep -E "^Fetching|^error:|^fatal:" || true)
        if [[ -n "$fetched" ]] && echo "$fetched" | grep -qE "^(error|fatal):"; then
            out_fail "$label" "$fetched"
        else
            out_ok "$label" "up to date"
        fi
    }
    source scripts/scripts/for-each-repo.sh
    for_each_repo fetch_repo
    out_end "$(timer_elapsed)"

# Show branches across all repos
[no-cd]
[script]
branches:
    source scripts/scripts/output-helpers.sh
    show_branch() {
        local label="$1" dir="$2"
        local branch count
        branch=$(git -C "$dir" branch --show-current 2>/dev/null)
        count=$(git -C "$dir" branch --list 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$branch" == "main" && "$count" -le 1 ]]; then
            status_ok "$label" "main"
        elif [[ "$branch" == "main" ]]; then
            status_info "$label" "main ($count branches)"
        else
            status_info "$label" "${branch:-detached} ($count branches)"
        fi
    }
    source scripts/scripts/for-each-repo.sh
    for_each_repo show_branch

# Pull latest changes from all repos
[no-cd]
[script]
pull-all:
    source scripts/scripts/output-helpers.sh
    timer_start
    out_begin
    pull_repo() {
        local label="$1" dir="$2"
        # Pre-flight: detect unmerged files
        local unmerged
        unmerged=$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null || true)
        if [[ -n "$unmerged" ]]; then
            local files
            files=$(echo "$unmerged" | head -3 | tr '\n' ', ' | sed 's/,$//')
            out_fail "$label" "unmerged files: $files — run: git -C $dir restore --staged --worktree $files"
            return 0
        fi
        local output
        # `--autostash` keeps `pull-all` working when a consumer
        # Cargo.toml/Cargo.lock has local-only edits; mirrors `git sync`.
        if output=$(git -C "$dir" pull --rebase --autostash --quiet 2>&1); then
            if echo "$output" | grep -qE "Already up to date|is up to date"; then
                out_ok "$label" "up to date"
            elif echo "$output" | grep -q "Applied autostash"; then
                out_ok "$label" "pulled (autostash applied)"
            else
                out_ok "$label" "pulled"
            fi
        else
            git -C "$dir" rebase --abort 2>/dev/null || true
            local reason
            if echo "$output" | grep -q "CONFLICT"; then
                reason="rebase conflict — run: git -C $dir pull --rebase and resolve"
            elif echo "$output" | grep -q "Applying autostash resulted in conflicts"; then
                reason="autostash conflict — resolve in worktree; recovery: git -C $dir stash pop"
            elif echo "$output" | grep -qE "unstaged changes|uncommitted changes"; then
                if grep -q '^# >>> setup-path-overrides BEGIN' "$dir/Cargo.toml" 2>/dev/null \
                   || grep -q '^# >>> setup-path-overrides BEGIN' "$dir/wasm/Cargo.toml" 2>/dev/null; then
                    reason="path-override dirt — run: just clean-path-overrides && just git pull-all && just setup-path-overrides"
                else
                    reason="dirty working tree — commit or stash first"
                fi
            else
                reason="pull failed — $(echo "$output" | tail -1)"
            fi
            out_fail "$label" "$reason"
        fi
    }
    source scripts/scripts/for-each-repo.sh
    for_each_repo pull_repo
    out_end "$(timer_elapsed)"

# Push all repos with commits ahead of origin
# Usage: just git push-all              (fmt + clippy + tests per repo)
#        just git push-all skip-tests   (fmt + clippy only, skip tests)
[no-cd]
[script]
push-all mode='full':
    source scripts/scripts/output-helpers.sh
    timer_start
    if [[ "{{ mode }}" == "skip-tests" ]]; then
        export SKIP_TESTS=1
        printf "${DIM}Pushing with SKIP_TESTS=1 (fmt + clippy only)${NC}\n\n"
    fi
    pushed=()
    wip_blocked=()
    skipped=0
    push_repo() {
        local label="$1" dir="$2"
        local ahead head_msg branch
        branch=$(git -C "$dir" branch --show-current 2>/dev/null)
        # Skip repos on main — main is protected, use MRs instead
        if [[ "$branch" == "main" ]]; then
            skipped=$((skipped + 1))
            return
        fi
        ahead=$(git -C "$dir" rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
        if [[ "$ahead" -gt 0 ]]; then
            # Block pushing WIP commits
            head_msg=$(git -C "$dir" log -1 --format=%s 2>/dev/null || true)
            if [[ "$head_msg" == wip:* ]]; then
                status_fail "$label" "SKIPPED — HEAD is WIP ($head_msg)"
                wip_blocked+=("$label")
                return
            fi
            status_info "$label" "pushing ($ahead commits ahead)..."
            if git -C "$dir" push; then
                status_ok "$label" "pushed"
            else
                status_fail "$label" "push FAILED"
                wip_blocked+=("$label")  # reuse array for all failures
                return
            fi
            pushed+=("$label")
        else
            skipped=$((skipped + 1))
        fi
    }
    source scripts/scripts/for-each-repo.sh
    for_each_repo push_repo
    elapsed=$(timer_elapsed)
    if [[ ${#pushed[@]} -eq 0 && ${#wip_blocked[@]} -eq 0 ]]; then
        status_ok "all repos" "nothing to push"
    fi
    if [[ ${#wip_blocked[@]} -gt 0 ]]; then
        printf "\n%sWIP-blocked (%d): %s%s\n" "$YELLOW" "${#wip_blocked[@]}" "${wip_blocked[*]}" "$NC"
        printf "%sUndo WIP commits first: just git wip-undo%s\n" "$DIM" "$NC"
    fi
    if [[ ${#pushed[@]} -gt 0 || ${#wip_blocked[@]} -gt 0 ]]; then
        summary_mix "${#pushed[@]}" "${#wip_blocked[@]}" "$elapsed"
    fi

# Push a single repo, retrying with --force-with-lease on non-fast-forward failure.
# Mirrors the fallback already used by `just gitlab mr-create`, but for the
# plain-git case when not opening an MR.
# Usage: just git push-retry          (current repo)
#        just git push-retry core     (specific repo)
[no-cd]
[script]
push-retry repo='':
    source scripts/scripts/output-helpers.sh
    set -euo pipefail
    dir="{{ repo }}"
    if [[ "$dir" == "." || "$dir" == "root" || -z "$dir" ]]; then
        dir="."
        label="vauchi (root)"
    else
        label="{{ repo }}"
    fi
    if [[ "$dir" != "." && ! -d "$dir/.git" ]]; then
        echo "ERROR: $dir is not a git repo" >&2
        exit 1
    fi
    branch=$(git -C "$dir" branch --show-current 2>/dev/null || true)
    if [[ "$branch" == "main" ]]; then
        status_fail "$label" "SKIPPED — main is protected, use MRs"
        exit 1
    fi
    ahead=$(git -C "$dir" rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
    if [[ "$ahead" -eq 0 ]]; then
        status_ok "$label" "nothing to push"
        exit 0
    fi
    status_info "$label" "pushing $ahead commit(s) on $branch..."
    if git -C "$dir" push 2>&1; then
        status_ok "$label" "pushed"
    else
        status_info "$label" "push rejected — trying force-with-lease"
        if git -C "$dir" push --force-with-lease 2>&1; then
            status_ok "$label" "pushed (force-with-lease)"
        else
            status_fail "$label" "push FAILED (force-with-lease also rejected)"
            exit 1
        fi
    fi

# Show diff of current branch vs origin/main
# Usage: just git diff-main [repo]   (omit repo to diff all repos with branches)
[no-cd]
[script]
diff-main repo='':
    set -euo pipefail
    if [[ -n "{{ repo }}" ]]; then
        dir="{{ repo }}"
        [[ "$dir" == "root" || "$dir" == "." ]] && dir="."
        if [[ "$dir" != "." && ! -d "$dir/.git" ]]; then
            echo "ERROR: $dir is not a git repo" >&2
            exit 1
        fi
        git -C "$dir" fetch origin main --quiet 2>/dev/null || echo "WARN: fetch failed for $dir" >&2
        label="{{ repo }}"
        [[ "$dir" == "." ]] && label="vauchi (root)"
        echo "── ${label} ──"
        git -C "$dir" diff origin/main...HEAD
    else
        for dir in . */; do
            if [[ "$dir" == "." ]]; then
                gitdir=".git"
                label="vauchi (root)"
            else
                [[ ! -d "${dir}.git" ]] && continue
                gitdir="${dir}.git"
                label="${dir%/}"
                dir="${dir%/}"
            fi
            branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "")
            [[ "$branch" == "main" || -z "$branch" ]] && continue
            git -C "$dir" fetch origin main --quiet 2>/dev/null || true
            count=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
            [[ "$count" == "0" ]] && continue
            echo "── $label ($branch, $count commits) ──"
            git -C "$dir" diff origin/main...HEAD --stat
            echo ""
        done
    fi

# Rebase current branch on origin/main
# Usage: just git rebase-main [repo]   (omit repo to rebase all feature branches)
[no-cd]
[script]
rebase-main repo='':
    source scripts/scripts/output-helpers.sh
    set -euo pipefail
    rebase_repo() {
        local label="$1" dir="$2"
        local branch
        branch=$(git -C "$dir" branch --show-current 2>/dev/null)
        if [[ "$branch" == "main" || -z "$branch" ]]; then
            return 0
        fi
        # Pre-flight: detect unmerged files
        local unmerged
        unmerged=$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null || true)
        if [[ -n "$unmerged" ]]; then
            local files
            files=$(echo "$unmerged" | head -3 | tr '\n' ', ' | sed 's/,$//')
            status_fail "$label" "unmerged files: $files — run: git -C $dir restore --staged --worktree $files"
            return 1
        fi
        echo ""
        echo "── $label ($branch) ──"
        git -C "$dir" fetch origin main --quiet 2>/dev/null
        local behind
        behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "0")
        if [[ "$behind" == "0" ]]; then
            status_ok "$label" "up to date with origin/main"
            return 0
        fi
        printf "  ${YELLOW}↓${NC} %s commits behind origin/main — rebasing...\n" "$behind"
        local rebase_output
        if rebase_output=$(git -C "$dir" rebase origin/main 2>&1); then
            echo "$rebase_output" | sed 's/^/  /'
            status_ok "$label" "rebase OK"
        else
            echo "$rebase_output" | sed 's/^/  /'
            status_fail "$label" "CONFLICT — resolve manually, then run: git -C $dir rebase --continue" >&2
            git -C "$dir" rebase --abort 2>/dev/null
            return 1
        fi
    }
    if [[ -n "{{ repo }}" ]]; then
        dir="{{ repo }}"
        [[ "$dir" == "root" || "$dir" == "." ]] && dir="."
        if [[ "$dir" != "." && ! -d "$dir/.git" ]]; then
            echo "ERROR: $dir is not a git repo" >&2
            exit 1
        fi
        label="{{ repo }}"
        [[ "$dir" == "." ]] && label="vauchi (root)"
        rebase_repo "$label" "$dir"
    else
        failed=()
        for dir in . */; do
            if [[ "$dir" == "." ]]; then
                label="vauchi (root)"
            else
                [[ ! -d "${dir}.git" ]] && continue
                label="${dir%/}"
                dir="${dir%/}"
            fi
            if ! rebase_repo "$label" "$dir"; then
                failed+=("$label")
            fi
        done
        echo ""
        if [[ ${#failed[@]} -gt 0 ]]; then
            echo "FAILED: ${failed[*]} — resolve conflicts manually"
            exit 1
        else
            echo "All branches up to date with origin/main"
        fi
    fi

# Show commits on current branch not on main
# Usage: just git log-branch [repo]   (omit repo to show all feature branches)
[no-cd]
[script]
log-branch repo='':
    set -euo pipefail
    log_repo() {
        local label="$1" dir="$2"
        local branch
        branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "")
        [[ "$branch" == "main" || -z "$branch" ]] && return 0
        local count
        count=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
        [[ "$count" == "0" ]] && return 0
        echo "── $label ($branch, $count commits) ──"
        git -C "$dir" log origin/main..HEAD --oneline --no-decorate
        echo ""
    }
    if [[ -n "{{ repo }}" ]]; then
        dir="{{ repo }}"
        [[ "$dir" == "root" || "$dir" == "." ]] && dir="."
        if [[ "$dir" != "." && ! -d "$dir/.git" ]]; then
            echo "ERROR: $dir is not a git repo" >&2
            exit 1
        fi
        label="{{ repo }}"
        [[ "$dir" == "." ]] && label="vauchi (root)"
        git -C "$dir" fetch origin main --quiet 2>/dev/null || true
        log_repo "$label" "$dir"
    else
        for dir in . */; do
            if [[ "$dir" == "." ]]; then
                label="vauchi (root)"
            else
                [[ ! -d "${dir}.git" ]] && continue
                label="${dir%/}"
                dir="${dir%/}"
            fi
            log_repo "$label" "$dir"
        done
    fi

# Fetch all repos and pull where on main (combines fetch + pull)
[no-cd]
[script]
sync:
    source scripts/scripts/output-helpers.sh
    set -euo pipefail
    timer_start

    # The path-override fence and its regenerated Cargo.lock are local-only
    # and unstashable in practice: `pull --rebase --autostash` stashes them,
    # pulls a main that moved Cargo.lock, then cannot merge the pop — so
    # every sync left conflict markers plus an orphan autostash behind.
    # Strip before pulling, restore after. The trap covers the mid-sync
    # failure path; without it a fetch error would leave the tree stripped.
    _po=scripts/scripts/path-overrides.sh
    _po_restore=0
    if bash "$_po" status; then
        _po_restore=1
        bash "$_po" clean >/dev/null
    fi
    trap '[[ "$_po_restore" == 1 ]] && bash "$_po" apply >/dev/null 2>&1 || true' EXIT

    # Count repos for progress
    repo_total=1
    for dir in */; do [[ -d "${dir}.git" ]] && repo_total=$((repo_total + 1)); done
    repo_n=0
    ok_count=0
    fail_count=0

    sync_repo() {
        local label="$1" dir="$2" n="$3"

        # Pre-flight: detect unmerged files (stale merge/rebase conflicts)
        local unmerged
        unmerged=$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null || true)
        if [[ -n "$unmerged" ]]; then
            local file_list
            file_list=$(echo "$unmerged" | head -3 | tr '\n' ', ' | sed 's/,$//')
            progress_fail "$n" "$repo_total" "$label" "unmerged files: $file_list — resolve or run: git -C $dir restore --staged --worktree $file_list"
            fail_count=$((fail_count + 1))
            return 0
        fi

        if ! git -C "$dir" fetch --all --quiet 2>/dev/null; then
            progress_fail "$n" "$repo_total" "$label" "fetch FAILED — check network or remote URL"
            fail_count=$((fail_count + 1))
            return 0
        fi
        local branch
        branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "")
        if [[ "$branch" == "main" ]]; then
            local output
            # `--autostash` keeps sync working when the consumer Cargo.toml/
            # Cargo.lock have local-only edits (e.g. path-override fences
            # written by `setup-path-overrides`, or transient build
            # artifacts): the stash is auto-applied after rebase. If the
            # pop conflicts, git leaves markers in the worktree but the
            # rebase itself returns 0 — we post-check for unmerged files
            # so the conflict is reported as a failure, not a silent ok.
            # Use subshell to prevent set -e from aborting on pull failure
            if output=$(git -C "$dir" pull --rebase --autostash --quiet 2>&1); then
                # Post-check: did `--autostash` leave unmerged files?
                local post_unmerged
                post_unmerged=$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null || true)
                if [[ -n "$post_unmerged" ]]; then
                    local nfiles
                    nfiles=$(echo "$post_unmerged" | wc -l | tr -d ' ')
                    progress_fail "$n" "$repo_total" "$label" "autostash pop conflicted on $nfiles file(s); recovery: git -C $dir checkout --theirs <files> or stash list"
                    fail_count=$((fail_count + 1))
                elif [[ -z "$output" ]] || echo "$output" | grep -qE "Already up to date|up to date|Current branch .* is up to date"; then
                    progress_ok "$n" "$repo_total" "$label" "fetched, main up to date"
                    ok_count=$((ok_count + 1))
                elif echo "$output" | grep -q "Applied autostash"; then
                    progress_ok "$n" "$repo_total" "$label" "fetched, pulled main (autostash applied)"
                    ok_count=$((ok_count + 1))
                else
                    progress_ok "$n" "$repo_total" "$label" "fetched, pulled main"
                    ok_count=$((ok_count + 1))
                fi
            else
                # Rebase failed — abort it and report. With --autostash,
                # if pop conflicts the stash is preserved at stash@{0}.
                git -C "$dir" rebase --abort 2>/dev/null || true
                local reason="pull --rebase failed"
                if echo "$output" | grep -q "CONFLICT"; then
                    reason="rebase conflict — run: git -C $dir pull --rebase and resolve"
                elif echo "$output" | grep -q "Applying autostash resulted in conflicts"; then
                    reason="autostash conflict — resolve in worktree; recovery: git -C $dir stash pop"
                elif echo "$output" | grep -qE "unstaged changes|uncommitted changes"; then
                    # Detect the path-override fence so we can point at the
                    # exact recovery path instead of the generic "stash first"
                    # hint — the fenced [patch] block + regenerated Cargo.lock
                    # are local-only and cannot be stashed away.
                    if grep -q '^# >>> setup-path-overrides BEGIN' "$dir/Cargo.toml" 2>/dev/null \
                       || grep -q '^# >>> setup-path-overrides BEGIN' "$dir/wasm/Cargo.toml" 2>/dev/null; then
                        reason="path-override dirt — run: just clean-path-overrides && just git sync && just setup-path-overrides"
                    else
                        reason="dirty working tree — commit or stash first"
                    fi
                elif echo "$output" | grep -q "unmerged"; then
                    reason="unmerged files — resolve or: git -C $dir restore --staged --worktree <file>"
                fi
                progress_fail "$n" "$repo_total" "$label" "$reason"
                fail_count=$((fail_count + 1))
            fi
        else
            local ahead behind
            ahead=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "?")
            behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
            progress_info "$n" "$repo_total" "$label" "fetched (on $branch, ↑$ahead ↓$behind vs main)"
            ok_count=$((ok_count + 1))
        fi
    }
    repo_n=$((repo_n + 1))
    sync_repo "vauchi (root)" "." "$repo_n"
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            repo_n=$((repo_n + 1))
            sync_repo "${dir%/}" "$dir" "$repo_n"
        fi
    done
    summary_mix "$ok_count" "$fail_count" "$(timer_elapsed)"

# Show branch status for all repos (branch, ahead/behind, merged)
[no-cd]
[script]
branch-status:
    source scripts/scripts/output-helpers.sh
    set -euo pipefail
    _BS_C1=22  # repo column
    _BS_C2=32  # branch column
    _tbl() {
        local c1="$1" c2="$2" c3="$3" c4="$4" c5="$5"
        local _p1=$(( _BS_C1 - ${#c1} )); [[ $_p1 -lt 1 ]] && _p1=1
        local _p2=$(( _BS_C2 - ${#c2} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "  %s%*s %s%*s %8s %8s %s\n" "$c1" "$_p1" "" "$c2" "$_p2" "" "$c3" "$c4" "$c5"
    }
    _tbl "REPO" "BRANCH" "AHEAD" "BEHIND" "MERGED?"
    printf "  ${DIM}%s${NC}\n" "$(printf '%*s' $(( _BS_C1 + _BS_C2 + 28 )) '' | tr ' ' '-')"
    check_repo() {
        local label="$1" dir="$2"
        local branch ahead behind merged color_l color_b
        branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "detached")
        if [[ "$branch" == "main" ]]; then
            behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
            if [[ "$behind" == "0" || "$behind" == "?" ]]; then
                color_l="${GREEN}" color_b=""
            else
                color_l="${YELLOW}" color_b="${YELLOW}"
            fi
            local _p1=$(( _BS_C1 - ${#label} )); [[ $_p1 -lt 1 ]] && _p1=1
            local _p2=$(( _BS_C2 - ${#branch} )); [[ $_p2 -lt 1 ]] && _p2=1
            printf "  ${color_l}%s${NC}%*s %s%*s %8s ${color_b}%8s${NC} %s\n" \
                "$label" "$_p1" "" "$branch" "$_p2" "" "-" "$behind" "-"
            return
        fi
        ahead=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "?")
        behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
        if git -C "$dir" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
            merged="${GREEN}yes${NC}"
        else
            merged="no"
        fi
        local _p1=$(( _BS_C1 - ${#label} )); [[ $_p1 -lt 1 ]] && _p1=1
        local _p2=$(( _BS_C2 - ${#branch} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "  %s%*s ${BLUE}%s${NC}%*s %8s %8s %b\n" \
            "$label" "$_p1" "" "$branch" "$_p2" "" "$ahead" "$behind" "$merged"
    }
    source scripts/scripts/for-each-repo.sh
    for_each_repo check_repo

# Create a branch with the same name across repos
# If repos have uncommitted changes, prompts to save them first
# Usage: just git branch feature/my-feature core cli linux-gtk
#        just git branch feature/my-feature           (all repos)
[no-cd]
[script]
branch name *repos='':
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/for-each-repo.sh
    set -euo pipefail
    if [[ -z "{{ name }}" ]]; then
        echo "Usage: just git branch <branch-name> [repo1 repo2 ...]" >&2
        exit 1
    fi
    targets=()
    if [[ -n "{{ repos }}" ]]; then
        for r in {{ repos }}; do
            if [[ -d "$r/.git" ]]; then
                targets+=("$r")
            elif [[ "$r" == "root" || "$r" == "." ]]; then
                targets+=(".")
            else
                echo "WARNING: $r is not a git repo, skipping" >&2
            fi
        done
    else
        # for_each_repo, not `for dir in */` — the glob cannot see the
        # workspace repo itself, so "all repos" silently skipped root and
        # left it behind on whatever branch it was already on. Same
        # helper `just git resume` uses, so the pair stays symmetric.
        _collect_all() {
            local label="$1" dir="$2"
            targets+=("$dir")
        }
        for_each_repo _collect_all
    fi

    # Safety check: warn about uncommitted changes before switching
    dirty=()
    for dir in "${targets[@]}"; do
        label="$dir"
        [[ "$dir" == "." ]] && label="vauchi (root)"
        if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
            dirty+=("$label")
        fi
    done
    if [[ ${#dirty[@]} -gt 0 ]]; then
        echo "WARNING: Uncommitted changes in: ${dirty[*]}"
        if [[ -t 0 ]]; then
            echo "How to save? [w]ip commit (recommended), [s]kip (keep changes), [a]bort"
            read -rp "> " answer
            case "$answer" in
                w|W|wip)
                    echo "Saving WIP commits..."
                    timestamp=$(date +%Y%m%d-%H%M%S)
                    for dir in "${targets[@]}"; do
                        if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
                            git -C "$dir" add -A
                            git -C "$dir" commit -m "wip: checkpoint $timestamp" --quiet --no-verify
                            label="$dir"
                            [[ "$dir" == "." ]] && label="vauchi (root)"
                            status_ok "$label" "WIP saved"
                        fi
                    done
                    echo ""
                    ;;
                s|S|skip) echo "Proceeding without saving..." ;;
                *) echo "Aborted."; exit 0 ;;
            esac
        else
            echo "Non-interactive shell — save changes first with: just git wip" >&2
            exit 1
        fi
    fi

    created=()
    skipped=()
    for dir in "${targets[@]}"; do
        label="$dir"
        [[ "$dir" == "." ]] && label="vauchi (root)"
        current=$(git -C "$dir" branch --show-current 2>/dev/null)
        if [[ "$current" == "{{ name }}" ]]; then
            skipped+=("$label (already on it)")
            continue
        fi
        if git -C "$dir" rev-parse --verify "{{ name }}" &>/dev/null; then
            git -C "$dir" checkout "{{ name }}" --quiet 2>/dev/null
            status_ok "$label" "switched to existing branch"
            created+=("$label")
        else
            git -C "$dir" checkout -b "{{ name }}" --quiet 2>/dev/null
            status_ok "$label" "created new branch"
            created+=("$label")
        fi
    done
    echo ""
    [[ ${#created[@]} -gt 0 ]] && echo "Branch '{{ name }}' active in: ${created[*]}"
    [[ ${#skipped[@]} -gt 0 ]] && echo "Skipped: ${skipped[*]}"
    exit 0
