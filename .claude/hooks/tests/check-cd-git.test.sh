#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Test runner for `.claude/hooks/check-cd-git.sh`.
#
# Covers: `cd && git` blocking, `cd && cmd` blocking, subshell exemption,
# CLAUDE_PROJECT_DIR exemption, bare-cd blocking, git-commit skip,
# `git -C root` block. Also a regression case for the
# "stray \ before /" warning that fired on every CLAUDE_PROJECT_DIR
# exemption check (over-escaped `/` in the sed metacharacter class).
#
# Run: bash .claude/hooks/tests/check-cd-git.test.sh
# Exits 0 on full pass, 1 on any failure. Each case prints PASS/FAIL.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/check-cd-git.sh"
FAKE_ROOT="/tmp/check-cd-git.test.$$"

if [[ ! -x "$HOOK" ]]; then
    echo "FATAL: $HOOK not executable" >&2
    exit 1
fi

# Pre-create .claude/ + .session-errors so the hook's log_error path
# stays silent (otherwise it prints "No such file or directory" to
# stderr, polluting the per-case output).
mkdir -p "$FAKE_ROOT/.claude"
touch "$FAKE_ROOT/.claude/.session-errors"
trap 'rm -rf "$FAKE_ROOT"' EXIT

PASS=0
FAIL=0

expect_contains() {
    local name="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n    expected to contain: %s\n    got:                 %s\n' \
            "$name" "$needle" "$haystack"
        FAIL=$((FAIL + 1))
    fi
}

expect_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf '  PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n    must NOT contain: %s\n    got:              %s\n' \
            "$name" "$needle" "$haystack"
        FAIL=$((FAIL + 1))
    fi
}

expect_exit() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n    expected exit: %s\n    got:           %s\n' \
            "$name" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

# Invoke the hook with a JSON envelope.
# `out`  ← combined stdout+stderr
# `code` ← exit code (in the shell var $? after this returns)
run_hook() {
    local cmd="$1"
    local json
    json=$(jq -nc --arg cmd "$cmd" --arg cwd "$FAKE_ROOT" \
        '{tool_input:{command:$cmd},cwd:$cwd}')
    CLAUDE_PROJECT_DIR="$FAKE_ROOT" bash "$HOOK" <<< "$json" 2>&1
}

STRAY="stray \\ before /"
CD_GIT_MSG="Use \"git -C <dir> ...\" instead"
CD_CMD_MSG="drifts the working directory"
BARE_CD_MSG="Bare \"cd\" drifts"
ROOT_MSG="Do not use \"git -C root\""

# ── Regression for the stray-backslash warning: ANY firing of the
#         CLAUDE_PROJECT_DIR exemption path must not emit grep warnings,
#         regardless of how many `/` segments the project dir contains.
out=$(run_hook "cd _private && markdownlint foo.md"); code=$?
expect_not_contains "R1 no 'stray \\ before /' warning on cd-blocking path" "$STRAY" "$out"
expect_contains     "R1 still blocks (cd <dir> && cmd)"                     "$CD_CMD_MSG" "$out"
expect_exit         "R1 exits 2"                                            "2" "$code"

# ── Case 1: cd && git → blocked with git-C nudge ──
out=$(run_hook "cd _private && git status"); code=$?
expect_contains "C1 cd && git: blocked with git -C nudge" "$CD_GIT_MSG" "$out"
expect_exit     "C1 exits 2"                              "2" "$code"

# ── Case 2: cd ; git → blocked ──
out=$(run_hook "cd _private ; git status"); code=$?
expect_contains "C2 cd ; git: blocked" 'use "git -C <dir> ..." instead' "$out"
expect_exit     "C2 exits 2"            "2" "$code"

# ── Case 3: subshell (cd && cmd) is exempt ──
out=$(run_hook "(cd _private && markdownlint foo.md)"); code=$?
expect_not_contains "C3 subshell: not blocked" "$CD_CMD_MSG" "$out"
expect_exit         "C3 exits 0"               "0" "$code"

# ── Case 4: cd $CLAUDE_PROJECT_DIR is safe (returns to root) ──
out=$(run_hook "cd $FAKE_ROOT && ls"); code=$?
expect_not_contains "C4 cd into project root: not blocked" "$CD_CMD_MSG" "$out"
expect_exit         "C4 exits 0"                           "0" "$code"

# ── Case 5: git -C <dir> is always safe ──
out=$(run_hook "git -C _private status"); code=$?
expect_exit "C5 git -C <dir>: exits 0" "0" "$code"

# ── Case 6: git -C root is blocked (workspace root is the root repo) ──
out=$(run_hook "git -C root status"); code=$?
expect_contains "C6 git -C root: blocked" "$ROOT_MSG" "$out"
expect_exit     "C6 exits 2"              "2" "$code"

# ── Case 7: bare cd is blocked ──
out=$(run_hook "cd _private"); code=$?
expect_contains "C7 bare cd: blocked" "$BARE_CD_MSG" "$out"
expect_exit     "C7 exits 2"          "2" "$code"

# ── Case 8: git commit/tag bodies are skipped (body may legitimately mention cd) ──
out=$(run_hook 'git commit -m "fix: cd into bar then check"'); code=$?
expect_exit "C8 git commit body skipped: exits 0" "0" "$code"

# ── Summary ──
echo ""
if [[ "$FAIL" -eq 0 ]]; then
    printf 'check-cd-git.test: %d passed, 0 failed\n' "$PASS"
    exit 0
else
    printf 'check-cd-git.test: %d passed, %d FAILED\n' "$PASS" "$FAIL"
    exit 1
fi
