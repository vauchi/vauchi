# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Workspace .claude layout invariant (CLAUDE.md §Dependencies & Repo
# Layout): the real config tree lives in _private/.claude; the root
# .claude is a relative symlink so Claude Code — which only discovers
# project config at the workspace root — still loads it. Sourced by
# session-init (warns + repairs) and session-end (gates).
#
# Returns 0 when the layout is sound, 1 when an issue needs a human.
# Prints two-space-indented lines matching the session recipes' style.

check_claude_layout() {
    local issues=0

    if [[ -L .claude ]]; then
        local target
        target=$(readlink .claude)
        if [[ "$target" != "_private/.claude" ]]; then
            echo "  WARNING: .claude → $target (expected _private/.claude)"
            issues=1
        fi
    elif [[ -d .claude ]]; then
        echo "  WARNING: .claude is a real directory — expected symlink to _private/.claude"
        echo "  → merge contents into _private/.claude, then:"
        echo "    rm -rf .claude && ln -s _private/.claude .claude"
        issues=1
    elif [[ -d _private/.claude ]]; then
        ln -s _private/.claude .claude
        echo "  Repaired: created .claude → _private/.claude symlink"
    else
        echo "  ERROR: neither .claude nor _private/.claude exists — is _private cloned?"
        issues=1
    fi

    if [[ ! -f .claude/settings.json ]]; then
        echo "  WARNING: .claude/settings.json not found through the symlink"
        issues=1
    fi

    # Stray .claude dirs: agents running with a sub-repo or subdir cwd
    # leave worktrees/agent-memory scratch behind — at sub-repo roots
    # and nested deeper (e.g. _private/docs/planning/todo/.claude).
    # Empty scratch is removed silently; anything with files needs a
    # human decision. Root .claude is a symlink, so -type d skips it.
    local d
    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        [[ "$d" == "./_private/.claude" ]] && continue
        if [[ -z $(find "$d" -type f 2>/dev/null | head -1) ]]; then
            rm -rf "$d"
            echo "  Removed empty stray $d"
        else
            echo "  WARNING: stray $d contains files:"
            find "$d" -type f 2>/dev/null | head -5 | sed 's/^/    /'
            echo "  → move agent memory into _private/.claude/agent-memory/, then remove $d"
            issues=1
        fi
    done < <(find . -maxdepth 5 \
        \( -name node_modules -o -name target -o -name build \
           -o -name .git -o -name worktrees -o -name .derived-data \
           -o -name .spm-packages \) -prune \
        -o -type d -name .claude -print 2>/dev/null)

    return $issues
}
