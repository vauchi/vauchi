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

# Skip git commit/tag commands (message body may contain blocked patterns)
if echo "$COMMAND" | grep -qE '\bgit\s+((-C\s+\S+\s+)?)?(commit|tag)\b'; then
  exit 0
fi

# Block: git -C root (workspace root IS the root repo — no root/ directory)
if echo "$COMMAND" | grep -qE 'git\s+-C\s+root\b'; then
  cat >&2 <<'EOF'
Do not use "git -C root" — the workspace root IS the root repo.
There is no "root/" subdirectory. Use bare "git ..." (no -C) for the root repo.
For sub-repos, use "git -C <repo-name> ..." (e.g. git -C core, git -C android).
EOF
  exit 2
fi

log_error() {
  local category="$1" reason="$2"
  local log="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-errors"
  printf '{"ts":"%s","hook":"check-cd-git","category":"%s","command":"%s","reason":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$category" "$(echo "$COMMAND" | head -c 200)" "$reason" >> "$log" 2>/dev/null
}

# Block: cd <path> && git ... (use git -C instead)
if echo "$COMMAND" | grep -qE '^\s*cd\s+.*&&\s*git\s'; then
  cat >&2 <<'EOF'
Do not use "cd <dir> && git ..." — it triggers a security prompt every time.
Use "git -C <dir> ..." instead. Examples:
  git -C /path/to/repo log --oneline
  git -C /path/to/repo show HEAD:file.rs
  git -C /path/to/repo grep "pattern"
EOF
  log_error "cwd-drift" "cd && git — use git -C"
  exit 2
fi

# Block: cd <path>; git ...
if echo "$COMMAND" | grep -qE '^\s*cd\s+.*;\s*git\s'; then
  cat >&2 <<'EOF'
Do not use "cd <dir>; git ..." — use "git -C <dir> ..." instead.
EOF
  log_error "cwd-drift" "cd ; git — use git -C"
  exit 2
fi

# Block: cd <path> && <non-git command> without subshell
# Allow: (cd <path> && ...) — subshells are safe, cwd doesn't leak
# Allow: cd $CLAUDE_PROJECT_DIR && ... — returning to workspace root is safe
# Block: cd <other-dir> && ... — drifts working directory
_CD_EXEMPT=false
if echo "$COMMAND" | grep -qE '^\s*\('; then _CD_EXEMPT=true; fi
# Escape ERE metacharacters in the absolute path before embedding in the
# regex. `/` is NOT an ERE metachar — escaping it makes grep emit
# "stray \ before /" warnings (one per slash in CLAUDE_PROJECT_DIR).
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]] && echo "$COMMAND" | grep -qE "^\s*cd\s+(\"|')?(\\$\{?CLAUDE_PROJECT_DIR\}?|$(printf '%s' "${CLAUDE_PROJECT_DIR}" | sed 's/[].*+?|(){}[$^\\]/\\&/g'))(\"|')?\s"; then _CD_EXEMPT=true; fi
if echo "$COMMAND" | grep -qE '^\s*cd\s+\S+.*&&' && [[ "$_CD_EXEMPT" == "false" ]]; then
  cat >&2 <<EOF
[$CLAUDE_PROJECT_DIR/.claude/hooks/check-cd-git.sh]: "cd <dir> && ..." drifts the working directory.
Wrap in a subshell so cwd resets after: (cd <dir> && <command>)
Or use absolute paths / tool-specific flags (git -C, cargo --manifest-path).
EOF
  log_error "cwd-drift" "cd && cmd — use subshell"
  exit 2
fi

# Block: bare "cd <dir>" with no following command
# Exception: "cd $CLAUDE_PROJECT_DIR" is safe (returns to workspace root)
_BARE_CD_EXEMPT=false
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]] && echo "$COMMAND" | grep -qF "$CLAUDE_PROJECT_DIR"; then _BARE_CD_EXEMPT=true; fi
if echo "$COMMAND" | grep -qF '$CLAUDE_PROJECT_DIR'; then _BARE_CD_EXEMPT=true; fi
if echo "$COMMAND" | grep -qE '^\s*cd\s+\S+\s*$' && [[ "$_BARE_CD_EXEMPT" == "false" ]]; then
  cat >&2 <<EOF
[$CLAUDE_PROJECT_DIR/.claude/hooks/check-cd-git.sh]: Bare "cd" drifts the working directory permanently.
Stay at workspace root ($CLAUDE_PROJECT_DIR). Use:
  git -C <dir> ...
  cargo --manifest-path <dir>/Cargo.toml ...
  (cd <dir> && ./gradlew ...)  # subshell — cwd resets after
EOF
  log_error "cwd-drift" "bare cd — blocked"
  exit 2
fi

exit 0
