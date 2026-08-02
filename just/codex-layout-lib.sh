# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# shellcheck shell=bash
# Sourced by session-init/session-end, never executed — no shebang to infer
# the dialect from, so declare it for shellcheck (SC2148).

# Workspace .codex layout invariant. The canonical tree still lives in
# _private/.codex, but the workspace root entry must be a REAL DIRECTORY
# whose children are symlinks into it — not a symlink like .claude.
#
# Why the shapes differ: Codex bind-mounts <workspace>/.codex read-only, and
# bubblewrap refuses to enforce a read-only path that crosses a writable
# symlink. With .codex a symlink, EVERY sandboxed command dies with:
#
#   error building bubblewrap command: Fatal error: cannot enforce sandbox
#   read-only path <root>/.codex because it crosses writable symlink
#
# read-only mode is unaffected, which is why this hid for so long.
#
# SCOPE — this is a startup-compatibility fix, NOT a security control. The
# read-only bind protects the directory ENTRIES (a sandboxed session cannot
# create .codex/newhook.sh), but every entry is a symlink into _private, which
# is inside the writable workspace. Measured behaviour:
#
#   create .codex/newhook.sh   -> blocked (read-only file system)
#   append .codex/config.toml  -> SUCCEEDS (writes through the link)
#   append _private/.codex/*   -> SUCCEEDS
#
# So a sandboxed session CAN still rewrite its own hooks and config mid-turn.
# The upstream protection cannot hold while the canonical tree lives in a
# writable path; restoring it would mean moving the tree out of the workspace
# or giving _private/.codex its own read-only bind. Do not cite this layout as
# a self-modification guard. .agents/skills has the identical hole.
#
# .claude and .kimi-code stay symlinks: neither Claude Code nor Kimi bind-mounts
# its config dir, so neither hits the bubblewrap failure. That asymmetry is a
# per-tool compatibility fact, not a pattern to copy — check the new tool's
# sandbox behaviour before assuming either shape.
#
# Returns 0 when the layout is sound, 1 when an issue needs a human.
# Prints two-space-indented lines matching the session recipes' style.

# Populate .codex with one relative symlink per _private/.codex entry.
# Deriving the list from the canonical tree means a new file there needs no
# change here. Returns 1 if any link could not be created.
_codex_link_entries() {
    local created="${1:-}"
    local issues=0 entry name target

    for entry in _private/.codex/*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        name=$(basename "$entry")
        target="../_private/.codex/$name"

        if [[ -L ".codex/$name" ]]; then
            [[ "$(readlink ".codex/$name")" == "$target" ]] && continue
            rm -f ".codex/$name"
        elif [[ -e ".codex/$name" ]]; then
            echo "  WARNING: .codex/$name is a real file — expected symlink to $target"
            issues=1
            continue
        fi

        if ln -s "$target" ".codex/$name"; then
            [[ -n "$created" ]] && echo "  Repaired: .codex/$name → $target"
        else
            echo "  ERROR: could not create .codex/$name → $target"
            issues=1
        fi
    done

    return $issues
}

check_codex_layout() {
    local issues=0

    if [[ ! -d _private/.codex ]]; then
        echo "  ERROR: _private/.codex does not exist — is _private cloned?"
        return 1
    fi

    if [[ -L .codex ]]; then
        # The sandbox-breaking shape. Converting is safe and lossless: every
        # byte lives in _private/.codex and only the root entry changes.
        rm -f .codex
        mkdir -p .codex
        _codex_link_entries || issues=1
        echo "  Repaired: .codex symlink → real directory with symlinked entries"
    elif [[ -d .codex ]]; then
        _codex_link_entries repair || issues=1
    else
        mkdir -p .codex
        _codex_link_entries || issues=1
        echo "  Repaired: created .codex directory with symlinked entries"
    fi

    # Strays: anything in .codex without a counterpart in the canonical tree
    # is content that will never be tracked, since _private owns the source.
    local link name
    for link in .codex/* .codex/.[!.]*; do
        [[ -e "$link" || -L "$link" ]] || continue
        name=$(basename "$link")
        if [[ ! -e "_private/.codex/$name" && ! -L "_private/.codex/$name" ]]; then
            echo "  WARNING: stray .codex/$name has no _private/.codex counterpart"
            echo "  → move it into _private/.codex/, then re-run"
            issues=1
        fi
    done

    # The config must resolve through the links, not merely exist as a dangling
    # symlink — a broken chain here silently drops every project hook.
    if [[ ! -f .codex/config.toml ]]; then
        echo "  WARNING: .codex/config.toml not readable through the links"
        issues=1
    fi

    return $issues
}
