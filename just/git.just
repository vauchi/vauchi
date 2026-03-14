# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Multi-repo git commands
# Usage: just git <recipe>

# Save changes, checkout main, and pull latest in all repos
# Usage: just git main          (interactive — prompts with wip/stash/abort)
#        just git main yes      (non-interactive — auto-stash without prompting)
#        just git main wip      (non-interactive — auto-WIP-commit without prompting)
[no-cd]
[script]
main mode='':
    # First pass: collect dirty repos and show changes
    dirty_repos=()
    dirty_labels=()
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            label="vauchi (root)"
            gitdir=".git"
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"
            gitdir="${dir}.git"
        fi
        if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
            dirty_repos+=("$dir")
            dirty_labels+=("$label")
        fi
    done

    save_mode=""
    if [[ ${#dirty_repos[@]} -gt 0 ]]; then
        echo "Uncommitted changes in:"
        echo ""
        for i in "${!dirty_repos[@]}"; do
            dir="${dirty_repos[$i]}"
            label="${dirty_labels[$i]}"
            echo "=== $label ==="
            git -C "$dir" status --short
            echo ""
        done
        if [[ "{{ mode }}" == "yes" ]]; then
            echo "(auto-stashing — non-interactive mode)"
            save_mode="stash"
        elif [[ "{{ mode }}" == "wip" ]]; then
            echo "(auto-WIP-commit — non-interactive mode)"
            save_mode="wip"
        else
            echo "How to save? [w]ip commit (recommended), [s]tash, [a]bort"
            read -rp "> " answer
            case "$answer" in
                w|W|wip) save_mode="wip" ;;
                s|S|stash) save_mode="stash" ;;
                *) echo "Aborted."; exit 0 ;;
            esac
        fi
        echo ""
    fi

    # Second pass: save changes, checkout main, and pull
    switch_to_main() {
        local label="$1"
        local dir="$2"
        echo -n "$label: "
        cd "$dir" || return 1
        # Save if dirty
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            if [[ "$save_mode" == "wip" ]]; then
                local timestamp
                timestamp=$(date +%Y%m%d-%H%M%S)
                git add -A
                git commit -m "wip: checkpoint $timestamp" --quiet --no-verify
                echo -n "(wip saved) "
            else
                git stash push -m "auto-stash before switching to main" --quiet
                echo -n "(stashed) "
            fi
        fi
        # Checkout main and pull
        if git checkout main --quiet 2>/dev/null; then
            output=$(git pull --rebase 2>&1 || git pull 2>&1)
            if echo "$output" | grep -q "Already up to date"; then
                echo "up to date"
            else
                echo "$output" | tail -1
            fi
        else
            echo "FAILED (no main branch?)"
        fi
    }
    # Root repo
    switch_to_main "vauchi (root)" "."
    # Sub-repos
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            (switch_to_main "${dir%/}" "$dir")
        fi
    done

    # Auto-cleanup: delete local branches already merged into main
    echo ""
    cleaned=0
    cleanup_merged() {
        local label="$1" dir="$2"
        local merged
        # Check against origin/main (local main may be stale after ff merge)
        merged=$(git -C "$dir" branch --merged origin/main 2>/dev/null \
            | grep -vE '^\*|^[[:space:]]+main$' \
            | sed 's/^[[:space:]]*//' || true)
        # Fallback: detect branches whose content is in main even if
        # git ancestry doesn't show it (e.g. rebased before ff merge)
        local all_local
        all_local=$(git -C "$dir" branch --no-color 2>/dev/null \
            | grep -vE '^\*|^[[:space:]]+main$' \
            | sed 's/^[[:space:]]*//' || true)
        for candidate in $all_local; do
            echo "$merged" | grep -qxF "$candidate" && continue
            if git -C "$dir" diff --quiet origin/main..."$candidate" -- 2>/dev/null; then
                merged=$(printf '%s\n%s' "$merged" "$candidate")
            fi
        done
        merged=$(echo "$merged" | sed '/^$/d' || true)
        [[ -z "$merged" ]] && return 0
        while IFS= read -r b; do
            [[ -z "$b" ]] && continue
            if git -C "$dir" branch -D "$b" &>/dev/null; then
                echo "  $label: deleted merged branch '$b'"
                cleaned=$((cleaned + 1))
            fi
        done <<< "$merged"
    }
    cleanup_merged "vauchi (root)" "."
    for dir in */; do
        [[ -d "${dir}.git" ]] && cleanup_merged "${dir%/}" "$dir"
    done
    if [[ "$cleaned" -gt 0 ]]; then
        echo "Cleaned up $cleaned merged branch(es)"
    fi

