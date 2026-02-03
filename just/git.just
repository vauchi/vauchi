# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Multi-repo git commands
# Usage: just git <recipe>

# Stash changes, checkout main, and pull latest in all repos
[no-cd]
[script('bash')]
main:
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
    echo "Tip: run 'just git fetch' first to ensure remote state is current"
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
[no-cd]
[script('bash')]
push-all:
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            ahead=$(cd "$dir" && git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
            if [[ "$ahead" -gt 0 ]]; then
                echo "Pushing $dir ($ahead commits ahead)"
                (cd "$dir" && git push)
            fi
        fi
    done
