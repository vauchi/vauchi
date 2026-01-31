# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Multi-repo git commands
# Usage: just git <recipe>

# Stash changes, checkout main, and pull latest in all repos
[no-cd]
main:
    #!/usr/bin/env bash
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
status:
    #!/usr/bin/env bash
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
checkout-main:
    #!/usr/bin/env bash
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            echo -n "${dir%/}: "
            (cd "$dir" && git checkout main 2>&1) | tail -1
        fi
    done

# Fetch all repos
[no-cd]
fetch:
    #!/usr/bin/env bash
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            echo -n "${dir%/}: "
            (cd "$dir" && git fetch --all 2>&1) | grep -E "^Fetching|error|fatal" || echo "up to date"
        fi
    done

# Show branches across all repos
[no-cd]
branches:
    #!/usr/bin/env bash
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            branch=$(cd "$dir" && git branch --show-current 2>/dev/null)
            branches=$(cd "$dir" && git branch --list 2>/dev/null | wc -l)
            echo "${dir%/}: ${branch:-detached} ($branches branches)"
        fi
    done

# Delete merged branches in all repos
[no-cd]
clean-branches:
    #!/usr/bin/env bash
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            merged=$(cd "$dir" && git branch --merged main 2>/dev/null | grep -v "^\*\|main" | wc -l)
            if [[ "$merged" -gt 0 ]]; then
                echo "=== ${dir%/} ==="
                (cd "$dir" && git branch --merged main | grep -v "^\*\|main" | xargs -r git branch -d)
            fi
        fi
    done
    echo "Done!"

# Pull latest changes from all repos
[no-cd]
pull-all:
    #!/usr/bin/env bash
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            echo -n "${dir%/}: "
            (cd "$dir" && git pull --rebase 2>&1) || (cd "$dir" && git pull 2>&1) || echo "FAILED"
        fi
    done

# Push all repos with commits ahead of origin
[no-cd]
push-all:
    #!/usr/bin/env bash
    for dir in */; do
        if [[ -d "${dir}.git" ]]; then
            ahead=$(cd "$dir" && git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
            if [[ "$ahead" -gt 0 ]]; then
                echo "Pushing $dir ($ahead commits ahead)"
                (cd "$dir" && git push)
            fi
        fi
    done
