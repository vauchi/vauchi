#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Test runner for `.claude/hooks/pretool-edit-cap.sh`.
#
# Covers the one-shot circuit-breaker redesign
# (2026-04-20-excessive-reedit-reread-pattern, 2026-06-12 findings):
#   1. No tracker            — allow.
#   2. 3 EDITs same session  — allow (below cap).
#   3. 4 EDITs same session  — block once (exit 2), BLOCKED recorded.
#   4. BLOCKED already set   — allow (one-shot, fixes the dead end).
#   5. 4 EDITs other session — allow (session isolation, fixes F1).
#   6. Legacy bare-path rows — allow (clean migration).
#   7. VAUCHI_EDIT_CAP=0     — allow, nothing recorded (revert hatch).
#   8. tool_name=Write       — allow (Write is an approved escape).
#   9. Path is a substring   — allow (exact-line match, fixes F6).
#
# Run: bash .claude/hooks/tests/pretool-edit-cap.test.sh
# Exits 0 on full pass, 1 on any failure.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/pretool-edit-cap.sh"

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

setup() {
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/.claude"
    TRACKER="$TEST_DIR/.claude/.session-activity"
}

teardown() {
    rm -rf "$TEST_DIR"
}

edit_input() {
    printf '{"session_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s"}}' \
        "$1" "$2" "$3"
}

FILE="/work/src/lib.rs"

# 1. No tracker — allow.
setup
edit_input sess-a Edit "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "no tracker allows" "0" "$?"
teardown

# 2. 3 EDITs same session — allow.
setup
for _ in 1 2 3; do echo "sess-a EDIT $FILE" >> "$TRACKER"; done
edit_input sess-a Edit "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "3 edits below cap allows" "0" "$?"
teardown

# 3. 4 EDITs same session — block once, BLOCKED recorded.
setup
for _ in 1 2 3 4; do echo "sess-a EDIT $FILE" >> "$TRACKER"; done
STDERR=$(edit_input sess-a Edit "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>&1 >/dev/null)
RC=$?
run_case "4 edits blocks" "2" "$RC"
run_case "block message says one-shot" "yes" "$([[ "$STDERR" == *"next Edit"* ]] && echo yes || echo no)"
run_case "BLOCKED line recorded" "1" "$(grep -cxF "sess-a BLOCKED $FILE" "$TRACKER")"
teardown

# 4. BLOCKED already set — allow (one-shot).
setup
for _ in 1 2 3 4; do echo "sess-a EDIT $FILE" >> "$TRACKER"; done
echo "sess-a BLOCKED $FILE" >> "$TRACKER"
edit_input sess-a Edit "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "after block allows (one-shot)" "0" "$?"
teardown

# 5. 4 EDITs from another session — allow.
setup
for _ in 1 2 3 4; do echo "sess-b EDIT $FILE" >> "$TRACKER"; done
edit_input sess-a Edit "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "other session's edits ignored" "0" "$?"
teardown

# 6. Legacy bare-path lines — ignored.
setup
for _ in 1 2 3 4 5; do echo "$FILE" >> "$TRACKER"; done
edit_input sess-a Edit "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "legacy lines ignored" "0" "$?"
teardown

# 7. VAUCHI_EDIT_CAP=0 — allow, no BLOCKED written.
setup
for _ in 1 2 3 4; do echo "sess-a EDIT $FILE" >> "$TRACKER"; done
edit_input sess-a Edit "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" VAUCHI_EDIT_CAP=0 bash "$HOOK" 2>/dev/null
RC=$?
run_case "env escape allows" "0" "$RC"
run_case "env escape records nothing" "0" "$(grep -cxF "sess-a BLOCKED $FILE" "$TRACKER")"
teardown

# 8. tool_name=Write — always allowed.
setup
for _ in 1 2 3 4; do echo "sess-a EDIT $FILE" >> "$TRACKER"; done
edit_input sess-a Write "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "Write tool allowed" "0" "$?"
teardown

# 9. Exact-line match — edits of foo.rs.bak don't count against foo.rs.
setup
for _ in 1 2 3 4; do echo "sess-a EDIT $FILE.bak" >> "$TRACKER"; done
edit_input sess-a Edit "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "substring path not counted" "0" "$?"
teardown

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
