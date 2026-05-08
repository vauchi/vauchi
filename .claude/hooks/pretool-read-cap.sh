#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse Read hook: blocks the 4th+ Read of the same file in a
# session, unless an Edit/Write to that file has happened since the
# previous Read (legitimate verify-after-edit) or the Read targets a
# different region (offset/limit).
#
# Companion to .claude/hooks/log-read-patterns.sh (PostToolUse,
# observation-only). The 3-strike rule in `just session-end` flagged
# `excessive-reread` 8000+ times across sessions — this hook is the
# tightening that turns the warning into a block.
#
# Escape: if a re-read is genuinely needed (file changed externally,
# different region, etc.), pass `offset` or `limit` — those count as
# different reads. Otherwise use Grep for a specific symbol or
# `Bash sed -n NNp,MMp <file>` for a known line range.
#
# Tuning notes: watch the next 3–5 sessions for false positives. If
# legitimate flows trip the cap, widen the escapes (or bump the
# threshold). Otherwise the threshold stays at 3.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
OFFSET=$(echo "$INPUT" | jq -r '.tool_input.offset // empty')
LIMIT=$(echo "$INPUT" | jq -r '.tool_input.limit // empty')

[[ -z "$FILE_PATH" ]] && exit 0

# Reads with explicit offset/limit target a specific region — different
# from a full re-read. Allow without counting toward the cap.
if [[ -n "$OFFSET" || -n "$LIMIT" ]]; then
  exit 0
fi

READS_TRACKER="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-reads"
EDITS_TRACKER="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-edits"

COUNT=0
# `grep -c` exits 1 with stdout "0" when there are no matches; `|| echo "0"`
# in that case appended a second "0" line to the substitution, producing a
# multi-line COUNT that broke the `[[ … -ge 3 ]]` arithmetic. `|| true`
# swallows the non-zero exit and keeps the substitution single-line.
[[ -f "$READS_TRACKER" ]] && COUNT=$(grep -cF "$FILE_PATH" "$READS_TRACKER" 2>/dev/null || true)
[[ -z "$COUNT" ]] && COUNT=0

# Allow the next Read if there has been an Edit/Write to this file
# AFTER the most recent Read (file genuinely changed; verify-after-edit
# is legitimate). Compare line numbers in the trackers.
if [[ -f "$EDITS_TRACKER" && "$COUNT" -ge 3 ]]; then
  LAST_READ_LINE=$(grep -nF "$FILE_PATH" "$READS_TRACKER" 2>/dev/null | tail -1 | cut -d: -f1)
  LAST_EDIT_LINE=$(grep -nF "$FILE_PATH" "$EDITS_TRACKER" 2>/dev/null | tail -1 | cut -d: -f1)
  if [[ -n "$LAST_EDIT_LINE" && -n "$LAST_READ_LINE" \
        && "$LAST_EDIT_LINE" -gt "$LAST_READ_LINE" ]]; then
    exit 0
  fi
fi

if [[ "$COUNT" -ge 3 ]]; then
  cat >&2 <<EOF
Blocked: $((COUNT + 1))th Read of $FILE_PATH this session (cap: 3).

Either:
  1. Trust the file content already in your context.
  2. Use Grep for a specific symbol — much cheaper than re-reading.
  3. Use 'Bash sed -n NNp,MMp <file>' for a known line range.
  4. Pass offset/limit on Read for a different region — that bypasses
     this cap (legitimate when reading a long file in chunks).

If the file changed externally and you must re-read in full, the
session-tracker doesn't see that. Edit/Write any byte of the file
first to flip the "verify-after-edit" escape hatch.

Escalations: see .claude/.session-errors for the prior reads.
EOF
  exit 2
fi

exit 0
