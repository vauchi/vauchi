#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse Read hook: blocks the 4th+ full Read of the same file in
# a session, unless an Edit/Write to that file happened after the
# previous Read (legitimate verify-after-edit) or the Read targets a
# specific region (offset/limit — never counted, never blocked).
#
# Counts are per (session_id, file) in .claude/.session-activity,
# line format `<session_id> <VERB> <file_path>`. The single combined
# tracker makes read-vs-edit ordering positional — the previous
# two-file design compared line numbers across independently growing
# files, so the verify-after-edit escape opened effectively at
# random (2026-06-12 finding F4 in
# _private/docs/problems/2026-04-20-excessive-reedit-reread-pattern/).
#
# Escapes: offset/limit slice, Grep, verify-after-edit,
# VAUCHI_READ_CAP=0 (revert hatch).

INPUT=$(cat)
[[ "${VAUCHI_READ_CAP:-1}" == "0" ]] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
OFFSET=$(echo "$INPUT" | jq -r '.tool_input.offset // empty')
LIMIT=$(echo "$INPUT" | jq -r '.tool_input.limit // empty')

[[ -z "$FILE_PATH" ]] && exit 0

# Region-targeted reads are a different read each time — exempt.
if [[ -n "$OFFSET" || -n "$LIMIT" ]]; then
  exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "nosession"')
TRACKER="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-activity"
[[ -f "$TRACKER" ]] || exit 0

# `grep -c` exits 1 with stdout "0" on no matches; `|| true` keeps
# COUNT single-line.
COUNT=$(grep -cxF "$SESSION_ID READ $FILE_PATH" "$TRACKER" 2>/dev/null || true)
[[ -z "$COUNT" ]] && COUNT=0
[[ "$COUNT" -lt 3 ]] && exit 0

# Verify-after-edit: allow if an EDIT or WRITE to this file appears
# after the last READ. Line numbers are comparable — same file.
LAST_READ=$(grep -nxF "$SESSION_ID READ $FILE_PATH" "$TRACKER" 2>/dev/null | tail -1 | cut -d: -f1)
LAST_CHANGE=$( { grep -nxF "$SESSION_ID EDIT $FILE_PATH" "$TRACKER" 2>/dev/null
                 grep -nxF "$SESSION_ID WRITE $FILE_PATH" "$TRACKER" 2>/dev/null
               } | cut -d: -f1 | sort -n | tail -1)
if [[ -n "$LAST_CHANGE" && -n "$LAST_READ" && "$LAST_CHANGE" -gt "$LAST_READ" ]]; then
  exit 0
fi

cat >&2 <<EOF
Blocked: $((COUNT + 1))th full Read of $FILE_PATH this session (cap: 3).

Either:
  1. Trust the file content already in your context.
  2. Use Grep for a specific symbol — much cheaper than re-reading.
  3. Pass offset/limit on Read for the region you need — sliced
     reads are never capped.

If the file genuinely changed, an Edit/Write to it re-opens one full
Read automatically. Prior activity: .claude/.session-activity.
EOF
exit 2
