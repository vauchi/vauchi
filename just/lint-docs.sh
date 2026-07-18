#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

readonly REPOSITORIES=("." "_private" "scripts" "assets")
readonly NAMING_CHECKER="scripts/ci-templates/check-doc-naming.sh"
readonly WRONG_LICENSE_PATTERNS=("licensed under MIT" "License: MIT")

errors=0
markdown_files=()
naming_files=()

for repository in "${REPOSITORIES[@]}"; do
    [ -d "$repository" ] || continue
    git -C "$repository" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        continue

    while IFS= read -r -d '' relative_path; do
        if [ "$repository" = "." ]; then
            path="$relative_path"
        else
            path="$repository/$relative_path"
        fi
        markdown_files+=("$path")
    done < <(
        git -C "$repository" ls-files -z \
            --cached --others --exclude-standard -- '*.md'
    )
done

for repository in "${REPOSITORIES[@]}"; do
    [ -d "$repository" ] || continue
    git -C "$repository" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        continue

    while IFS= read -r -d '' relative_path; do
        if [ "$repository" = "." ]; then
            path="$relative_path"
        else
            path="$repository/$relative_path"
        fi
        case "$path" in
            assets/*) ;;
            *) naming_files+=("$path") ;;
        esac
    done < <(
        if git -C "$repository" rev-parse --verify origin/main \
            >/dev/null 2>&1; then
            git -C "$repository" diff --name-only --diff-filter=A -z \
                origin/main... -- '*.md'
        elif git -C "$repository" rev-parse --verify HEAD~1 \
            >/dev/null 2>&1; then
            git -C "$repository" diff --name-only --diff-filter=A -z \
                HEAD~1... -- '*.md'
        fi
        git -C "$repository" diff --cached --name-only --diff-filter=A -z \
            -- '*.md'
        git -C "$repository" ls-files -z \
            --others --exclude-standard -- '*.md'
    )
done

echo "═══ Checking doc naming convention ═══"
if [ ! -x "$NAMING_CHECKER" ]; then
    echo "  FAIL: canonical naming checker not found: $NAMING_CHECKER"
    errors=$((errors + 1))
elif ! "$NAMING_CHECKER" --files "${naming_files[@]}"; then
    errors=$((errors + 1))
fi

echo ""
echo "═══ Checking for wrong license references ═══"
for pattern in "${WRONG_LICENSE_PATTERNS[@]}"; do
    matches=""
    if [ "${#markdown_files[@]}" -gt 0 ]; then
        matches=$(
            grep -Hni "$pattern" "${markdown_files[@]}" 2>/dev/null |
                grep -Eiv \
                    'catppuccin|dracula|nord|solarized|gruvbox|third.party|external|dependency' ||
                true
        )
    fi
    if [ -n "$matches" ]; then
        echo "$matches"
        echo "  FAIL: Wrong license reference: '$pattern'"
        errors=$((errors + 1))
    fi
done

echo ""
echo "═══ Checking for broken links ═══"
if command -v lychee >/dev/null 2>&1; then
    if [ "${#markdown_files[@]}" -gt 0 ]; then
        lychee --offline --no-progress "${markdown_files[@]}" ||
            errors=$((errors + 1))
    fi
else
    echo "  SKIP: lychee not installed (brew install lychee / cargo install lychee)"
fi

echo ""
if [ "$errors" -gt 0 ]; then
    echo "FAILED: $errors issue(s) found"
    exit 1
fi
echo "All documentation checks passed."
