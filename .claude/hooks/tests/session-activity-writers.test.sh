#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Test runner for the `.session-activity` writer side of
# `post-edit.sh` and `log-read-patterns.sh`. The line format
# `<session_id> <VERB> <file_path>` is the contract the cap hooks
# count against — a writer/reader drift would silently disable or
# misfire both caps.
#
#   1. post-edit on Edit          — appends "SID EDIT path".
#   2. post-edit on Write         — appends "SID WRITE path".
#   3. log-read-patterns full     — appends "SID READ path".
#   4. log-read-patterns sliced   — appends nothing (offset/limit
#                                    reads are exempt from the cap,
#                                    so they must not count).
#
# Run: bash .claude/hooks/tests/session-activity-writers.test.sh
# Exits 0 on full pass, 1 on any failure.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
POST_EDIT="$HOOK_DIR/post-edit.sh"
LOG_READS="$HOOK_DIR/log-read-patterns.sh"

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
    # .txt avoids every dispatch case in post-edit.sh (rustfmt, SPDX,
    # linters) so only the tracker section is exercised.
    TARGET="$TEST_DIR/note.txt"
    echo "content" > "$TARGET"
}

teardown() {
    rm -rf "$TEST_DIR"
}

tool_input() {
    printf '{"session_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s"}}' \
        "$1" "$2" "$3"
}

# 1. post-edit on Edit appends EDIT line.
setup
tool_input sess-a Edit "$TARGET" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$POST_EDIT" >/dev/null 2>&1
run_case "Edit appends EDIT line" "1" "$(grep -cxF "sess-a EDIT $TARGET" "$TRACKER" 2>/dev/null)"
teardown

# 2. post-edit on Write appends WRITE line.
setup
tool_input sess-a Write "$TARGET" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$POST_EDIT" >/dev/null 2>&1
run_case "Write appends WRITE line" "1" "$(grep -cxF "sess-a WRITE $TARGET" "$TRACKER" 2>/dev/null)"
teardown

# 3. log-read-patterns appends READ line on full read.
setup
tool_input sess-a Read "$TARGET" | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$LOG_READS" >/dev/null 2>&1
run_case "full Read appends READ line" "1" "$(grep -cxF "sess-a READ $TARGET" "$TRACKER" 2>/dev/null)"
teardown

# 4. Sliced read appends nothing.
setup
printf '{"session_id":"sess-a","tool_name":"Read","tool_input":{"file_path":"%s","offset":5,"limit":20}}' "$TARGET" \
    | CLAUDE_PROJECT_DIR="$TEST_DIR" bash "$LOG_READS" >/dev/null 2>&1
run_case "sliced Read not tracked" "0" "$(grep -cF "$TARGET" "$TRACKER" 2>/dev/null || echo 0)"
teardown

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
