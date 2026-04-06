#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse hook: blocks Edit/Write on source files unless
# .claude/.workcontext is set with a non-empty problem slug.
#
# Enforces that Claude sessions claim a task from the work board
# before making code changes.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Nothing to check if no file path
[[ -z "$FILE" ]] && exit 0

WORKCONTEXT="${CLAUDE_PROJECT_DIR:-.}/.claude/.workcontext"

# ── Exempt paths that don't require a claimed task ──────────────
# Meta-work: hooks, settings, workcontext itself
case "$FILE" in
  */.claude/*) exit 0 ;;
  */_private/*) exit 0 ;;
esac

# Config and documentation — not code
case "$FILE" in
  *.md|*.txt|*.json|*.toml|*.yml|*.yaml|*.gitignore|*.env*) exit 0 ;;
  *CLAUDE.md|*README.md|*LICENSE*) exit 0 ;;
esac

# ── Check workcontext ───────────────────────────────────────────
if [[ ! -f "$WORKCONTEXT" ]]; then
  cat >&2 <<'EOF'
No task claimed. Before editing code, claim a task from the work board:

  1. Edit _private/docs/work-board.md — move item to "In Progress"
  2. Set .claude/.workcontext:
     {"problem": "your-task-slug", "phase": "implementing"}

This ensures sessions don't start work without visibility on the board.
EOF
  exit 2
fi

PROBLEM=$(jq -r '.problem // empty' "$WORKCONTEXT" 2>/dev/null)

if [[ -z "$PROBLEM" ]]; then
  cat >&2 <<'EOF'
.workcontext exists but has no problem slug. Set it before editing code:

  {"problem": "your-task-slug", "phase": "implementing"}

Claim the task on _private/docs/work-board.md first.
EOF
  exit 2
fi

exit 0
