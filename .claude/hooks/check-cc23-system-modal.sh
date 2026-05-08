#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse hook: blocks Edit/Write that introduces the CC-23
# anti-pattern — instantiating a foreign-process `XCUIApplication`
# by bundle identifier in a Swift test file.
#
# Background (`.claude/rules/test-quality-rules.md` CC-23):
#   UI tests that poll `XCUIApplication(bundleIdentifier:
#   "com.apple.…")` to verify a system-owned modal *actually
#   presented* fail in two structural ways:
#     (1) the system modal can cover any in-app sentinel before
#         XCTest can query it, so the predicate times out even
#         when the bridge fired correctly;
#     (2) the system bundle id and chrome label set drift across
#         iOS / macOS versions — a test that passed on iOS 17
#         silently regresses on iOS 26.
#   Test the state that drives the presentation
#   (`@Published` flag, `pendingFilePick` value, injected
#   hardware-event callback) at the unit layer instead.
#
# Failure-mode history: ios!401 pivot from
# `FilePickerReachabilityUITests.swift` to
# `VauchiTests/CoreUI/ExchangeCommandBridgeTests.swift`
# (2026-05-04). CC-23 was added to codify the lesson; this hook
# enforces it mechanically (audit finding R-2 / F2, 2026-05-08).

INPUT=$(cat)

# Only Swift files matter; gate is cheap to run on others.
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
case "$FILE" in
    *.swift) ;;
    *) exit 0 ;;
esac

# Edit and Write carry the new content under different keys; pick
# whichever is present.
CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // empty')
[ -z "$CONTENT" ] && exit 0

# Match `XCUIApplication ( bundleIdentifier` allowing whitespace
# variants but not the legitimate no-arg `XCUIApplication()`.
# `grep -E` is POSIX (avoids GNU-only `-P`).
if printf '%s' "$CONTENT" | grep -qE 'XCUIApplication[[:space:]]*\([[:space:]]*bundleIdentifier'; then
    cat >&2 <<EOF
CC-23 violation in $FILE:

A Swift test instantiates \`XCUIApplication(bundleIdentifier: ...)\`
to query a foreign process. This is the failure-mode codified in
\`.claude/rules/test-quality-rules.md\` §CC-23:

  (1) system modal covers in-app sentinels — predicates time out
      even when the bridge fired correctly;
  (2) bundle ids and chrome labels drift across OS versions — a
      test green on iOS 17 silently regresses on iOS 26.

Test the state that drives the presentation at the unit layer:
  - the engine emits the matching ExchangeCommand on the matching
    action — covered by tests/it/*_wiring_tests.rs in core
  - the bridge flips its @Published flag — covered by
    VauchiTests/CoreUI/ExchangeCommandBridgeTests.swift
  - SwiftUI presents the modal once the state flips — that's the
    OS's responsibility, not our test's.

Reference: ios!401 pivot, 2026-05-04. If this is a test of a
non-system foreign process (rare, but legitimate), re-format the
construct so this regex misses it AND add a comment explaining
why CC-23 does not apply.
EOF
    exit 2
fi

exit 0
