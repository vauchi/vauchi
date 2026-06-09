#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Test runner for `.claude/hooks/check-branch-delete.sh`.
#
# The hook guards `git branch -D` (force-delete) against losing commits
# that are not yet in origin/main. It uses `git cherry` (patch-id), so it
# correctly ALLOWS deletion of squash-merged branches (reachability says
# "unmerged" but the patch is already in main) and BLOCKS deletion of
# genuinely-unmerged branches. This is the most-recurrent reasoning error
# in the project log (4 incidents: deleted-unmerged-branch, ghost-MRs,
# squash-merge false-positive, stale ahead/behind).
#
# Uses a REAL throwaway git repo — no mocking — mirroring the project's
# "use real operations" testing philosophy.
#
# Run: bash .claude/hooks/tests/check-branch-delete.test.sh
# Exits 0 on full pass, 1 on any failure.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/check-branch-delete.sh"
WORK="/tmp/check-branch-delete.test.$$"

if [[ ! -x "$HOOK" ]]; then
    echo "FATAL: $HOOK not executable (hook not implemented yet — RED)" >&2
    exit 1
fi

PASS=0
FAIL=0

expect_exit() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  PASS  %s\n' "$name"; PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n    expected exit: %s\n    got:           %s\n' \
            "$name" "$expected" "$actual"; FAIL=$((FAIL + 1))
    fi
}

expect_contains() {
    local name="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  PASS  %s\n' "$name"; PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n    expected to contain: %s\n    got: %s\n' \
            "$name" "$needle" "$haystack"; FAIL=$((FAIL + 1))
    fi
}

# Build a real repo:
#   main                 base commit
#   feat-merged          commit cherry-picked onto main (squash-merge analogue:
#                        different SHA, same patch-id → `git cherry` marks it `-`)
#   feat-unmerged        commit NOT in main → `git cherry` marks it `+`
REPO="$WORK/repo"
setup_repo() {
    rm -rf "$WORK"
    mkdir -p "$REPO/.claude"
    touch "$REPO/.claude/.session-errors"
    git -C "$REPO" init -q -b main
    git -C "$REPO" config user.email t@t.t
    git -C "$REPO" config user.name t
    echo base > "$REPO/file"
    git -C "$REPO" add file
    git -C "$REPO" commit -qm base

    # feat-merged: a commit whose patch lands on main via a different SHA
    git -C "$REPO" checkout -q -b feat-merged
    echo merged-change >> "$REPO/file"
    git -C "$REPO" commit -qam "feat: merged change"
    git -C "$REPO" checkout -q main
    # cherry-pick has no -q; pick the tip onto main → different SHA, same patch-id
    git -C "$REPO" cherry-pick feat-merged >/dev/null 2>&1

    # feat-unmerged: a commit that never reaches main
    git -C "$REPO" checkout -q -b feat-unmerged main
    echo unmerged-change >> "$REPO/other"
    git -C "$REPO" add other
    git -C "$REPO" commit -qm "feat: unmerged change"
    git -C "$REPO" checkout -q main

    # Pin origin/main to the current main tip (no real remote needed)
    git -C "$REPO" update-ref refs/remotes/origin/main main
}

trap 'rm -rf "$WORK"' EXIT

# Invoke hook with a JSON envelope; returns combined stdout+stderr, sets $?
run_hook() {
    local cmd="$1"
    local json
    json=$(jq -nc --arg cmd "$cmd" --arg cwd "$REPO" \
        '{tool_input:{command:$cmd},cwd:$cwd}')
    CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<< "$json" 2>&1
}

# ── C1: force-delete of a squash-merged branch is ALLOWED ──
setup_repo
out=$(run_hook "git -C $REPO branch -D feat-merged"); code=$?
expect_exit "C1 -D squash-merged branch: allowed (cherry all '-')" "0" "$code"

# ── C2: force-delete of a genuinely-unmerged branch is BLOCKED ──
setup_repo
out=$(run_hook "git -C $REPO branch -D feat-unmerged"); code=$?
expect_exit     "C2 -D unmerged branch: blocked"        "2" "$code"
expect_contains "C2 names the branch"                   "feat-unmerged" "$out"
expect_contains "C2 mentions cherry"                    "cherry" "$out"

# ── C3: plain -d (no force) is NOT intercepted (git's own check suffices) ──
setup_repo
out=$(run_hook "git -C $REPO branch -d feat-unmerged"); code=$?
expect_exit "C3 plain -d: not intercepted" "0" "$code"

# ── C4: non-branch git command is ignored ──
setup_repo
out=$(run_hook "git -C $REPO status"); code=$?
expect_exit "C4 git status: ignored" "0" "$code"

# ── C5: --delete --force is treated as force-delete and blocked ──
setup_repo
out=$(run_hook "git -C $REPO branch --delete --force feat-unmerged"); code=$?
expect_exit "C5 --delete --force unmerged: blocked" "2" "$code"

# ── C6: deleting multiple branches blocks if ANY is unmerged ──
setup_repo
out=$(run_hook "git -C $REPO branch -D feat-merged feat-unmerged"); code=$?
expect_exit     "C6 mixed batch: blocked"          "2" "$code"
expect_contains "C6 names only the unmerged one"   "feat-unmerged" "$out"

# ── C7: bare command (no -C) resolves repo from cwd/CLAUDE_PROJECT_DIR ──
setup_repo
out=$(run_hook "git branch -D feat-unmerged"); code=$?
expect_exit "C7 bare -D unmerged via cwd: blocked" "2" "$code"

# ── C8: missing origin/main → cannot verify → advisory, allow ──
setup_repo
git -C "$REPO" update-ref -d refs/remotes/origin/main
out=$(run_hook "git -C $REPO branch -D feat-unmerged"); code=$?
expect_exit     "C8 no origin/main: allowed (advisory)" "0" "$code"
expect_contains "C8 warns it could not verify"          "could not verify" "$out"

# ── C9: remote-branch delete (push --delete) is NOT a local branch op ──
setup_repo
out=$(run_hook "git -C $REPO push origin --delete feat-unmerged"); code=$?
expect_exit "C9 push --delete: ignored (not local branch op)" "0" "$code"

# ── Summary ──
echo ""
if [[ "$FAIL" -eq 0 ]]; then
    printf 'check-branch-delete.test: %d passed, 0 failed\n' "$PASS"; exit 0
else
    printf 'check-branch-delete.test: %d passed, %d FAILED\n' "$PASS" "$FAIL"; exit 1
fi
