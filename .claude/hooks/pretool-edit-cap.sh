#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse Edit hook: one-shot circuit breaker on the 5th Edit of
# the same file in a session. Blocks ONCE to force a planning pause,
# then allows — a permanent wall proved counterproductive: it
# displaced edits into Bash (sed -i / python heredocs), which skip
# rustfmt, the assertion checks, SPDX, and the file-state tracker.
# Full audit: 2026-06-12 findings F1–F6 in
# _private/docs/problems/2026-04-20-excessive-reedit-reread-pattern/.
#
# Counts are per (session_id, file) in .claude/.session-activity,
# line format `<session_id> <VERB> <file_path>` — session scoping
# keeps concurrent sessions and past sessions from polluting the
# count. Writers: post-edit.sh (EDIT/WRITE), log-read-patterns.sh
# (READ). This hook writes the BLOCKED marker.
#
# Escapes: Write tool (never capped), VAUCHI_EDIT_CAP=0 (revert
# hatch per the problem record's measurement criteria).

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Edit. Write is fine — it's the suggested escape.
[[ "$TOOL" != "Edit" ]] && exit 0
[[ "${VAUCHI_EDIT_CAP:-1}" == "0" ]] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE_PATH" ]] && exit 0
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "nosession"')

TRACKER="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-activity"
[[ -f "$TRACKER" ]] || exit 0

# `grep -c` exits 1 with stdout "0" on no matches; `|| true` keeps
# COUNT single-line (the `|| echo "0"` variant appended a 2nd line).
COUNT=$(grep -cxF "$SESSION_ID EDIT $FILE_PATH" "$TRACKER" 2>/dev/null || true)
[[ -z "$COUNT" ]] && COUNT=0
[[ "$COUNT" -lt 4 ]] && exit 0

BLOCKED=$(grep -cxF "$SESSION_ID BLOCKED $FILE_PATH" "$TRACKER" 2>/dev/null || true)
[[ -n "$BLOCKED" && "$BLOCKED" -ge 1 ]] && exit 0

echo "$SESSION_ID BLOCKED $FILE_PATH" >> "$TRACKER" 2>/dev/null

cat >&2 <<EOF
Paused: $((COUNT + 1))th Edit of $FILE_PATH this session (cap: 4).

Frequent re-edits of one file usually mean the changes don't fit the
current mental model. Take one planning pass now:

  - Collect EVERY remaining change to this file, then apply them in
    a single Edit call (replace_all where applicable) — or use Write
    to replace the file in one atomic call.
  - Do NOT route the edit through Bash (sed -i, python, tee) — that
    skips the formatter and the test-assertion checks.

This pause fires once per file per session: your next Edit to this
file will be allowed. Prior activity: .claude/.session-activity.
EOF
exit 2
