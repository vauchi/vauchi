#!/bin/sh
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: blog-publish.sh <drafts-dir> <content-dir> <slug> <YYYY-MM-DD>
# Writes the draft whose front matter has slug = "<slug>" to
# <content-dir>/<slug>.md, dated and without the draft flag, and prints
# its path. Drafts live in the private repo and posts in the public one
# (vauchi/private#822), so anything that points at internals is refused.
set -eu

drafts_dir=$1
content_dir=$2
slug=$3
publish_date=$4

fail() {
    printf 'blog-publish: %s\n' "$1" >&2
    exit 1
}

case $slug in
    '' | *[!a-z0-9-]*) fail "slug must be lowercase letters, digits and dashes: '$slug'" ;;
esac

draft=$(grep -l -x "slug = \"$slug\"" "$drafts_dir"/*.md 2>/dev/null | head -n 1 || true)
[ -n "$draft" ] || fail "no draft with slug $slug in $drafts_dir"

target=$content_dir/$slug.md
[ ! -e "$target" ] || fail "$slug is already published at $target"

leaks=$(grep -n -E '_private/|ADR-[0-9]|[a-z-]+![0-9]+|\.claude' "$draft" || true)
[ -z "$leaks" ] || fail "internal reference in $draft:
$leaks"

awk -v date="$publish_date" '
    fences < 2 && /^<!-- SPDX-/ { next }
    fences == 0 && /^$/ { next }
    /^\+\+\+$/ && fences < 2 { fences++; print; next }
    fences == 1 && /^date = / { print "date = " date; next }
    fences == 1 && /^draft = true$/ { next }
    { print }
' "$draft" > "$target"

printf '%s\n' "$target"