# Show git status for all repos
[no-cd]
[default]
[script]
status:
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            status=$(cd "$dir" && git status --porcelain 2>/dev/null)
            branch=$(cd "$dir" && git branch --show-current 2>/dev/null)
            ahead=$(cd "$dir" && git rev-list --count @{u}..HEAD 2>/dev/null || echo "?")
            behind=$(cd "$dir" && git rev-list --count HEAD..@{u} 2>/dev/null || echo "?")

            if [[ -n "$status" ]] || [[ "$branch" != "main" ]] || [[ "$ahead" != "0" ]] || [[ "$behind" != "0" ]]; then
                echo "=== ${dir%/} (${branch:-detached}) ==="
                [[ "$ahead" != "0" && "$ahead" != "?" ]] && echo "  ↑ $ahead ahead"
                [[ "$behind" != "0" && "$behind" != "?" ]] && echo "  ↓ $behind behind"
                [[ -n "$status" ]] && echo "$status" | sed 's/^/  /'
                echo ""
            fi
        fi
    done
    echo "Repos on main with no changes: not shown"

# Checkout main branch in all repos
[no-cd]
[script]
checkout-main:
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            echo -n "${dir%/}: "
            (cd "$dir" && git checkout main 2>&1) | tail -1
        fi
    done

# Fetch all repos
[no-cd]
[script]
fetch:
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            echo -n "${dir%/}: "
            (cd "$dir" && git fetch --all 2>&1) | grep -E "^Fetching|error|fatal" || echo "up to date"
        fi
    done

# Show branches across all repos
[no-cd]
[script]
branches:
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            branch=$(cd "$dir" && git branch --show-current 2>/dev/null)
            branches=$(cd "$dir" && git branch --list 2>/dev/null | wc -l)
            echo "${dir%/}: ${branch:-detached} ($branches branches)"
        fi
    done

