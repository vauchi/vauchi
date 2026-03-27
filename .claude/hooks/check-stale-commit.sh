#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse hook: warns before committing on a branch that is behind
# origin/main. Prevents duplicate work when parallel sessions have
# already landed the same changes upstream.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

# Only intercept git commit commands (not amend-only, not rebase --continue)
if ! echo "$COMMAND" | grep -qE '^\s*git\s+(-C\s+\S+\s+)?commit\s'; then
  exit 0
fi

# Skip rebase --continue (which internally commits)
if echo "$COMMAND" | grep -qE 'rebase\s+--continue'; then
  exit 0
fi

# Determine the repo directory
REPO_DIR="$CWD"
if REL_DIR=$(echo "$COMMAND" | sed -n 's/.*git[[:space:]]\+-C[[:space:]]\+\([^[:space:]]\+\).*/\1/p') && [[ -n "$REL_DIR" ]]; then
  if [[ "$REL_DIR" = /* ]]; then
    REPO_DIR="$REL_DIR"
  else
    REPO_DIR="$CWD/$REL_DIR"
  fi
fi

REPO_DIR=$(cd "$REPO_DIR" 2>/dev/null && pwd) || exit 0

# Only check if this is a git repo with a remote
if ! git -C "$REPO_DIR" remote get-url origin &>/dev/null; then
  exit 0
fi

# Only warn when committing on main — feature branches are expected to be behind
BRANCH=$(git -C "$REPO_DIR" branch --show-current 2>/dev/null)
if [[ "$BRANCH" != "main" ]]; then
  exit 0
fi

# Quick fetch (fail silently if offline)
git -C "$REPO_DIR" fetch origin main --quiet 2>/dev/null || exit 0

# Check if HEAD is behind origin/main
BEHIND=$(git -C "$REPO_DIR" rev-list --count HEAD..origin/main 2>/dev/null || echo "0")

if [[ "$BEHIND" -gt 0 ]]; then
  REPO_NAME=$(basename "$REPO_DIR")
  # Show what landed upstream
  UPSTREAM=$(git -C "$REPO_DIR" log --oneline HEAD..origin/main 2>/dev/null | head -5)
  echo "" >&2
  echo "WARNING: $REPO_NAME is $BEHIND commit(s) behind origin/main." >&2
  echo "Recent upstream commits:" >&2
  echo "$UPSTREAM" >&2
  echo "" >&2
  echo "Verify your changes aren't already upstream before committing." >&2
  echo "Run: git -C $REPO_NAME fetch origin main && git -C $REPO_NAME log --oneline HEAD..origin/main" >&2
  # Warn only, don't block — the developer may be on a feature branch intentionally behind
  exit 0
fi
