#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PostToolUse Bash hook: OBSERVATION-ONLY. Records when a file edit was
# performed through the Bash tool instead of the Edit/Write tools.
#
# Why this exists — the edit-cap (pretool-edit-cap.sh) and auto-format
# (post-edit.sh) bind ONLY to the Edit|Write matcher. A `sed -i`,
# `perl -i`, `tee <file>`, `python -c 'open(...,"w")'`, or a `>`/`>>`
# redirect into a source file routes through the Bash matcher and is
# therefore invisible to the cap, the formatter, and the re-edit counter.
# That blind spot can make the "excessive-reedit dropped 169→39" metric
# look like reduction when some of it is DISPLACEMENT into Bash.
#
# This hook never blocks (always exit 0). It only emits a
# `bash-file-edit` line to .session-errors so `just session-end` can
# count how often it happens — the same observe-first path that
# log-read-patterns.sh walked before pretool-read-cap.sh became a block.
# If the count turns out to be material, promote to a PreToolUse nudge or
# cap; if negligible, this stays a cheap counter.
#
# Heuristic is deliberately conservative: in-place editors are always
# flagged; redirects/tee are flagged only when the target looks like a
# tracked source file (known extension) and is NOT under /tmp or /dev.

set -uo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

# Source-file extensions we care about for redirect/tee targets.
SRC_EXT='rs|md|sh|toml|json|swift|kt|kts|py|ts|tsx|js|jsx|yml|yaml|cpp|cc|h|hpp|cs|java|txt|just|feature|css|html'

TOOL=""
FILE=""

# 1. In-place stream editors — always a Bash-side edit.
if printf '%s' "$COMMAND" | grep -qE '\bsed\b[^|;&]*[[:space:]]-i'; then
    TOOL="sed-i"
    FILE=$(printf '%s' "$COMMAND" | grep -oE "[^[:space:]'\"]+\.($SRC_EXT)\b" | tail -1)
elif printf '%s' "$COMMAND" | grep -qE '\bperl\b[^|;&]*[[:space:]]-i'; then
    TOOL="perl-i"
    FILE=$(printf '%s' "$COMMAND" | grep -oE "[^[:space:]'\"]+\.($SRC_EXT)\b" | tail -1)

# 2. python/node inline script that opens a file for writing.
elif printf '%s' "$COMMAND" | grep -qE '\b(python3?|node)\b' \
     && printf '%s' "$COMMAND" | grep -qE "open\([^)]*['\"][wa]|\.write\(|writeFileSync"; then
    TOOL="python"
    FILE=$(printf '%s' "$COMMAND" | grep -oE "[^[:space:]'\"]+\.($SRC_EXT)\b" | head -1)

# 3. tee into a source file (skip /tmp, /dev).
elif printf '%s' "$COMMAND" | grep -qE "\btee\b[^|]*[^[:space:]'\"]+\.($SRC_EXT)\b" \
     && ! printf '%s' "$COMMAND" | grep -qE '\btee\b[^|]*(/tmp/|/dev/)'; then
    TOOL="tee"
    FILE=$(printf '%s' "$COMMAND" | grep -oE "[^[:space:]'\"]+\.($SRC_EXT)\b" | tail -1)

# 4. Redirect (> or >>) into a source file (skip /tmp, /dev, .bak).
elif printf '%s' "$COMMAND" | grep -qE ">>?[[:space:]]*[^[:space:]'\"|&]*\.($SRC_EXT)\b"; then
    TARGET=$(printf '%s' "$COMMAND" \
        | grep -oE ">>?[[:space:]]*[^[:space:]'\"|&]*\.($SRC_EXT)\b" \
        | tail -1 | sed -E 's/^>>?[[:space:]]*//')
    case "$TARGET" in
        /tmp/* | /dev/*) : ;;        # safe sinks — ignore
        *) TOOL="redirect"; FILE="$TARGET" ;;
    esac
fi

[[ -z "$TOOL" ]] && exit 0

LOG="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-errors"
printf '{"ts":"%s","hook":"log-bash-edits","category":"bash-file-edit","tool":"%s","file":"%s","command":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TOOL" \
    "$(printf '%s' "$FILE" | head -c 200 | tr '"' "'")" \
    "$(printf '%s' "$COMMAND" | head -c 200 | tr '"' "'")" \
    >> "$LOG" 2>/dev/null

exit 0
