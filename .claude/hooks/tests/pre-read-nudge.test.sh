#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Test runner for `.claude/hooks/pre-read-nudge.sh`.
#
# Covers the five paths from the test strategy in
# `_private/docs/problems/2026-04-20-excessive-reedit-reread-pattern/`:
#   1. 1st invocation        — silent, state appended.
#   2. 2nd invocation in win — nudge emitted (stdout JSON + stderr).
#   3. VAUCHI_READ_NUDGE=0   — exits silent (escape hatch).
#   4. 2nd read with offset  — nudge mentions prior 'full file'.
#   5. Empty input           — silent (no file_path).
#
# Run: bash .claude/hooks/tests/pre-read-nudge.test.sh
# Exits 0 on full pass, 1 on any failure. Each path prints PASS/FAIL.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/pre-read-nudge.sh"

if [[ ! -x "$HOOK" ]]; then
    echo "FATAL: $HOOK not executable" >&2
    exit 1
fi

PASS=0
FAIL=0

run_case() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n    expected: %s\n    got:      %s\n' "$name" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

run_case_contains() {
    local name="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n    expected to contain: %s\n    got:                 %s\n' "$name" "$needle" "$haystack"
        FAIL=$((FAIL + 1))
    fi
}

# ── Per-test setup: isolated CLAUDE_PROJECT_DIR ──
setup() {
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/.claude"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ── Path 1: 1st invocation — silent + state appended ──
setup
out=$(CLAUDE_PROJECT_DIR=$TEST_DIR bash "$HOOK" <<< '{"tool_input":{"file_path":"/tmp/foo.md"}}' 2>&1)
state_lines=$(wc -l < "$TEST_DIR/.claude/.session-reads-meta" 2>/dev/null | tr -d ' ')
run_case "Path 1 — 1st invocation: silent" "" "$out"
run_case "Path 1 — 1st invocation: state has 1 line" "1" "$state_lines"
teardown

# ── Path 2: 2nd invocation within window — nudge + valid stdout JSON ──
setup
CLAUDE_PROJECT_DIR=$TEST_DIR bash "$HOOK" <<< '{"tool_input":{"file_path":"/tmp/foo.md"}}' >/dev/null 2>&1
stdout=$(CLAUDE_PROJECT_DIR=$TEST_DIR bash "$HOOK" <<< '{"tool_input":{"file_path":"/tmp/foo.md"}}' 2>/dev/null)
stderr=$(CLAUDE_PROJECT_DIR=$TEST_DIR bash "$HOOK" <<< '{"tool_input":{"file_path":"/tmp/foo.md"}}' 2>&1 >/dev/null)
# stdout must be a single line of valid JSON with .hookSpecificOutput.additionalContext
json_check=$(printf '%s' "$stdout" | jq -r '.hookSpecificOutput.additionalContext // "MISSING"' 2>/dev/null)
run_case_contains "Path 2 — stdout is JSON with additionalContext" "earlier in this session" "$json_check"
run_case_contains "Path 2 — stderr emits same nudge" "earlier in this session" "$stderr"
teardown

# ── Path 3: VAUCHI_READ_NUDGE=0 — silent ──
setup
CLAUDE_PROJECT_DIR=$TEST_DIR bash "$HOOK" <<< '{"tool_input":{"file_path":"/tmp/foo.md"}}' >/dev/null 2>&1
out=$(CLAUDE_PROJECT_DIR=$TEST_DIR VAUCHI_READ_NUDGE=0 bash "$HOOK" <<< '{"tool_input":{"file_path":"/tmp/foo.md"}}' 2>&1)
run_case "Path 3 — VAUCHI_READ_NUDGE=0: silent" "" "$out"
teardown

# ── Path 4: 2nd read with offset/limit — nudge mentions prior 'full file' ──
setup
CLAUDE_PROJECT_DIR=$TEST_DIR bash "$HOOK" <<< '{"tool_input":{"file_path":"/tmp/bar.md"}}' >/dev/null 2>&1
out=$(CLAUDE_PROJECT_DIR=$TEST_DIR bash "$HOOK" <<< '{"tool_input":{"file_path":"/tmp/bar.md","offset":50,"limit":100}}' 2>&1 >/dev/null)
run_case_contains "Path 4 — nudge mentions prior full-file read" "full file" "$out"
teardown

# ── Path 5: empty input — silent (no file_path) ──
setup
out=$(CLAUDE_PROJECT_DIR=$TEST_DIR bash "$HOOK" <<< '{"tool_input":{}}' 2>&1)
run_case "Path 5 — empty input: silent" "" "$out"
teardown

# ── Summary ──
echo ""
if [[ "$FAIL" -eq 0 ]]; then
    printf 'pre-read-nudge.test: %d passed, 0 failed\n' "$PASS"
    exit 0
else
    printf 'pre-read-nudge.test: %d passed, %d FAILED\n' "$PASS" "$FAIL"
    exit 1
fi
