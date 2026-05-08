#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse Edit hook: blocks the 5th+ Edit of the same file in a
# session. 1–2 Edits = normal. 3rd Edit = soft nudge from post-edit.sh
# already prints. 4th = logged as `excessive-reedit`. 5th = blocked.
#
# Companion to post-edit.sh (PostToolUse, observation-only). The
# 3-strike rule in `just session-end` flagged `excessive-reedit` 3000+
# times across sessions — this hook turns the post-edit log into a
# pre-edit block.
#
# Escape: re-Read the file (post-edit.sh tracker is per-session, not
# per-edit-burst — there is no built-in reset). Use Write instead to
# replace the whole file when many changes pile up.
#
# Tuning notes: watch the next 3–5 sessions for false positives. If
# legitimate flows trip the cap, widen the escapes (or bump the
# threshold). Otherwise the threshold stays at 4.

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only check Edit. Write is fine — it's the suggested escape.
[[ "$TOOL" != "Edit" ]] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE_PATH" ]] && exit 0

TRACKER="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-edits"
COUNT=0
# Same `grep -c || echo "0"` multi-line bug as pretool-read-cap.sh —
# `grep -c` exits 1 with stdout "0" on no matches, the fallback echo
# appended a second "0" line, producing a multi-line COUNT.
[[ -f "$TRACKER" ]] && COUNT=$(grep -cF "$FILE_PATH" "$TRACKER" 2>/dev/null || true)
[[ -z "$COUNT" ]] && COUNT=0

if [[ "$COUNT" -ge 4 ]]; then
  cat >&2 <<EOF
Blocked: $((COUNT + 1))th Edit of $FILE_PATH this session (cap: 4).

Repeated Edits to the same file usually mean the changes don't fit the
mental model — back up:

  1. Write the whole file fresh (one tool call, atomic).
  2. Re-read the file, plan all remaining changes, then a single Edit
     with replace_all where applicable.
  3. If you're patching small unrelated fragments, batch them — each
     Edit is round-trip overhead.

The post-edit.sh hook already nudged at the 3rd Edit; this is the hard
cap. See .claude/.session-errors for the prior edits.
EOF
  exit 2
fi

exit 0
