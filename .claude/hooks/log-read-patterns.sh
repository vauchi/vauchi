#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PostToolUse Read hook: tracks file read patterns per session.
# Logs excessive re-reads (same file read 3+ times = potential waste).
# Non-blocking, purely observational. ~2ms overhead.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" ]] && exit 0

# Track reads in a lightweight counter file (one line per unique file path)
TRACKER="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-reads"
LOG="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-errors"

# Count how many times this file has been read this session
COUNT=1
if [[ -f "$TRACKER" ]]; then
  COUNT=$(grep -cF "$FILE_PATH" "$TRACKER" 2>/dev/null || echo "0")
  COUNT=$((COUNT + 1))
fi

# Append to tracker
echo "$FILE_PATH" >> "$TRACKER" 2>/dev/null

# Log on 3rd+ read of same file (1st and 2nd are normal: read + re-read after edit)
if [[ "$COUNT" -ge 3 ]]; then
  printf '{"ts":"%s","hook":"read-obs","category":"excessive-reread","count":%d,"file":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$COUNT" "$(echo "$FILE_PATH" | head -c 200 | tr '"' "'")" \
    >> "$LOG" 2>/dev/null
fi

exit 0
