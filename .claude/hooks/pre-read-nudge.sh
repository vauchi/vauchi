#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse Read hook: nudge the model when it re-reads the same file
# within a short window. Non-blocking — emits guidance via stdout JSON
# (additionalContext) and stderr; always exits 0 so the read proceeds.
#
# Targets the dominant token-waste pattern from
# `_private/docs/problems/2026-04-20-excessive-reedit-reread-pattern/`:
# at the 2026-05-08 baseline, `excessive-reread` is ~75 % of all hook
# events (151 of 452 in 22 days, ~1.5 M wasted tokens). A nudge gives
# the model the context it needs to be more targeted on the next call
# without blocking legitimate re-reads (file changed since last read,
# auto-format wrote it, etc.).
#
# Disable via `VAUCHI_READ_NUDGE=0` in env.
#
# State file: `.claude/.session-reads-meta` — JSONL,
# {"file":"<abs-path>","offset":N,"limit":N,"ts":"<rfc3339>"}.
# Truncated by `just session-init` (or any tool that clears
# `.claude/.session-*`). Window is checked in seconds against the
# current invocation's `ts`.

set -uo pipefail

# Escape hatch — disable per-session if nudges are noisy.
[[ "${VAUCHI_READ_NUDGE:-1}" == "0" ]] && exit 0

INPUT=$(cat)

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE_PATH" ]] && exit 0

# Read tool's optional offset/limit for the *current* invocation.
OFFSET=$(printf '%s' "$INPUT" | jq -r '.tool_input.offset // empty')
LIMIT=$(printf '%s' "$INPUT" | jq -r '.tool_input.limit // empty')

META="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-reads-meta"
NOW=$(date -u +%s)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Window: 30 min — long enough to catch genuine re-read waste, short
# enough that file-change-after-edit re-reads (which take seconds
# minutes apart, not sub-30-min cycles) don't all queue up the nudge.
WINDOW_SECS=1800

PRIOR_LINE=""
if [[ -f "$META" ]]; then
  # Find the most recent prior read of this file within the window.
  # `jq -rR 'fromjson?'` skips any malformed line silently.
  PRIOR_LINE=$(jq -cR --arg f "$FILE_PATH" --arg now "$NOW" --argjson win "$WINDOW_SECS" '
    fromjson?
    | select(.file == $f)
    | select(((($now | tonumber) - ((.ts_unix // 0) | tonumber)) | floor) < $win)
  ' "$META" 2>/dev/null | tail -1)
fi

# Always append the current invocation to state — captures intent at
# PreToolUse time so future invocations see it. ts_unix kept alongside
# ts for cheap window math without re-parsing rfc3339.
{
  printf '{"file":%s,"offset":%s,"limit":%s,"ts":%s,"ts_unix":%d}\n' \
    "$(printf '%s' "$FILE_PATH" | jq -Rs .)" \
    "${OFFSET:-null}" \
    "${LIMIT:-null}" \
    "$(printf '%s' "$NOW_ISO" | jq -Rs .)" \
    "$NOW"
} >> "$META" 2>/dev/null

# No prior read → silent.
[[ -z "$PRIOR_LINE" ]] && exit 0

# Build a one-line summary of the prior read.
PRIOR_OFFSET=$(printf '%s' "$PRIOR_LINE" | jq -r '.offset // "(none)"')
PRIOR_LIMIT=$(printf '%s' "$PRIOR_LINE" | jq -r '.limit // "(none)"')
PRIOR_TS=$(printf '%s' "$PRIOR_LINE" | jq -r '.ts // ""')

if [[ "$PRIOR_OFFSET" == "(none)" && "$PRIOR_LIMIT" == "(none)" ]]; then
  PRIOR_RANGE="full file (default 2000-line read)"
else
  PRIOR_RANGE="offset=${PRIOR_OFFSET} limit=${PRIOR_LIMIT}"
fi

NUDGE="You read $(basename "$FILE_PATH") earlier in this session at ${PRIOR_RANGE} (${PRIOR_TS}). If you only need a specific region this time, pass offset+limit to avoid re-loading the same content. If the file changed since (auto-format / edit), this re-read is fine — proceed. Set VAUCHI_READ_NUDGE=0 to silence for the session."

# Output JSON for newer Claude Code harnesses that surface
# `additionalContext` to the model, plus stderr for older harnesses.
# Whichever the harness honors, the model sees the nudge.
jq -nc --arg msg "$NUDGE" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $msg
  }
}'

printf '%s\n' "$NUDGE" >&2

# Lightweight observability — append to the session-errors stream so
# `just session-end` can count nudge fires alongside other categories.
LOG="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-errors"
printf '{"ts":"%s","hook":"pre-read-nudge","category":"read-nudge","file":"%s"}\n' \
  "$NOW_ISO" "$(printf '%s' "$FILE_PATH" | head -c 200 | tr '"' "'")" \
  >> "$LOG" 2>/dev/null

exit 0