# Branch cleanup: merged local/remote branches + stale tracking refs
# Usage: just git cleanup          (dry run — preview only)
#        just git cleanup run      (delete branches and prune refs)
[no-cd]
[script]
cleanup mode='dry-run':
    set -uo pipefail

    MODE="{{ mode }}"

    if [[ "$MODE" != "dry-run" && "$MODE" != "run" ]]; then
        echo "Usage: just git cleanup [dry-run|run]"
        exit 1
    fi

    if [[ "$MODE" == "run" ]]; then
        echo "EXECUTING branch cleanup across all repos"
    else
        echo "DRY RUN — showing what would be cleaned"
        echo "(run 'just git cleanup run' to execute)"
    fi
    echo "Fetching all repos first..."
    for dir in . */; do
        [[ "$dir" == "." ]] && gitdir=".git" || gitdir="${dir}.git"
        [[ -d "$gitdir" ]] && git -C "$dir" fetch --all --prune --quiet 2>/dev/null
    done
    echo ""

    total_local=0
    total_remote=0
    total_stale=0

    cleanup_repo() {
        local label="$1"
        local dir="$2"

        # Must have main branch and origin remote
        git -C "$dir" rev-parse --verify main &>/dev/null || return 0
        git -C "$dir" remote 2>/dev/null | grep -q '^origin$' || return 0

        local local_branches remote_branches stale_refs

        # Local branches merged into origin/main (exclude current branch and main itself)
        # Uses origin/main (not local main) because fetch runs first but doesn't
        # update local main — so local main can be stale after ff merges.
        local_branches=$(git -C "$dir" branch --merged origin/main 2>/dev/null \
            | grep -vE '^\*|^[[:space:]]+main$' \
            | sed 's/^[[:space:]]*//' || true)

        # Fallback: detect branches whose content is already in origin/main
        # even if git ancestry doesn't show it (e.g. after interactive rebase
        # rewrote commits before the ff merge, or rare squash merges).
        all_local=$(git -C "$dir" branch --no-color 2>/dev/null \
            | grep -vE '^\*|^[[:space:]]+main$' \
            | sed 's/^[[:space:]]*//' || true)
        for candidate in $all_local; do
            echo "$local_branches" | grep -qxF "$candidate" && continue
            if git -C "$dir" diff --quiet origin/main..."$candidate" -- 2>/dev/null; then
                local_branches=$(printf '%s\n%s' "$local_branches" "$candidate")
            fi
        done
        local_branches=$(echo "$local_branches" | sed '/^$/d' || true)

        # Remote branches merged into origin/main (exclude main and HEAD pointer)
        remote_branches=$(git -C "$dir" branch -r --merged origin/main 2>/dev/null \
            | grep -E '^[[:space:]]+origin/' \
            | grep -vE 'origin/main$|origin/HEAD' \
            | sed 's|^[[:space:]]*origin/||' || true)

        # Stale remote-tracking refs (remote branch deleted but local ref remains)
        stale_refs=$(git -C "$dir" remote prune origin --dry-run 2>/dev/null \
            | grep '\[would prune\]' \
            | sed 's/.*\[would prune\] //' || true)

        local lc=0 rc=0 sc=0
        [[ -n "$local_branches" ]] && lc=$(echo "$local_branches" | wc -l | tr -d ' ')
        [[ -n "$remote_branches" ]] && rc=$(echo "$remote_branches" | wc -l | tr -d ' ')
        [[ -n "$stale_refs" ]] && sc=$(echo "$stale_refs" | wc -l | tr -d ' ')

        local total=$((lc + rc + sc))
        [[ "$total" -eq 0 ]] && return 0

        echo "=== $label ==="

        if [[ -n "$local_branches" ]]; then
            echo "  Local merged ($lc):"
            while IFS= read -r b; do
                [[ -z "$b" ]] && continue
                if [[ "$MODE" == "run" ]]; then
                    # Use -D: we've already verified content is in main
                    # (via --merged or diff check), but -d fails on squash merges
                    if git -C "$dir" branch -D "$b" &>/dev/null; then
                        echo "    deleted  $b"
                    else
                        echo "    FAILED   $b (currently checked out?)"
                    fi
                else
                    echo "    $b"
                fi
            done <<< "$local_branches"
        fi

        if [[ -n "$remote_branches" ]]; then
            echo "  Remote merged ($rc):"
            while IFS= read -r b; do
                [[ -z "$b" ]] && continue
                if [[ "$MODE" == "run" ]]; then
                    if git -C "$dir" push origin --delete "$b" 2>/dev/null; then
                        echo "    deleted  origin/$b"
                    else
                        echo "    FAILED   origin/$b (already gone or protected)"
                    fi
                else
                    echo "    origin/$b"
                fi
            done <<< "$remote_branches"
        fi

        if [[ -n "$stale_refs" ]]; then
            echo "  Stale refs ($sc):"
            while IFS= read -r ref; do
                [[ -z "$ref" ]] && continue
                echo "    $ref"
            done <<< "$stale_refs"
            if [[ "$MODE" == "run" ]]; then
                git -C "$dir" remote prune origin &>/dev/null
                echo "    (pruned)"
            fi
        fi

        echo ""

        total_local=$((total_local + lc))
        total_remote=$((total_remote + rc))
        total_stale=$((total_stale + sc))
    }

    # Root repo
    cleanup_repo "vauchi (root)" "."

    # Sub-repos
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            cleanup_repo "${dir%/}" "$dir"
        fi
    done

    # Summary
    grand_total=$((total_local + total_remote + total_stale))
    if [[ "$grand_total" -eq 0 ]]; then
        echo "All clean — no merged branches or stale refs found."
    else
        echo "Summary: $total_local local, $total_remote remote, $total_stale stale ($grand_total total)"
        if [[ "$MODE" == "dry-run" ]]; then
            echo "Run 'just git cleanup run' to delete these."
        else
            echo "Done."
        fi
    fi

