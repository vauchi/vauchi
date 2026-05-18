#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse Read hook: blocks full-file reads of files >500 lines
# unless `offset` or `limit` is passed, or ALLOW_FULL_READ=1 is set.
#
# Rationale: audit S1-3 deep evidence (2026-05-18) — 8801
# excessive-reread events (60% of all hook events). Most are
# full-file rereads of large files where a targeted slice would
# suffice; per-event waste ~10K tokens per 500 lines.
#
# Orthogonal to pretool-read-cap.sh (which blocks the N-th re-read
# of the same file). This hook catches the *first* greedy read
# before it lands.
#
# Companion: open problem record
# `_private/docs/problems/2026-04-20-excessive-reedit-reread-pattern/`.
#
# Escape: ALLOW_FULL_READ=1 bypasses for cases where full read is
# genuinely needed (rare — only for files where the structure
# requires whole-context reasoning).

set -uo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
OFFSET=$(echo "$INPUT" | jq -r '.tool_input.offset // empty')
LIMIT=$(echo "$INPUT" | jq -r '.tool_input.limit // empty')

# No file path: defer to other hooks / let Read error naturally.
[[ -z "$FILE_PATH" ]] && exit 0

# Slicing already requested — fine.
if [[ -n "$OFFSET" || -n "$LIMIT" ]]; then
  exit 0
fi

# Escape hatch for legitimate full-file needs.
if [[ "${ALLOW_FULL_READ:-0}" == "1" ]]; then
  exit 0
fi

# File missing: let Read error naturally with the real error message.
[[ ! -f "$FILE_PATH" ]] && exit 0

# Skip binary/non-text — Read tool handles these specially and
# wc -l doesn't model their structure.
case "$FILE_PATH" in
  *.png|*.jpg|*.jpeg|*.gif|*.bmp|*.tiff|*.tif|*.webp|*.svg|*.heic) exit 0 ;;
  *.pdf|*.ipynb) exit 0 ;;
esac

LINE_COUNT=$(wc -l < "$FILE_PATH" 2>/dev/null | tr -d ' ')
[[ -z "$LINE_COUNT" || "$LINE_COUNT" -le 500 ]] && exit 0

# Estimate token cost: ~20 tokens per line in cat-n format.
EST_KTOKENS=$(( LINE_COUNT * 20 / 1000 ))

cat >&2 <<EOF
Blocked: full-file Read of $FILE_PATH ($LINE_COUNT lines, ~${EST_KTOKENS}K tokens).

Files >500 lines should be read with offset/limit for the region you need:

  Read(file_path="$FILE_PATH", offset=1, limit=100)
  Read(file_path="$FILE_PATH", offset=$((LINE_COUNT / 2 - 50)), limit=100)

If you don't know which region, use Grep for the symbol or pattern
first, then Read the matching region.

Override: set ALLOW_FULL_READ=1 if a full read is genuinely needed
(rare — only when the structure requires whole-context reasoning).
EOF
exit 2
