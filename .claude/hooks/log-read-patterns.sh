#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PostToolUse Read hook: tracks file read patterns per session.
# Logs excessive re-reads (same file read 3+ times = potential waste).
# Non-blocking, purely observational. ~2ms overhead.
#
# Writes `<session_id> READ <file_path>` lines to .session-activity —
# the contract pretool-read-cap.sh counts against. Sliced reads
# (offset/limit) are not recorded: they are exempt from the cap, so
# counting them would inflate the full-read count.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
OFFSET=$(echo "$INPUT" | jq -r '.tool_input.offset // empty')
LIMIT=$(echo "$INPUT" | jq -r '.tool_input.limit // empty')

[[ -z "$FILE_PATH" ]] && exit 0
[[ -n "$OFFSET" || -n "$LIMIT" ]] && exit 0

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "nosession"')
TRACKER="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-activity"
LOG="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-errors"

echo "$SESSION_ID READ $FILE_PATH" >> "$TRACKER" 2>/dev/null

# Self-trim: the tracker is append-only across all sessions on this
# machine; cap its size so greps stay cheap. Relative line order is
# preserved, which is all the cap hooks rely on.
if [[ $(wc -l < "$TRACKER" 2>/dev/null || echo 0) -gt 50000 ]]; then
  tail -n 25000 "$TRACKER" > "$TRACKER.tmp" 2>/dev/null && mv "$TRACKER.tmp" "$TRACKER"
fi

COUNT=$(grep -cxF "$SESSION_ID READ $FILE_PATH" "$TRACKER" 2>/dev/null || true)

# Log on 3rd+ read of same file (1st and 2nd are normal: read + re-read after edit)
if [[ -n "$COUNT" && "$COUNT" -ge 3 ]]; then
  printf '{"ts":"%s","hook":"read-obs","category":"excessive-reread","count":%d,"file":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$COUNT" "$(echo "$FILE_PATH" | head -c 200 | tr '"' "'")" \
    >> "$LOG" 2>/dev/null
fi

exit 0
