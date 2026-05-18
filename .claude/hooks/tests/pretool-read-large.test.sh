#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Test runner for `.claude/hooks/pretool-read-large.sh`.
#
# Paths covered:
#   1. Small file (<=500 lines)            — exit 0, silent.
#   2. Large file (>500 lines), no slice   — exit 2, block message.
#   3. Large file + offset                 — exit 0.
#   4. Large file + limit                  — exit 0.
#   5. Large file + ALLOW_FULL_READ=1      — exit 0.
#   6. Missing file                        — exit 0.
#   7. Image extension                     — exit 0.
#   8. Empty file_path                     — exit 0.
#
# Run: bash .claude/hooks/tests/pretool-read-large.test.sh
# Exits 0 on full pass, 1 on any failure.

set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/pretool-read-large.sh"
[[ -x "$HOOK" ]] || { echo "FATAL: $HOOK not executable" >&2; exit 1; }

PASS=0
FAIL=0

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf '  PASS  %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s — expected exit %s, got %s\n' "$name" "$expected" "$actual"
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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SMALL="$TMP/small.txt"
LARGE="$TMP/large.rs"
MISSING="$TMP/does-not-exist.txt"
IMAGE="$TMP/photo.png"

# 100-line small file
seq 1 100 > "$SMALL"
# 501-line large file (just over threshold)
seq 1 501 > "$LARGE"
# Image — placeholder bytes; extension drives the skip
printf '\x89PNG\r\n\x1a\n' > "$IMAGE"
seq 1 1000 >> "$IMAGE"  # also >500 lines to confirm extension wins

run() {
  echo "$1" | "$HOOK" 2>"$TMP/err"
  echo "$?"
}
run_env() {
  local env="$1" input="$2"
  env "$env" bash -c "echo '$input' | '$HOOK'" 2>"$TMP/err"
  echo "$?"
}

# Path 1: small file → exit 0, no stderr
exit_code=$(run "{\"tool_input\":{\"file_path\":\"$SMALL\"}}")
assert_exit "1 small file exit" "0" "$exit_code"
assert_exit "1 small file (no stderr)" "" "$(cat "$TMP/err")"

# Path 2: large file no slice → exit 2 with structured message
exit_code=$(run "{\"tool_input\":{\"file_path\":\"$LARGE\"}}")
err=$(cat "$TMP/err")
assert_exit "2 large file blocks" "2" "$exit_code"
assert_contains "2 message names file path" "$LARGE" "$err"
assert_contains "2 message names line count" "501 lines" "$err"
assert_contains "2 message offers offset/limit" "offset=" "$err"
assert_contains "2 message names escape hatch" "ALLOW_FULL_READ" "$err"

# Path 3: large file with offset → exit 0
exit_code=$(run "{\"tool_input\":{\"file_path\":\"$LARGE\",\"offset\":1}}")
assert_exit "3 large + offset silent" "0" "$exit_code"

# Path 4: large file with limit → exit 0
exit_code=$(run "{\"tool_input\":{\"file_path\":\"$LARGE\",\"limit\":50}}")
assert_exit "4 large + limit silent" "0" "$exit_code"

# Path 5: large file with ALLOW_FULL_READ=1 → exit 0
exit_code=$(run_env "ALLOW_FULL_READ=1" "{\"tool_input\":{\"file_path\":\"$LARGE\"}}")
assert_exit "5 ALLOW_FULL_READ override" "0" "$exit_code"

# Path 6: missing file → exit 0
exit_code=$(run "{\"tool_input\":{\"file_path\":\"$MISSING\"}}")
assert_exit "6 missing file silent" "0" "$exit_code"

# Path 7: image extension, large by lines → exit 0
exit_code=$(run "{\"tool_input\":{\"file_path\":\"$IMAGE\"}}")
assert_exit "7 image extension silent" "0" "$exit_code"

# Path 8: empty file_path → exit 0
exit_code=$(run '{"tool_input":{}}')
assert_exit "8 empty file_path silent" "0" "$exit_code"

echo "---"
echo "Pass: $PASS  Fail: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
