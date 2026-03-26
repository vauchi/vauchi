#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse hook: blocks raw commands that have `just` recipe equivalents.
# Suggests the recipe instead of letting the raw command through.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip if the command is already a just invocation
if echo "$COMMAND" | grep -qE '^\s*just\s'; then
  exit 0
fi

# Skip commands inside subshells, git commits, heredocs
if echo "$COMMAND" | grep -qE '^\s*\(|git\s+(commit|tag)|<<'; then
  exit 0
fi

log_error() {
  local category="$1" reason="$2"
  local log="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-errors"
  printf '{"ts":"%s","hook":"check-use-just","category":"%s","command":"%s","reason":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$category" "$(echo "$COMMAND" | head -c 200)" "$reason" >> "$log" 2>/dev/null
}

# --- cargo build/test/fmt/clippy → just build/test/check ---
if echo "$COMMAND" | grep -qE '^\s*cargo\s+(build|test|fmt|clippy)'; then
  CARGO_CMD=$(echo "$COMMAND" | grep -oE 'cargo\s+(build|test|fmt|clippy)' | head -1)
  case "$CARGO_CMD" in
    *build*)  RECIPE="just build [repo]" ;;
    *test*)   RECIPE="just test [repo]" ;;
    *fmt*|*clippy*) RECIPE="just check [repo]" ;;
  esac
  cat >&2 <<EOF
Use \`$RECIPE\` instead of raw \`$CARGO_CMD\`.
The recipe handles workspace root, correct manifest path, and repo selection.
For all checks at once: just check [repo]
EOF
  log_error "raw-cargo" "$CARGO_CMD → $RECIPE"
  exit 2
fi

# --- glab mr create → just gitlab mr-create ---
if echo "$COMMAND" | grep -qE '^\s*glab\s+mr\s+create'; then
  cat >&2 <<'EOF'
Use `just gitlab mr-create [repo]` instead of raw `glab mr create`.
The recipe handles branch selection, remote detection, and MR templates.
EOF
  log_error "raw-glab" "glab mr create → just gitlab mr-create"
  exit 2
fi

# --- manual mv of planning docs → just archive ---
if echo "$COMMAND" | grep -qE '(mv|git\s+mv).*planning/(todo|docs).*planning/(archived|deferred)'; then
  cat >&2 <<'EOF'
Use `just archive <file> <status> [note]` instead of manual mv.
The recipe moves the file, records a redirect, and rewrites all references.
Statuses: done, deprecated, deferred, superseded
Example: just archive todo/old-plan.md done
EOF
  log_error "raw-mv-archive" "manual mv → just archive"
  exit 2
fi

# --- cargo coverage → just coverage ---
if echo "$COMMAND" | grep -qE '^\s*cargo\s+(llvm-cov|tarpaulin)'; then
  cat >&2 <<'EOF'
Use `just coverage [repo]` instead of raw cargo coverage commands.
EOF
  log_error "raw-cargo" "cargo coverage → just coverage"
  exit 2
fi

exit 0