# Clear all stashes across all repos
[no-cd]
[script]
stash-clear:
    echo "Clearing git stash in all repos..."
    echo ""

    cleared=()

    # Root repo
    count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
        git stash clear
        echo "vauchi (root): cleared $count stash(es)"
        cleared+=("vauchi (root)")
    fi

    # Sub-repos
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            count=$(git -C "$dir" stash list 2>/dev/null | wc -l | tr -d ' ')
            if [[ "$count" -gt 0 ]]; then
                git -C "$dir" stash clear
                echo "${dir%/}: cleared $count stash(es)"
                cleared+=("${dir%/}")
            fi
        fi
    done

    echo ""
    if [[ ${#cleared[@]} -eq 0 ]]; then
        echo "No stashes found in any repo."
    else
        echo "Cleared stashes in ${#cleared[@]} repo(s): ${cleared[*]}"
    fi

# Pull latest changes from all repos
[no-cd]
[script]
pull-all:
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            echo -n "${dir%/}: "
            (cd "$dir" && git pull --rebase 2>&1) || (cd "$dir" && git pull 2>&1) || echo "FAILED"
        fi
    done

# Push all repos with commits ahead of origin
# Usage: just git push-all              (fmt + clippy + tests per repo)
#        just git push-all skip-tests   (fmt + clippy only, skip tests)
[no-cd]
[script]
push-all mode='full':
    if [[ "{{ mode }}" == "skip-tests" ]]; then
        export SKIP_TESTS=1
        echo "Pushing with SKIP_TESTS=1 (fmt + clippy only)"
        echo ""
    fi
    pushed=()
    wip_blocked=()
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            ahead=$(cd "$dir" && git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
            if [[ "$ahead" -gt 0 ]]; then
                # Block pushing WIP commits
                head_msg=$(git -C "$dir" log -1 --format=%s 2>/dev/null || true)
                if [[ "$head_msg" == wip:* ]]; then
                    echo "SKIPPED ${dir%/}: HEAD is a WIP commit ($head_msg)"
                    echo "  -> Run: just git wip-undo ${dir%/}"
                    wip_blocked+=("${dir%/}")
                    continue
                fi
                echo "Pushing ${dir%/} ($ahead commits ahead)"
                (cd "$dir" && git push)
                pushed+=("${dir%/}")
            fi
        fi
    done
    if [[ ${#wip_blocked[@]} -gt 0 ]]; then
        echo ""
        echo "WIP-blocked (${#wip_blocked[@]}): ${wip_blocked[*]}"
        echo "Undo WIP commits first: just git wip-undo"
    fi
    if [[ ${#pushed[@]} -gt 0 ]]; then
        echo ""
        echo "Verify with: git -C <repo> log --oneline origin/<branch>..<branch>"
    fi

# Show diff of current branch vs origin/main
# Usage: just git diff-main [repo]   (omit repo to diff all repos with branches)
[no-cd]
[script]
diff-main repo='':
    set -uo pipefail
    if [[ -n "{{ repo }}" ]]; then
        dir="{{ repo }}"
        [[ "$dir" == "root" || "$dir" == "." ]] && dir="."
        if [[ "$dir" != "." && ! -d "$dir/.git" ]]; then
            echo "ERROR: $dir is not a git repo" >&2
            exit 1
        fi
        git -C "$dir" fetch origin main --quiet 2>/dev/null
        label="{{ repo }}"
        [[ "$dir" == "." ]] && label="vauchi (root)"
        echo "=== ${label} ==="
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
            branch=$(git -C "$dir" branch --show-current 2>/dev/null)
            [[ "$branch" == "main" || -z "$branch" ]] && continue
            git -C "$dir" fetch origin main --quiet 2>/dev/null
            count=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
            [[ "$count" == "0" ]] && continue
            echo "=== $label ($branch, $count commits) ==="
            git -C "$dir" diff origin/main...HEAD --stat
            echo ""
        done
    fi

# Rebase current branch on origin/main
# Usage: just git rebase-main [repo]   (omit repo to rebase all feature branches)
[no-cd]
[script]
rebase-main repo='':
    set -euo pipefail
    rebase_repo() {
        local label="$1" dir="$2"
        local branch
        branch=$(git -C "$dir" branch --show-current 2>/dev/null)
        if [[ "$branch" == "main" || -z "$branch" ]]; then
            return 0
        fi
        echo "=== $label ($branch) ==="
        git -C "$dir" fetch origin main --quiet 2>/dev/null
        local behind
        behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "0")
        if [[ "$behind" == "0" ]]; then
            echo "  Already up to date with origin/main"
            return 0
        fi
        echo "  $behind commits behind origin/main — rebasing..."
        if git -C "$dir" rebase origin/main 2>&1 | sed 's/^/  /'; then
            echo "  Rebase OK"
        else
            echo "  CONFLICT — resolve manually, then run: git -C $dir rebase --continue" >&2
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
    set -uo pipefail
    log_repo() {
        local label="$1" dir="$2"
        local branch
        branch=$(git -C "$dir" branch --show-current 2>/dev/null)
        [[ "$branch" == "main" || -z "$branch" ]] && return 0
        local count
        count=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
        [[ "$count" == "0" ]] && return 0
        echo "=== $label ($branch, $count commits) ==="
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
        git -C "$dir" fetch origin main --quiet 2>/dev/null
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
    set -uo pipefail
    sync_repo() {
        local label="$1" dir="$2"
        echo -n "$label: "
        git -C "$dir" fetch --all --quiet 2>/dev/null
        local branch
        branch=$(git -C "$dir" branch --show-current 2>/dev/null)
        if [[ "$branch" == "main" ]]; then
            output=$(git -C "$dir" pull --rebase --quiet 2>&1 || git -C "$dir" pull --quiet 2>&1)
            if echo "$output" | grep -q "Already up to date"; then
                echo "fetched, main up to date"
            else
                behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
                echo "fetched, pulled main ($output)"
            fi
        else
            local ahead behind
            ahead=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "?")
            behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
            echo "fetched (on $branch, ↑$ahead ↓$behind vs main)"
        fi
    }
    sync_repo "vauchi (root)" "."
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            sync_repo "${dir%/}" "$dir"
        fi
    done

# Show branch status for all repos (branch, ahead/behind, merged)
[no-cd]
[script]
branch-status:
    set -uo pipefail
    printf "%-20s %-30s %8s %8s %s\n" "REPO" "BRANCH" "AHEAD" "BEHIND" "MERGED?"
    printf "%-20s %-30s %8s %8s %s\n" "----" "------" "-----" "------" "-------"
    check_repo() {
        local label="$1" dir="$2"
        local branch ahead behind merged
        branch=$(git -C "$dir" branch --show-current 2>/dev/null || echo "detached")
        if [[ "$branch" == "main" ]]; then
            behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
            printf "%-20s %-30s %8s %8s %s\n" "$label" "main" "-" "$behind" "-"
            return
        fi
        ahead=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "?")
        behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "?")
        if git -C "$dir" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
            merged="yes"
        else
            merged="no"
        fi
        printf "%-20s %-30s %8s %8s %s\n" "$label" "$branch" "$ahead" "$behind" "$merged"
    }
    check_repo "vauchi (root)" "."
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            check_repo "${dir%/}" "$dir"
        fi
    done

# Show stashes across all repos
[no-cd]
[script]
stash-list:
    found=0
    # Root repo
    stashes=$(git stash list 2>/dev/null)
    if [[ -n "$stashes" ]]; then
        count=$(echo "$stashes" | wc -l | tr -d ' ')
        echo "=== vauchi (root) ($count) ==="
        echo "$stashes"
        echo ""
        found=1
    fi
    # Sub-repos
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            stashes=$(git -C "$dir" stash list 2>/dev/null)
            if [[ -n "$stashes" ]]; then
                count=$(echo "$stashes" | wc -l | tr -d ' ')
                echo "=== ${dir%/} ($count) ==="
                echo "$stashes"
                echo ""
                found=1
            fi
        fi
    done
    if [[ "$found" -eq 0 ]]; then
        echo "No stashes in any repo."
    fi

# Create a branch with the same name across repos
# If repos have uncommitted changes, prompts to save them first
# Usage: just git branch feature/my-feature core cli linux-gtk
#        just git branch feature/my-feature           (all repos)
[no-cd]
[script]
branch name *repos='':
    set -uo pipefail
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
        # All repos
        for dir in */; do
            [[ -d "${dir}.git" ]] && targets+=("${dir%/}")
        done
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
                            echo "  $label: WIP saved"
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
            echo -n "$label: branch exists, switching... "
            git -C "$dir" checkout "{{ name }}" --quiet 2>/dev/null
            echo "OK"
            created+=("$label")
        else
            echo -n "$label: creating {{ name }}... "
            git -C "$dir" checkout -b "{{ name }}" --quiet 2>/dev/null
            echo "OK"
            created+=("$label")
        fi
    done
    echo ""
    [[ ${#created[@]} -gt 0 ]] && echo "Branch '{{ name }}' active in: ${created[*]}"
    [[ ${#skipped[@]} -gt 0 ]] && echo "Skipped: ${skipped[*]}"
    exit 0

# ═══════════════════════════════════════════════════════════════════
# WIP - Save/restore in-progress work as commits (safer than stash)
# ═══════════════════════════════════════════════════════════════════

# Save work-in-progress as a commit on the current branch
# Unlike stash, WIP commits stay on the branch, show in git log, and can't be lost
# Usage: just git wip                          (all dirty repos, default message)
#        just git wip "fixing exchange bug"    (all dirty repos, custom message)
#        just git wip "" core cli              (specific repos, default message)
#        just git wip "my msg" core cli        (specific repos, custom message)
[no-cd]
[script]
wip msg='' *repos='':
    set -uo pipefail
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
        # All repos including root
        for dir in . */; do
            if [[ "$dir" == "." ]]; then
                gitdir=".git"
            else
                [[ ! -d "${dir}.git" ]] && continue
                gitdir="${dir}.git"
            fi
            if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
                if [[ "$dir" == "." ]]; then
                    targets+=(".")
                else
                    targets+=("${dir%/}")
                fi
            fi
        done
    fi

    if [[ ${#targets[@]} -eq 0 ]]; then
        echo "No dirty repos — nothing to save."
        exit 0
    fi

    timestamp=$(date +%Y%m%d-%H%M%S)
    branch=$(git -C "${targets[0]}" branch --show-current 2>/dev/null || echo "unknown")
    if [[ -n "{{ msg }}" ]]; then
        commit_msg="wip: {{ msg }}"
    else
        commit_msg="wip: checkpoint $timestamp"
    fi

    saved=()
    for dir in "${targets[@]}"; do
        label="$dir"
        [[ "$dir" == "." ]] && label="vauchi (root)"
        if [[ -z "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
            continue
        fi
        git -C "$dir" add -A
        git -C "$dir" commit -m "$commit_msg" --quiet --no-verify
        echo "$label: saved ($commit_msg)"
        saved+=("$label")
    done
    echo ""
    if [[ ${#saved[@]} -gt 0 ]]; then
        echo "Saved WIP in ${#saved[@]} repo(s): ${saved[*]}"
        echo "Undo with: just git wip-undo"
    fi

# Undo the last WIP commit (soft reset — keeps changes staged)
# Usage: just git wip-undo              (all repos with WIP commits)
#        just git wip-undo core cli     (specific repos)
[no-cd]
[script]
wip-undo *repos='':
    set -uo pipefail
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
        # All repos — only those whose HEAD is a wip: commit
        for dir in . */; do
            if [[ "$dir" == "." ]]; then
                [[ ! -d ".git" ]] && continue
            else
                [[ ! -d "${dir}.git" ]] && continue
            fi
            d="$dir"
            [[ "$dir" != "." ]] && d="${dir%/}"
            last_msg=$(git -C "$d" log -1 --format=%s 2>/dev/null || true)
            if [[ "$last_msg" == wip:* ]]; then
                targets+=("$d")
            fi
        done
    fi

    if [[ ${#targets[@]} -eq 0 ]]; then
        echo "No WIP commits found."
        exit 0
    fi

    undone=()
    skipped=()
    for dir in "${targets[@]}"; do
        label="$dir"
        [[ "$dir" == "." ]] && label="vauchi (root)"
        last_msg=$(git -C "$dir" log -1 --format=%s 2>/dev/null || true)
        if [[ "$last_msg" != wip:* ]]; then
            skipped+=("$label (HEAD is not a WIP commit)")
            continue
        fi
        git -C "$dir" reset --soft HEAD~1 --quiet
        echo "$label: undone WIP commit ($last_msg)"
        undone+=("$label")
    done
    echo ""
    [[ ${#undone[@]} -gt 0 ]] && echo "Undone in ${#undone[@]} repo(s): ${undone[*]}"
    [[ ${#skipped[@]} -gt 0 ]] && echo "Skipped: ${skipped[*]}"
    exit 0

# ═══════════════════════════════════════════════════════════════════
# RESUME - Return to a branch and undo WIP commits
# ═══════════════════════════════════════════════════════════════════

# Switch back to a branch and undo any WIP commits left there
# Usage: just git resume feature/my-feature              (all repos)
#        just git resume feature/my-feature core cli     (specific repos)
[no-cd]
[script]
resume name *repos='':
    set -uo pipefail
    if [[ -z "{{ name }}" ]]; then
        echo "Usage: just git resume <branch-name> [repo1 repo2 ...]" >&2
        exit 1
    fi

    # First: safety check — refuse if any target repo has uncommitted changes
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
        for dir in . */; do
            if [[ "$dir" == "." ]]; then
                [[ ! -d ".git" ]] && continue
                targets+=(".")
            else
                [[ ! -d "${dir}.git" ]] && continue
                targets+=("${dir%/}")
            fi
        done
    fi

    dirty=()
    for dir in "${targets[@]}"; do
        label="$dir"
        [[ "$dir" == "." ]] && label="vauchi (root)"
        if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
            dirty+=("$label")
        fi
    done
    if [[ ${#dirty[@]} -gt 0 ]]; then
        echo "ERROR: Uncommitted changes in: ${dirty[*]}" >&2
        echo "Save first with: just git wip" >&2
        exit 1
    fi

    # Switch to the branch
    switched=()
    for dir in "${targets[@]}"; do
        label="$dir"
        [[ "$dir" == "." ]] && label="vauchi (root)"
        current=$(git -C "$dir" branch --show-current 2>/dev/null)
        if [[ "$current" == "{{ name }}" ]]; then
            echo "$label: already on {{ name }}"
            switched+=("$dir")
            continue
        fi
        if git -C "$dir" rev-parse --verify "{{ name }}" &>/dev/null; then
            git -C "$dir" checkout "{{ name }}" --quiet 2>/dev/null
            echo "$label: switched to {{ name }}"
            switched+=("$dir")
        fi
    done

    # Undo WIP commits in switched repos
    wip_undone=()
    for dir in "${switched[@]}"; do
        label="$dir"
        [[ "$dir" == "." ]] && label="vauchi (root)"
        last_msg=$(git -C "$dir" log -1 --format=%s 2>/dev/null || true)
        if [[ "$last_msg" == wip:* ]]; then
            git -C "$dir" reset --soft HEAD~1 --quiet
            echo "$label: undone WIP commit ($last_msg)"
            wip_undone+=("$label")
        fi
    done
    echo ""
    echo "Resumed '{{ name }}' in ${#switched[@]} repo(s)"
    [[ ${#wip_undone[@]} -gt 0 ]] && echo "Restored WIP changes in: ${wip_undone[*]}"
    exit 0

# ═══════════════════════════════════════════════════════════════════
# STALE BRANCHES - Find branches with no recent activity
# ═══════════════════════════════════════════════════════════════════

# Show branches with no commits in N days (default: 14)
# Usage: just git stale-branches         (14-day threshold)
#        just git stale-branches 7       (7-day threshold)
[no-cd]
[script]
stale-branches days='14':
    set -uo pipefail
    threshold="{{ days }}"
    cutoff=$(date -d "$threshold days ago" +%s 2>/dev/null || date -v-${threshold}d +%s 2>/dev/null)

    # Fetch so origin/main is current for status checks
    for dir in . */; do
        [[ "$dir" == "." ]] && gitdir=".git" || gitdir="${dir}.git"
        [[ -d "$gitdir" ]] && git -C "$dir" fetch origin main --quiet 2>/dev/null &
    done
    wait

    printf "%-20s %-30s %-12s %-6s %s\n" "REPO" "BRANCH" "LAST COMMIT" "AGE" "STATUS"
    printf "%-20s %-30s %-12s %-6s %s\n" "----" "------" "-----------" "---" "------"

    total=0
    deletable=0
    for dir in . */; do
        if [[ "$dir" == "." ]]; then
            [[ ! -d ".git" ]] && continue
            label="vauchi (root)"
            d="."
        else
            [[ ! -d "${dir}.git" ]] && continue
            label="${dir%/}"
            d="${dir%/}"
        fi

        branches=$(git -C "$d" branch --no-color 2>/dev/null | grep -v 'main$' | sed 's/^[* ]*//' || true)
        [[ -z "$branches" ]] && continue

        while IFS= read -r br; do
            [[ -z "$br" ]] && continue
            last_epoch=$(git -C "$d" log -1 --format=%ct "$br" 2>/dev/null || echo "0")
            last_date=$(git -C "$d" log -1 --format=%ci "$br" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
            if [[ "$last_epoch" -lt "$cutoff" ]]; then
                now=$(date +%s)
                age_days=$(( (now - last_epoch) / 86400 ))
                # Check if content is already in main (merged or squash-merged)
                status="unmerged"
                if git -C "$d" merge-base --is-ancestor "$br" origin/main 2>/dev/null; then
                    status="merged"
                elif git -C "$d" diff --quiet origin/main..."$br" -- 2>/dev/null; then
                    status="in-main"
                fi
                if [[ "$status" != "unmerged" ]]; then
                    deletable=$((deletable + 1))
                fi
                printf "%-20s %-30s %-12s %-6s %s\n" "$label" "$br" "$last_date" "${age_days}d" "$status"
                total=$((total + 1))
            fi
        done <<< "$branches"
    done

    echo ""
    if [[ "$total" -eq 0 ]]; then
        echo "No branches older than ${threshold} days."
    else
        echo "$total stale branch(es) (no commits in ${threshold}+ days)"
        if [[ "$deletable" -gt 0 ]]; then
            echo "$deletable already in main — safe to delete"
        fi
        echo "Clean up with: just git cleanup run"
    fi
