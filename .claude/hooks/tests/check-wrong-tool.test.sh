#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Test runner for `.claude/hooks/check-wrong-tool.sh`.
#
# Run: bash .claude/hooks/tests/check-wrong-tool.test.sh
# Exits 0 on full pass, 1 on any failure.

set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/check-wrong-tool.sh"
[[ -x "$HOOK" ]] || { echo "FATAL: $HOOK not executable" >&2; exit 1; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s — expected %s, got %s\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s — expected to contain: %s\n  got: %s\n' "$name" "$needle" "$haystack"
    FAIL=$((FAIL + 1))
  fi
}

run() {
  echo "{\"tool_input\":{\"command\":$(printf '%s' "$1" | jq -Rs .)}}" | "$HOOK" 2>"$TMP/err"
  echo "$?"
}
run_env() {
  local env="$1" cmd="$2"
  env "$env" bash -c "echo '{\"tool_input\":{\"command\":$(printf '%s' "$cmd" | jq -Rs .)}}' | '$HOOK'" 2>"$TMP/err"
  echo "$?"
}

# Blocks
assert_exit "blocks cat file"          "2" "$(run 'cat /etc/hosts')"
assert_contains "cat block names Read"  "Read"   "$(cat "$TMP/err")"

assert_exit "blocks head file"         "2" "$(run 'head -n 50 src/foo.rs')"
assert_exit "blocks tail file"         "2" "$(run 'tail src/foo.rs')"
assert_exit "blocks find -name"        "2" "$(run 'find . -name "*.rs"')"
assert_exit "blocks grep -r"           "2" "$(run 'grep -r foo src/')"
assert_exit "blocks grep -R"           "2" "$(run 'grep -R foo src/')"
assert_exit "blocks grep -rn"          "2" "$(run 'grep -rn foo src/')"

# Allow — composed
assert_exit "allows pipeline cat"      "0" "$(run 'cat foo | jq .')"
assert_exit "allows redirect cat"      "0" "$(run 'cat foo > /tmp/x')"
assert_exit "allows && composition"    "0" "$(run 'cat foo && echo done')"
assert_exit "allows ; composition"     "0" "$(run 'cat foo ; echo done')"
assert_exit "allows find -exec"        "0" "$(run 'find . -name "*.rs" -exec wc -l {} \;')"
assert_exit "allows grep -r | head"    "0" "$(run 'grep -r foo src/ | head')"
assert_exit "allows command sub"       "0" "$(run 'echo $(cat foo)')"
assert_exit "allows find without name" "0" "$(run 'find . -newer marker -delete')"

# Allow — non-matching commands
assert_exit "allows git status"        "0" "$(run 'git status')"
assert_exit "allows just check"        "0" "$(run 'just check')"
assert_exit "allows echo"              "0" "$(run 'echo hello')"
assert_exit "allows ls"                "0" "$(run 'ls src/')"

# Escape hatch
assert_exit "ALLOW_RAW_BASH overrides" "0" "$(run_env 'ALLOW_RAW_BASH=1' 'cat /etc/hosts')"

# Empty command
assert_exit "empty command silent"     "0" "$(run '')"

echo "---"
echo "Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
