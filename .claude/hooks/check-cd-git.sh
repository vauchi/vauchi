#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse hook: prevents cwd drift by blocking commands that change directory.
#
# Rules:
# 1. "cd <dir> && git ..."  → use "git -C <dir>" instead
# 2. "cd <dir> && <command>" → use subshell "(cd <dir> && <command>)" instead
#    Subshells don't leak cwd to subsequent commands.
# 3. Bare "cd <dir>" with no following command → blocked entirely

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Block: cd <path> && git ... (use git -C instead)
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

# Block: cd <path>; git ...
if echo "$COMMAND" | grep -qE '^\s*cd\s+.*;\s*git\s'; then
  cat >&2 <<'EOF'
Do not use "cd <dir>; git ..." — use "git -C <dir> ..." instead.
EOF
  exit 2
fi

# Block: cd <path> && <non-git command> without subshell
# Allow: (cd <path> && ...) — subshells are safe, cwd doesn't leak
# Allow: cd $CLAUDE_PROJECT_DIR && ... — returning to workspace root is safe
if echo "$COMMAND" | grep -qE '^\s*cd\s+\S+.*&&' && ! echo "$COMMAND" | grep -qE '^\s*\(' && ! echo "$COMMAND" | grep -qF "$CLAUDE_PROJECT_DIR"; then
  cat >&2 <<EOF
[$CLAUDE_PROJECT_DIR/.claude/hooks/check-cd-git.sh]: "cd <dir> && ..." drifts the working directory.
Wrap in a subshell so cwd resets after: (cd <dir> && <command>)
Or use absolute paths / tool-specific flags (git -C, cargo --manifest-path).
EOF
  exit 2
fi

# Block: bare "cd <dir>" with no following command
# Exception: "cd $CLAUDE_PROJECT_DIR" is safe (returns to workspace root)
if echo "$COMMAND" | grep -qE '^\s*cd\s+\S+\s*$' && ! echo "$COMMAND" | grep -qF "$CLAUDE_PROJECT_DIR"; then
  cat >&2 <<EOF
[$CLAUDE_PROJECT_DIR/.claude/hooks/check-cd-git.sh]: Bare "cd" drifts the working directory permanently.
Stay at workspace root ($CLAUDE_PROJECT_DIR). Use:
  git -C <dir> ...
  cargo --manifest-path <dir>/Cargo.toml ...
  (cd <dir> && ./gradlew ...)  # subshell — cwd resets after
EOF
  exit 2
fi

exit 0
