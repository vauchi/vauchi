#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Shared logging helpers for .claude/hooks/*.sh
#
# Convention: hooks default SILENT on the success path. Only say_warn
# and say_error write to stderr. say_debug and say_info are no-ops
# unless CLAUDE_HOOK_VERBOSE=1.
#
# Why: every stderr line a hook emits becomes part of Claude's tool
# result and inflates context — even on successful tool calls. Audit
# S2-1 (2026-05-18): gate-push.sh has 57 stderr prints, contributing
# to compound waste on every Bash call.
#
# Usage:
#   . "$CLAUDE_PROJECT_DIR/.claude/hooks/_lib/log.sh"
#   say_warn  "branch is stale by 3 commits"
#   say_error "push blocked — stale local-bindings dir"
#   say_debug "checking remote SHA"      # silent unless CLAUDE_HOOK_VERBOSE=1
#   say_info  "found 12 files modified"  # silent unless CLAUDE_HOOK_VERBOSE=1
#
# ── SCOPE (post-merge audit 2026-05-18) ──
#
# This lib is appropriate for:
#   (a) Exit-2 hooks emitting single-line warn/error context (Claude
#       Code surfaces exit-2 stderr to the model as the tool error).
#   (b) Exit-0 hooks emitting debug/info under CLAUDE_HOOK_VERBOSE=1
#       (the dev sees terminal output directly).
#
# This lib is NOT the right tool for:
#   (c) Exit-0 hooks that want their warning visible to the MODEL.
#       Per docs, exit-0 stderr is discarded — the model never sees
#       say_warn/say_error from an exit-0 hook. Use stdout JSON
#       `hookSpecificOutput.additionalContext` instead; see
#       `pre-read-nudge.sh` as a reference implementation.
#   (d) Multi-line block messages on exit-2. A `cat >&2 <<EOF … EOF`
#       heredoc reads better than 6 stacked say_error calls (each of
#       which would prefix `[ERROR]` and break formatting).
#
# Audit reference:
# _private/docs/investigations/2026-05-18-claude-code-harness-audit.md S2-1.

# shellcheck shell=bash

CLAUDE_HOOK_VERBOSE="${CLAUDE_HOOK_VERBOSE:-0}"

say_debug() {
  if [[ "$CLAUDE_HOOK_VERBOSE" == "1" ]]; then
    printf '[DEBUG] %s\n' "$*" >&2
  fi
}

say_info() {
  if [[ "$CLAUDE_HOOK_VERBOSE" == "1" ]]; then
    printf '[INFO ] %s\n' "$*" >&2
  fi
}

say_warn() {
  printf '[WARN ] %s\n' "$*" >&2
}

say_error() {
  printf '[ERROR] %s\n' "$*" >&2
}
