# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Multi-repo git commands
# Usage: just git <recipe>

# Stash changes, checkout main, and pull latest in all repos
# Usage: just git main          (interactive — prompts before stashing)
#        just git main yes      (non-interactive — auto-stash without prompting)
[no-cd]
[script('bash')]
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

    if [[ ${#dirty_repos[@]} -gt 0 ]]; then
        echo "The following repos have uncommitted changes that will be stashed:"
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
        else
            read -rp "Stash these changes and switch to main? [y/N] " answer
            if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
                echo "Aborted."
                exit 0
            fi
        fi
        echo ""
    fi

    # Second pass: stash, checkout main, and pull
    switch_to_main() {
        local label="$1"
        local dir="$2"
        echo -n "$label: "
        cd "$dir" || return 1
        # Stash if dirty
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            git stash push -m "auto-stash before switching to main" --quiet
            echo -n "(stashed) "
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
        merged=$(git -C "$dir" branch --merged main 2>/dev/null \
            | grep -vE '^\*|^[[:space:]]+main$' \
            | sed 's/^[[:space:]]*//' || true)
        [[ -z "$merged" ]] && return 0
        while IFS= read -r b; do
            [[ -z "$b" ]] && continue
            if git -C "$dir" branch -d "$b" &>/dev/null; then
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
[script('bash')]
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
[script('bash')]
checkout-main:
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            echo -n "${dir%/}: "
            (cd "$dir" && git checkout main 2>&1) | tail -1
        fi
    done

# Fetch all repos
[no-cd]
[script('bash')]
fetch:
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            echo -n "${dir%/}: "
            (cd "$dir" && git fetch --all 2>&1) | grep -E "^Fetching|error|fatal" || echo "up to date"
        fi
    done

# Show branches across all repos
[no-cd]
[script('bash')]
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
[script('bash')]
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

        # Local branches merged into main (exclude current branch and main itself)
        local_branches=$(git -C "$dir" branch --merged main 2>/dev/null \
            | grep -vE '^\*|^[[:space:]]+main$' \
            | sed 's/^[[:space:]]*//' || true)

        # Remote branches merged into main (exclude main and HEAD pointer)
        remote_branches=$(git -C "$dir" branch -r --merged main 2>/dev/null \
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
                    if git -C "$dir" branch -d "$b" &>/dev/null; then
                        echo "    deleted  $b"
                    else
                        echo "    FAILED   $b (checked out or not fully merged)"
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
[script('bash')]
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
[script('bash')]
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
[script('bash')]
push-all mode='full':
    if [[ "{{ mode }}" == "skip-tests" ]]; then
        export SKIP_TESTS=1
        echo "Pushing with SKIP_TESTS=1 (fmt + clippy only)"
        echo ""
    fi
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            ahead=$(cd "$dir" && git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
            if [[ "$ahead" -gt 0 ]]; then
                echo "Pushing ${dir%/} ($ahead commits ahead)"
                (cd "$dir" && git push)
            fi
        fi
    done

# Show diff of current branch vs origin/main
# Usage: just git diff-main [repo]   (omit repo to diff all repos with branches)
[no-cd]
[script('bash')]
diff-main repo='':
    set -uo pipefail
    if [[ -n "{{ repo }}" ]]; then
        dir="{{ repo }}"
        [[ "$dir" == "root" || "$dir" == "." ]] && dir="."
        [[ "$dir" == "desktop" ]] && dir="desktop"
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
[script('bash')]
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
[script('bash')]
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
[script('bash')]
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
[script('bash')]
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
[script('bash')]
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
# Usage: just git branch feature/my-feature core cli desktop
#        just git branch feature/my-feature           (all repos)
[no-cd]
[script('bash')]
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
