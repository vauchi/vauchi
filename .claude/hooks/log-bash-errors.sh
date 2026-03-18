#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PostToolUse Bash hook: observes Claude's command behavior for waste patterns.
# Non-blocking (exit 0 always) — purely observational telemetry.
#
# Detects 3 waste patterns:
#   1. cmd-failed     — bad assumptions about system state
#   2. wrong-tool     — using Bash(cat/head/tail/grep) when Read/Grep exists
#   3. guessing-loop  — 3+ sequential failures → searching by guessing

INPUT=$(cat)
IFS=$'\t' read -r EXIT_CODE COMMAND \
  < <(echo "$INPUT" | jq -r '[
    (.tool_output.exit_code // .tool_result.exit_code // "0" | tostring),
    (.tool_input.command // "")
  ] | join("\t")')

LOG="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-errors"

# ── Pattern 1: Wrong tool choice ────────────────────────────────────
# Detect Bash commands that should have used a dedicated tool.
# Log but don't block — the system prompt already guides this.
case "$COMMAND" in
  # Pure file reads (no pipe, no redirection) → should use Read tool
  "cat "*|"head "*|"tail "*)
    # Only flag if it's a simple file read (no pipe)
    if ! echo "$COMMAND" | grep -qE '\||>|<|&&|\$\('; then
      printf '{"ts":"%s","hook":"bash-obs","category":"wrong-tool","detail":"use Read not %s","command":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${COMMAND%% *}" "$(echo "$COMMAND" | head -c 200 | tr '"' "'")" \
        >> "$LOG" 2>/dev/null
    fi
    ;;
  # Pure grep (not piped, not in compound) → should use Grep tool
  "grep "*)
    if ! echo "$COMMAND" | grep -qE '\||&&|;'; then
      printf '{"ts":"%s","hook":"bash-obs","category":"wrong-tool","detail":"use Grep not grep","command":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(echo "$COMMAND" | head -c 200 | tr '"' "'")" \
        >> "$LOG" 2>/dev/null
    fi
    ;;
  # Pure find → should use Glob tool
  "find "*)
    if ! echo "$COMMAND" | grep -qE '\||&&|;|-exec'; then
      printf '{"ts":"%s","hook":"bash-obs","category":"wrong-tool","detail":"use Glob not find","command":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(echo "$COMMAND" | head -c 200 | tr '"' "'")" \
        >> "$LOG" 2>/dev/null
    fi
    ;;
esac

# ── Pattern 2: Command failures ─────────────────────────────────────
if [[ "$EXIT_CODE" != "0" && -n "$EXIT_CODE" ]]; then
  # Skip expected non-zero exits
  case "$COMMAND" in
    *"grep -q"*|*"diff --quiet"*|*"git diff --quiet"*) exit 0 ;;
    *"command -v"*|*"which "*) exit 0 ;;
    *"|| true"*|*"|| echo"*) exit 0 ;;  # explicit error handling
  esac

  printf '{"ts":"%s","hook":"bash-obs","category":"cmd-failed","exit_code":%s,"command":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$EXIT_CODE" "$(echo "$COMMAND" | head -c 200 | tr '"' "'")" \
    >> "$LOG" 2>/dev/null

  # ── Pattern 3: Guessing loop detection ────────────────────────────
  # If last 2 entries in the log are also cmd-failed, flag as guessing loop
  if [[ -f "$LOG" ]]; then
    RECENT_FAILS=$(tail -3 "$LOG" | grep -c '"category":"cmd-failed"' || true)
    if [[ "$RECENT_FAILS" -ge 2 ]]; then
      printf '{"ts":"%s","hook":"bash-obs","category":"guessing-loop","detail":"3+ sequential failures","command":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(echo "$COMMAND" | head -c 100 | tr '"' "'")" \
        >> "$LOG" 2>/dev/null
    fi
  fi
fi

exit 0
