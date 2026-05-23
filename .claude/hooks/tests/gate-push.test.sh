#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Test runner for `.claude/hooks/gate-push.sh`.
#
# Covers the branch-gate, --no-verify gate, --tags exemption, and WIP-HEAD
# guard at the top of the hook. Does NOT exercise the post-branch lint/test
# cascade (those run in real-repo CI; we only care that "Push to main
# blocked" fires correctly here).
#
# Run: bash .claude/hooks/tests/gate-push.test.sh
# Exits 0 on full pass, 1 on any failure. Each case prints PASS/FAIL.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/gate-push.sh"

if [[ ! -x "$HOOK" ]]; then
    echo "FATAL: $HOOK not executable" >&2
    exit 1
fi

PASS=0
FAIL=0

# Assert that the haystack contains the needle.
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

# Assert that the haystack does NOT contain the needle.
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

# Create a minimal git repo on `main` (one empty commit) and return its path.
setup_repo() {
    local repo
    repo=$(mktemp -d)
    git -C "$repo" init -q -b main 2>/dev/null \
        || { git -C "$repo" init -q && git -C "$repo" symbolic-ref HEAD refs/heads/main; }
    git -C "$repo" config user.email "test@test.local"
    git -C "$repo" config user.name  "Test"
    git -C "$repo" commit --allow-empty -q -m "init"
    printf '%s' "$repo"
}

# Switch the repo to a feature branch.
checkout_branch() {
    local repo="$1" branch="$2"
    git -C "$repo" checkout -q -b "$branch"
}

# Set HEAD commit message (used to simulate WIP head).
amend_msg() {
    local repo="$1" msg="$2"
    git -C "$repo" commit --allow-empty -q --amend -m "$msg"
}

# Invoke the hook with a JSON envelope mimicking the PreToolUse contract.
# Returns combined stdout+stderr.
run_hook() {
    local cmd="$1" cwd="$2"
    local json
    json=$(jq -nc --arg cmd "$cmd" --arg cwd "$cwd" \
        '{tool_input:{command:$cmd},cwd:$cwd}')
    printf '%s' "$json" | bash "$HOOK" 2>&1
}

BLOCK_MSG="Push to main blocked"
NV_MSG="--no-verify is blocked"
WIP_MSG="HEAD is a WIP checkpoint"

# ── Case 1: from main, push to a non-main feature branch — ALLOW ──
repo=$(setup_repo)
out=$(run_hook "git -C $repo push -u origin feature/foo" "$repo")
expect_not_contains "C1 from main, push to feature: not blocked by branch gate" \
    "$BLOCK_MSG" "$out"
rm -rf "$repo"

# ── Case 2: from main, explicit push to main — BLOCK ──
repo=$(setup_repo)
out=$(run_hook "git -C $repo push origin main" "$repo")
expect_contains "C2 from main, explicit push to main: blocked" "$BLOCK_MSG" "$out"
rm -rf "$repo"

# ── Case 3: from main, bare `git push` (implicit destination) — BLOCK ──
repo=$(setup_repo)
out=$(run_hook "git -C $repo push" "$repo")
expect_contains "C3 from main, bare push: blocked" "$BLOCK_MSG" "$out"
rm -rf "$repo"

# ── Case 4: from main, `git push origin` (no branch arg) — BLOCK ──
repo=$(setup_repo)
out=$(run_hook "git -C $repo push origin" "$repo")
expect_contains "C4 from main, push origin (no branch): blocked" "$BLOCK_MSG" "$out"
rm -rf "$repo"

# ── Case 5 (THE BUG): chained `checkout -b ... && push -u origin <branch>`
#         from a transient main view — ALLOW. The hook must see the push
#         subcommand's args, not just the first segment before `&&`.
repo=$(setup_repo)
cmd="git -C $repo checkout -b tidy/foo && git -C $repo push -u origin tidy/foo"
out=$(run_hook "$cmd" "$repo")
expect_not_contains "C5 chained checkout+push: not blocked by branch gate" \
    "$BLOCK_MSG" "$out"
rm -rf "$repo"

# ── Case 6: tag push (--tags) from main — ALLOW (explicit exemption) ──
repo=$(setup_repo)
out=$(run_hook "git -C $repo push --tags origin" "$repo")
expect_not_contains "C6 tag push from main: exempt" "$BLOCK_MSG" "$out"
rm -rf "$repo"

# ── Case 7: --no-verify is blocked regardless of branch ──
repo=$(setup_repo)
checkout_branch "$repo" "feature/foo"
out=$(run_hook "git -C $repo push --no-verify -u origin feature/foo" "$repo")
expect_contains "C7 --no-verify from feature: blocked" "$NV_MSG" "$out"
rm -rf "$repo"

# ── Case 8: WIP-head commit blocks push regardless of branch ──
repo=$(setup_repo)
checkout_branch "$repo" "feature/foo"
amend_msg "$repo" "wip: in-progress checkpoint"
out=$(run_hook "git -C $repo push -u origin feature/foo" "$repo")
expect_contains "C8 WIP HEAD blocks push" "$WIP_MSG" "$out"
rm -rf "$repo"

# ── Case 9: branch deletion (--delete) is always exempt ──
repo=$(setup_repo)
out=$(run_hook "git -C $repo push origin --delete main" "$repo")
expect_not_contains "C9 branch deletion: exempt" "$BLOCK_MSG" "$out"
rm -rf "$repo"

# ── Case 10: chained pushes — second one targets main — BLOCK ──
repo=$(setup_repo)
cmd="git -C $repo push origin feature/foo && git -C $repo push origin main"
out=$(run_hook "$cmd" "$repo")
expect_contains "C10 second-of-chain pushes to main: blocked" "$BLOCK_MSG" "$out"
rm -rf "$repo"

# ── Summary ──
echo ""
if [[ "$FAIL" -eq 0 ]]; then
    printf 'gate-push.test: %d passed, 0 failed\n' "$PASS"
    exit 0
else
    printf 'gate-push.test: %d passed, %d FAILED\n' "$PASS" "$FAIL"
    exit 1
fi
