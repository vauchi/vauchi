# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Git worktree management for parallel multi-repo development
# Worktrees let you work on multiple branches simultaneously without switching
# Usage: just worktree <recipe>
#
# Directory structure: .worktrees/<flat-name>/<repo>/
# Branch names are flattened: bugfix/crash-fix → bugfix--crash-fix

[group('tests')]
test:
    python3 "{{ justfile_directory() }}/tests/test_worktree_recipe.py" "{{ justfile_directory() }}/just/worktree.just"

# Create a worktree for parallel development across repos
# Each worktree is a separate directory with its own checkout
# Usage: just worktree create bugfix/crash-fix              (all repos)
#        just worktree create bugfix/crash-fix core cli      (specific repos)
[no-cd]
create name *repos='':
    #!/usr/bin/env bash
    source scripts/scripts/output-helpers.sh
    set -euo pipefail
    if [[ -z "{{ name }}" ]]; then
        echo "Usage: just worktree create <branch-name> [repo1 repo2 ...]" >&2
        exit 1
    fi

    # Flatten branch name for directory (bugfix/crash-fix → bugfix--crash-fix)
    flat_name=$(echo "{{ name }}" | sed 's|/|--|g')
    wt_base=".worktrees/$flat_name"

    if [[ -d "$wt_base" ]]; then
        echo "ERROR: Worktree '$wt_base' already exists." >&2
        echo "List worktrees: just worktree list" >&2
        echo "Remove it first: just worktree remove {{ name }}" >&2
        exit 1
    fi

    source scripts/scripts/for-each-repo.sh
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
        # All sub-repos
        _collect_target() { targets+=("$2"); }
        for_each_repo --no-root _collect_target
    fi

    # Root first, at the base itself, so the other repos nest inside it as in
    # the real workspace; otherwise root's .claude -> _private/.claude dangles.
    has_root=false
    ordered=()
    for dir in "${targets[@]}"; do
        if [[ "$dir" == "." ]]; then has_root=true; else ordered+=("$dir"); fi
    done
    $has_root && targets=("." ${ordered[@]+"${ordered[@]}"})

    mkdir -p "$wt_base"

    created=()
    failed=()
    for dir in "${targets[@]}"; do
        label="$dir"
        [[ "$dir" == "." ]] && label="root"

        if [[ "$dir" == "." ]]; then
            wt_path="$wt_base"
        else
            wt_path="$wt_base/$label"
        fi

        if git -C "$dir" show-ref --verify --quiet "refs/heads/{{ name }}"; then
            # Preserve an existing branch exactly as-is.
            if git -C "$dir" worktree add "$(pwd)/$wt_path" "{{ name }}" --quiet 2>/dev/null; then
                status_ok "$label" "created (existing branch, $wt_path)"
                created+=("$label")
            else
                status_fail "$label" "FAILED"
                failed+=("$label")
                rmdir "$wt_path" 2>/dev/null || true
            fi
        elif git -C "$dir" fetch origin \
              "refs/heads/{{ name }}:refs/remotes/origin/{{ name }}" --quiet 2>/dev/null; then
            # A remote-only branch is existing work too; attach it rather than
            # creating a divergent branch with the same name from main.
            if git -C "$dir" worktree add "$(pwd)/$wt_path" -b "{{ name }}" \
                  --track "origin/{{ name }}" --quiet 2>/dev/null; then
                status_ok "$label" "created (remote branch, $wt_path)"
                created+=("$label")
            else
                status_fail "$label" "FAILED"
                failed+=("$label")
                rmdir "$wt_path" 2>/dev/null || true
            fi
        elif git -C "$dir" fetch origin main --quiet && \
              git -C "$dir" worktree add "$(pwd)/$wt_path" -b "{{ name }}" origin/main --quiet 2>/dev/null; then
            # New work starts from the freshly fetched shared base.
            status_ok "$label" "created ($wt_path)"
            created+=("$label")
        else
            status_fail "$label" "FAILED"
            failed+=("$label")
            rmdir "$wt_path" 2>/dev/null || true
        fi
    done

    # Written after the root worktree exists: git worktree add needs an empty base.
    echo "{{ name }}" > "$wt_base/.branch-name"

    echo ""
    if [[ ${#created[@]} -gt 0 ]]; then
        echo "Worktree '{{ name }}' created in ${#created[@]} repo(s): ${created[*]}"
        echo ""
        echo "Work in:  $wt_base/<repo>/"
        echo "Return:   just worktree remove {{ name }}"
        echo ""
        echo "Example:  cd $wt_base/core && cargo test"
    fi
    [[ ${#failed[@]} -gt 0 ]] && echo "Failed: ${failed[*]}"
    exit 0

# List all worktrees across repos
[no-cd]
list:
    #!/usr/bin/env bash
    source scripts/scripts/output-helpers.sh
    set -euo pipefail
    wt_base=".worktrees"

    if [[ ! -d "$wt_base" ]]; then
        echo "No worktrees. Create one with: just worktree create <branch>"
        exit 0
    fi

    total=0
    for wt_dir in "$wt_base"/*/; do
        [[ ! -d "$wt_dir" ]] && continue
        flat_name=$(basename "$wt_dir")

        # Read original branch name if available
        if [[ -f "$wt_dir/.branch-name" ]]; then
            name=$(cat "$wt_dir/.branch-name")
        else
            name="$flat_name"
        fi
        echo "── $name ──"

        repo_count=0
        for repo_dir in "$wt_dir"/*/; do
            [[ -e "$repo_dir/.git" ]] || continue
            repo=$(basename "$repo_dir")
            branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null || echo "detached")
            status=$(git -C "$repo_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
            dirty=""
            [[ "$status" -gt 0 ]] && dirty=" ($status uncommitted)"
            status_ok "$repo" "$branch$dirty"
            repo_count=$((repo_count + 1))
        done
        # Check for root worktree (not in a subdirectory)
        if [[ -f "$wt_dir/.git" ]]; then
            branch=$(git -C "$wt_dir" branch --show-current 2>/dev/null || echo "detached")
            status=$(git -C "$wt_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
            dirty=""
            [[ "$status" -gt 0 ]] && dirty=" ($status uncommitted)"
            status_ok "root" "$branch$dirty"
            repo_count=$((repo_count + 1))
        fi
        echo "  ($repo_count repos)"
        echo ""
        total=$((total + 1))
    done

    if [[ "$total" -eq 0 ]]; then
        echo "No worktrees. Create one with: just worktree create <branch>"
    else
        echo "$total worktree(s) in $wt_base/"
    fi

# Remove a worktree and clean up
# Usage: just worktree remove bugfix/crash-fix
[no-cd]
remove name:
    #!/usr/bin/env bash
    source scripts/scripts/output-helpers.sh
    set -euo pipefail
    if [[ -z "{{ name }}" ]]; then
        echo "Usage: just worktree remove <branch-name>" >&2
        exit 1
    fi

    flat_name=$(echo "{{ name }}" | sed 's|/|--|g')
    wt_base=".worktrees/$flat_name"

    if [[ ! -d "$wt_base" ]]; then
        echo "ERROR: Worktree directory '$wt_base' does not exist." >&2
        echo "List worktrees: just worktree list" >&2
        exit 1
    fi

    # Check for uncommitted changes in worktree repos
    dirty=()
    for repo_dir in "$wt_base"/*/; do
        [[ -e "$repo_dir/.git" ]] || continue
        repo=$(basename "$repo_dir")
        if [[ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]]; then
            dirty+=("$repo")
        fi
    done
    if [[ -f "$wt_base/.git" ]]; then
        if [[ -n "$(git -C "$wt_base" status --porcelain 2>/dev/null)" ]]; then
            dirty+=("root")
        fi
    fi

    if [[ ${#dirty[@]} -gt 0 ]]; then
        echo "WARNING: Uncommitted changes in worktree: ${dirty[*]}"
        if [[ -t 0 ]]; then
            read -rp "Remove anyway? Changes will be LOST. [y/N] " answer
            if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
                echo "Aborted. Commit or stash changes in the worktree first."
                exit 0
            fi
        else
            echo "ERROR: Non-interactive shell — commit or discard changes first." >&2
            exit 1
        fi
    fi

    # Remove worktrees from each parent repo
    removed=()
    wt_failed=()
    for repo_dir in "$wt_base"/*/; do
        [[ ! -d "$repo_dir" ]] && continue
        repo=$(basename "$repo_dir")
        abs_path="$(cd "$repo_dir" && pwd)"
        if [[ -d "$repo/.git" ]]; then
            if git -C "$repo" worktree remove "$abs_path" --force 2>/dev/null; then
                removed+=("$repo")
            else
                wt_failed+=("$repo")
            fi
        elif [[ "$repo" == "root" && -d ".git" ]]; then
            if git worktree remove "$abs_path" --force 2>/dev/null; then
                removed+=("root")
            else
                wt_failed+=("root")
            fi
        fi
    done
    if [[ -f "$wt_base/.git" ]]; then
        abs_path="$(cd "$wt_base" && pwd)"
        if git worktree remove "$abs_path" --force 2>/dev/null; then
            removed+=("root")
        else
            wt_failed+=("root")
        fi
    fi

    rm -rf "$wt_base"
    rmdir .worktrees 2>/dev/null || true

    echo "Removed worktree '{{ name }}' (${#removed[@]} repos: ${removed[*]:-none})"
    if [[ ${#wt_failed[@]} -gt 0 ]]; then
        echo "WARNING: git worktree remove failed for: ${wt_failed[*]} — run: git worktree prune in those repos"
    fi

    # Optionally delete the branch too
    if [[ -t 0 ]]; then
        source scripts/scripts/for-each-repo.sh
        read -rp "Also delete branch '{{ name }}'? [y/N] " answer
        if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
            _delete_branch() {
                local label="$1" dir="$2"
                if git -C "$dir" branch -d "{{ name }}" 2>/dev/null; then
                    status_ok "$label" "deleted branch '{{ name }}'"
                fi
            }
            for_each_repo _delete_branch
        fi
    fi

# Remove a worktree non-interactively (for automation/Claude)
# Usage: just worktree remove-force bugfix/crash-fix
[no-cd]
remove-force name:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{ name }}" ]]; then
        echo "Usage: just worktree remove-force <branch-name>" >&2
        exit 1
    fi

    flat_name=$(echo "{{ name }}" | sed 's|/|--|g')
    wt_base=".worktrees/$flat_name"

    if [[ ! -d "$wt_base" ]]; then
        echo "ERROR: Worktree directory '$wt_base' does not exist." >&2
        exit 1
    fi

    # Remove worktrees from each parent repo
    removed=()
    wt_failed=()
    for repo_dir in "$wt_base"/*/; do
        [[ ! -d "$repo_dir" ]] && continue
        repo=$(basename "$repo_dir")
        abs_path="$(cd "$repo_dir" && pwd)"
        if [[ -d "$repo/.git" ]]; then
            if git -C "$repo" worktree remove "$abs_path" --force 2>/dev/null; then
                removed+=("$repo")
            else
                wt_failed+=("$repo")
            fi
        elif [[ "$repo" == "root" && -d ".git" ]]; then
            if git worktree remove "$abs_path" --force 2>/dev/null; then
                removed+=("root")
            else
                wt_failed+=("root")
            fi
        fi
    done
    if [[ -f "$wt_base/.git" ]]; then
        abs_path="$(cd "$wt_base" && pwd)"
        if git worktree remove "$abs_path" --force 2>/dev/null; then
            removed+=("root")
        else
            wt_failed+=("root")
        fi
    fi

    rm -rf "$wt_base"
    rmdir .worktrees 2>/dev/null || true
    echo "Removed worktree '{{ name }}' (${#removed[@]} repos: ${removed[*]:-none})"
    if [[ ${#wt_failed[@]} -gt 0 ]]; then
        echo "WARNING: git worktree remove failed for: ${wt_failed[*]} — run: git worktree prune in those repos"
    fi
