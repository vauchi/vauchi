#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse hook: blocks "cd <dir> && git ..." compound commands.
# These trigger a built-in Claude Code security prompt every time.
# Use "git -C <dir> ..." instead — it's auto-allowed and equivalent.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Block: cd <path> && git ... (with optional semicolons, pipes, etc.)
if echo "$COMMAND" | grep -qE '^\s*cd\s+.*&&\s*git\s'; then
  cat >&2 <<'EOF'
Do not use "cd <dir> && git ..." — it triggers a security prompt every time.
Use "git -C <dir> ..." instead. Examples:
  git -C /path/to/repo log --oneline
  git -C /path/to/repo show HEAD:file.rs
  git -C /path/to/repo grep "pattern"
EOF
  exit 2
fi

# Also catch: cd <path>; git ...
if echo "$COMMAND" | grep -qE '^\s*cd\s+.*;\s*git\s'; then
  cat >&2 <<'EOF'
Do not use "cd <dir>; git ..." — use "git -C <dir> ..." instead.
EOF
  exit 2
fi

exit 0
