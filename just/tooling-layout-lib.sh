# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# shellcheck shell=bash
# Sourced by session-init, never executed: no shebang to infer the
# dialect from, so declare it for shellcheck (SC2148).

# The tools and forks live under utils/ and come from the vauchi/utils
# subgroup (private#1034). A slot set up before that move keeps its clones
# at the workspace root with personal-namespace remotes; the hooks and
# recipes then stop seeing the tool, and nothing says so.
#
# Arguments: the justfile's tooling_repos entries, each "<url>,<path>".
# Warns only: moving or repointing a clone is left to a human, since the
# clone may hold work. Returns 0 when the layout is sound, 1 otherwise.

check_tooling_layout() {
    local issues=0 entry url path name actual
    for entry in "$@"; do
        url=${entry%%,*}
        path=${entry#*,}
        name=${path##*/}
        if [[ -d "$name/.git" && "$name" != "$path" ]]; then
            echo "  WARNING: $name/ is at the workspace root; it belongs in $path →"
            echo "    mkdir -p ${path%/*} && mv $name $path && git -C $path remote set-url origin $url"
            issues=1
            continue
        fi
        if [[ ! -d "$path/.git" ]]; then
            echo "  WARNING: $path/ missing → git clone $url $path"
            issues=1
            continue
        fi
        actual=$(git -C "$path" remote get-url origin 2>/dev/null || echo none)
        if [[ ! "$actual" =~ [:/]vauchi/utils/$name(\.git)?$ ]]; then
            echo "  WARNING: $path pulls from $actual →"
            echo "    git -C $path remote set-url origin $url && git -C $path fetch origin"
            issues=1
        fi
    done
    return "$issues"
}
