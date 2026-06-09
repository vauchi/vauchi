#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Test runner for `.claude/hooks/log-bash-edits.sh`.
#
# The edit-cap (pretool-edit-cap.sh) and auto-format (post-edit.sh) bind
# ONLY to the Edit|Write matcher. A file edit performed through the Bash
# tool (`sed -i`, `perl -i`, `tee`, a `python -c` open(...,'w'), or a
# `>`/`>>` redirect into a source file) is invisible to all of them — not
# counted toward the cap, not auto-checked, not flagged. That blind spot
# means the observed "excessive-reedit dropped 169→39" may be partly
# DISPLACEMENT into Bash, not real reduction.
#
# This hook is observation-only (always exit 0) — it makes the blind spot
# measurable so a future cap decision rests on data, mirroring how
# log-read-patterns.sh preceded pretool-read-cap.sh.
#
# Run: bash .claude/hooks/tests/log-bash-edits.test.sh
# Exits 0 on full pass, 1 on any failure.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/log-bash-edits.sh"
WORK="/tmp/log-bash-edits.test.$$"

if [[ ! -x "$HOOK" ]]; then
    echo "FATAL: $HOOK not executable (hook not implemented yet — RED)" >&2
    exit 1
fi

PASS=0
FAIL=0
mkdir -p "$WORK/.claude"
LOG="$WORK/.claude/.session-errors"
trap 'rm -rf "$WORK"' EXIT

# Run hook with a Bash-tool envelope; returns exit code, leaves LOG written.
run_hook() {
    : > "$LOG"
    local cmd="$1"
    local json
    json=$(jq -nc --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}')
    CLAUDE_PROJECT_DIR="$WORK" bash "$HOOK" <<< "$json"
    return $?
}

expect_exit() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  PASS  %s\n' "$name"; PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n    expected exit %s, got %s\n' "$name" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

expect_logged() {
    local name="$1" tool="$2"
    if grep -q '"category":"bash-file-edit"' "$LOG" 2>/dev/null \
        && grep -q "\"tool\":\"$tool\"" "$LOG" 2>/dev/null; then
        printf '  PASS  %s\n' "$name"; PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n    expected a bash-file-edit log with tool=%s; got: %s\n' \
            "$name" "$tool" "$(cat "$LOG" 2>/dev/null)"; FAIL=$((FAIL + 1))
    fi
}

expect_not_logged() {
    local name="$1"
    if [[ ! -s "$LOG" ]]; then
        printf '  PASS  %s\n' "$name"; PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n    expected no log; got: %s\n' "$name" "$(cat "$LOG")"
        FAIL=$((FAIL + 1))
    fi
}

# ── Always non-blocking ──
run_hook "sed -i 's/a/b/' core/src/foo.rs"; expect_exit "always exits 0 (observer)" "0" "$?"

# ── In-place editors are logged ──
run_hook "sed -i 's/a/b/' core/src/foo.rs"      ; expect_logged   "sed -i logged"            "sed-i"
run_hook "sed -i.bak 's/a/b/' core/src/foo.rs"  ; expect_logged   "sed -i.bak logged"        "sed-i"
run_hook "perl -i -pe 's/a/b/' README.md"       ; expect_logged   "perl -i logged"           "perl-i"

# ── tee into a source file is logged ──
run_hook "echo x | tee core/Cargo.toml"         ; expect_logged   "tee into source logged"   "tee"

# ── python write is logged ──
run_hook "python3 -c 'open(\"x.rs\",\"w\").write(\"a\")'" ; expect_logged "python write logged" "python"

# ── redirect into a source file is logged ──
run_hook "echo bump > core/Cargo.toml"          ; expect_logged   "redirect to source logged" "redirect"
run_hook "cat tpl >> docs/src/index.md"         ; expect_logged   "append to source logged"   "redirect"

# ── NOT logged: read-only / safe sinks ──
run_hook "sed -n '1,5p' core/src/foo.rs"        ; expect_not_logged "sed -n (read) not logged"
run_hook "grep foo bar > /dev/null"             ; expect_not_logged "redirect to /dev/null not logged"
run_hook "cargo build > /tmp/out.log"           ; expect_not_logged "redirect to /tmp not logged"
run_hook "just check"                           ; expect_not_logged "plain command not logged"
run_hook "cat core/src/foo.rs"                  ; expect_not_logged "cat (read) not logged"

# ── Summary ──
echo ""
if [[ "$FAIL" -eq 0 ]]; then
    printf 'log-bash-edits.test: %d passed, 0 failed\n' "$PASS"; exit 0
else
    printf 'log-bash-edits.test: %d passed, %d FAILED\n' "$PASS" "$FAIL"; exit 1
fi
