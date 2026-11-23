# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# WIP & Resume — save/restore in-progress work as commits (safer than stash)

# Save work-in-progress as a commit on the current branch
# Unlike stash, WIP commits stay on the branch, show in git log, and can't be lost
# Usage: just git wip                          (all dirty repos, default message)
#        just git wip "fixing exchange bug"    (all dirty repos, custom message)
#        just git wip "" core cli-display      (specific repos, default message)
#        just git wip "my msg" core cli-display (specific repos, custom message)
[no-cd]
[script]
wip msg='' *repos='':
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/for-each-repo.sh
    set -euo pipefail
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
        # All repos including root — collect dirty ones. Repos whose only
        # changes are path-override churn are skipped: WIP-committing the
        # fence is how it ends up on protected mains (--no-verify below
        # bypasses the pre-commit guard). Explicit `just git wip <repo>`
        # still takes the repo as-is.
        _collect_dirty() {
            local label="$1" dir="$2"
            if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
                if scripts/scripts/override-only-changes.sh "$dir" >/dev/null 2>&1; then
                    echo "  · $label: only path-override churn — skipped"
                else
                    targets+=("$dir")
                fi
            fi
        }
        for_each_repo _collect_dirty
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
        status_ok "$label" "saved ($commit_msg)"
        saved+=("$label")
    done
    echo ""
    if [[ ${#saved[@]} -gt 0 ]]; then
        echo "Saved WIP in ${#saved[@]} repo(s): ${saved[*]}"
        echo "Undo with: just git wip-undo"
    fi

# Undo the last WIP commit (soft reset — keeps changes staged)
# Usage: just git wip-undo              (all repos with WIP commits)
#        just git wip-undo core cli-display (specific repos)
[no-cd]
[script]
wip-undo *repos='':
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/for-each-repo.sh
    set -euo pipefail
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
        _collect_wip() {
            local label="$1" dir="$2"
            local last_msg
            last_msg=$(git -C "$dir" log -1 --format=%s 2>/dev/null || true)
            if [[ "$last_msg" == wip:* ]]; then
                targets+=("$dir")
            fi
        }
        for_each_repo _collect_wip
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
        status_ok "$label" "undone WIP ($last_msg)"
        undone+=("$label")
    done
    echo ""
    [[ ${#undone[@]} -gt 0 ]] && echo "Undone in ${#undone[@]} repo(s): ${undone[*]}"
    [[ ${#skipped[@]} -gt 0 ]] && echo "Skipped: ${skipped[*]}"
    exit 0

# Switch back to a branch and undo any WIP commits left there
# Usage: just git resume feature/my-feature              (all repos)
#        just git resume feature/my-feature core cli-display (specific repos)
[no-cd]
[script]
resume name *repos='':
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/for-each-repo.sh
    set -euo pipefail
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
        _collect_all() {
            local label="$1" dir="$2"
            targets+=("$dir")
        }
        for_each_repo _collect_all
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
        current=$(git -C "$dir" branch --show-current 2>/dev/null || echo "")
        if [[ "$current" == "{{ name }}" ]]; then
            status_info "$label" "already on {{ name }}"
            switched+=("$dir")
            continue
        fi
        if git -C "$dir" rev-parse --verify "{{ name }}" &>/dev/null; then
            if git -C "$dir" checkout "{{ name }}" --quiet 2>/dev/null; then
                status_ok "$label" "switched to {{ name }}"
                switched+=("$dir")
            else
                echo "  WARN: checkout failed for $label" >&2
            fi
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
            status_ok "$label" "restored WIP ($last_msg)"
            wip_undone+=("$label")
        fi
    done
    echo ""
    echo "Resumed '{{ name }}' in ${#switched[@]} repo(s)"
    [[ ${#wip_undone[@]} -gt 0 ]] && echo "Restored WIP changes in: ${wip_undone[*]}"
    exit 0
