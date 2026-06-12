#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Test runner for `.claude/hooks/pretool-read-cap.sh`.
#
# Covers the session-scoped tracker redesign
# (2026-04-20-excessive-reedit-reread-pattern, 2026-06-12 findings):
#   1. 2 READs               — allow (below cap).
#   2. 3 READs               — block the 4th (exit 2).
#   3. offset/limit          — allow regardless of count.
#   4. EDIT after last READ  — allow (verify-after-edit, fixes F4).
#   5. EDIT before last READ — block (escape must not leak).
#   6. WRITE after last READ — allow (Write flips the escape too).
#   7. 3 READs other session — allow (session isolation, fixes F1).
#   8. VAUCHI_READ_CAP=0     — allow (revert hatch).
#   9. Legacy bare-path rows — allow (clean migration).
#
# Run: bash .claude/hooks/tests/pretool-read-cap.test.sh
# Exits 0 on full pass, 1 on any failure.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/pretool-read-cap.sh"

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

read_input() {
    printf '{"session_id":"%s","tool_name":"Read","tool_input":{"file_path":"%s"}}' \
        "$1" "$2"
}

FILE="/work/src/lib.rs"

# 1. 2 READs — allow.
setup
for _ in 1 2; do echo "sess-a READ $FILE" >> "$TRACKER"; done
read_input sess-a "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "2 reads below cap allows" "0" "$?"
teardown

# 2. 3 READs — block the 4th.
setup
for _ in 1 2 3; do echo "sess-a READ $FILE" >> "$TRACKER"; done
read_input sess-a "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "3 reads blocks 4th" "2" "$?"
teardown

# 3. offset/limit — allow regardless.
setup
for _ in 1 2 3 4 5; do echo "sess-a READ $FILE" >> "$TRACKER"; done
printf '{"session_id":"sess-a","tool_name":"Read","tool_input":{"file_path":"%s","offset":10,"limit":40}}' "$FILE" \
    | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "sliced read always allowed" "0" "$?"
teardown

# 4. EDIT after last READ — allow.
setup
for _ in 1 2 3; do echo "sess-a READ $FILE" >> "$TRACKER"; done
echo "sess-a EDIT $FILE" >> "$TRACKER"
read_input sess-a "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "verify-after-edit allows" "0" "$?"
teardown

# 5. EDIT before last READ — block.
setup
echo "sess-a EDIT $FILE" >> "$TRACKER"
for _ in 1 2 3; do echo "sess-a READ $FILE" >> "$TRACKER"; done
read_input sess-a "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "stale edit does not leak escape" "2" "$?"
teardown

# 6. WRITE after last READ — allow.
setup
for _ in 1 2 3; do echo "sess-a READ $FILE" >> "$TRACKER"; done
echo "sess-a WRITE $FILE" >> "$TRACKER"
read_input sess-a "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "verify-after-write allows" "0" "$?"
teardown

# 7. 3 READs from another session — allow.
setup
for _ in 1 2 3; do echo "sess-b READ $FILE" >> "$TRACKER"; done
read_input sess-a "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "other session's reads ignored" "0" "$?"
teardown

# 8. VAUCHI_READ_CAP=0 — allow.
setup
for _ in 1 2 3; do echo "sess-a READ $FILE" >> "$TRACKER"; done
read_input sess-a "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" VAUCHI_READ_CAP=0 bash "$HOOK" 2>/dev/null
run_case "env escape allows" "0" "$?"
teardown

# 9. Legacy bare-path lines — ignored.
setup
for _ in 1 2 3 4; do echo "$FILE" >> "$TRACKER"; done
read_input sess-a "$FILE" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$HOOK" 2>/dev/null
run_case "legacy lines ignored" "0" "$?"
teardown

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
