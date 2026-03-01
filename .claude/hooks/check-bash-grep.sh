#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse hook: blocks grep -P (Perl regex) in Bash commands.
# macOS ships BSD grep which does not support -P. Use ripgrep or just grep instead.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip commands where "grep -P" appears only inside string arguments, not as an actual command.
# This includes git commit messages, just recipe arguments, echo, etc.
if echo "$COMMAND" | grep -qE 'git\s+(commit|tag)'; then
  exit 0
fi
if echo "$COMMAND" | grep -qE '^\s*just\s'; then
  exit 0
fi

# Only check commands that contain grep
if ! echo "$COMMAND" | grep -q 'grep'; then
  exit 0
fi

# Block grep -P (Perl regex — not available on macOS)
if echo "$COMMAND" | grep -qE 'grep\s+(-[a-oq-zA-Z]*P|-P)'; then
  cat >&2 <<'EOF'
grep -P (Perl regex) is not available on macOS.
Use `just grep <pattern>` instead, which uses ripgrep under the hood.
For code search, prefer: just grep <pattern> [glob]
For concept search, prefer: just concept <name>
EOF
  exit 2
fi

exit 0
