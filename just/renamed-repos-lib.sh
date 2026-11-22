#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Sourced by session-init and clone-repos. A repository renamed in GitLab
# keeps its old directory in every slot cloned before the rename, and the
# registry (repos.toml) names the new one. Cloning the new name beside the
# old checkout would leave two copies, the old one holding the branches
# and local work.

# old:new, one pair per renamed repository (ADR-078, private#1029, private#1234).
RENAMED_REPO_DIRS=(
    "linux-gtk:gtk-display"
    "linux-qt:qt-display"
    "windows:windows-app"
)

# migrate_renamed_repo_dirs <workspace root>
# Moves each old checkout to its new name and points an origin that named
# the old project at the new one. Exit 1 when both directories exist (which
# one holds the work is not this function's call) or the OS refuses the move.
migrate_renamed_repo_dirs() {
    local root="$1" pair old new url refused=0
    for pair in "${RENAMED_REPO_DIRS[@]}"; do
        old="${pair%%:*}"
        new="${pair##*:}"
        [[ -e "$root/$old/.git" ]] || continue
        if [[ -e "$root/$new" ]]; then
            echo "  ERROR: both $old and $new exist in $root; move the work you need into $new, then remove $old" >&2
            refused=1
            continue
        fi
        if ! mv "$root/$old" "$root/$new"; then
            # Windows refuses to rename a folder a process has open.
            echo "  ERROR: could not move $old to $new in $root; close what holds $old open, then run session-init again" >&2
            refused=1
            continue
        fi
        url=$(git -C "$root/$new" config --get remote.origin.url || true)
        case "$url" in
            *"vauchi/$old.git" | *"vauchi/$old")
                git -C "$root/$new" remote set-url origin "${url/vauchi\/$old/vauchi\/$new}"
                ;;
        esac
        echo "  $old -> $new (renamed repository; build directories with absolute paths need a reconfigure)"
    done
    return "$refused"
}
