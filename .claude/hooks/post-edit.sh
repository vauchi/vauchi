#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Unified PostToolUse hook for Edit/Write operations.
# Consolidates: auto-format, check-cargo-toml, check-test-assertions,
#               check-css, check-html (and removes check-rust / cargo check).
# Single process spawn, single jq parse per edit.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Log blocked actions for session-end error analysis
log_error() {
  local category="$1" file="$2" reason="$3"
  local log="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-errors"
  printf '{"ts":"%s","hook":"post-edit","category":"%s","file":"%s","reason":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$category" "$file" "$reason" >> "$log" 2>/dev/null
}

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Skip build artifacts and deps
[[ "$FILE_PATH" == */node_modules/* || "$FILE_PATH" == */dist/* || "$FILE_PATH" == */target/* ]] && exit 0

# ── Edit/Write frequency tracking ───────────────────────────────────
# Excessive re-edits (same file 4+ edits) signal Claude got it wrong.
# Tracks Edit calls per file per session. 1-2 = normal, 3 = re-edit, 4+ = churn.
if [[ "$TOOL_NAME" == "Edit" ]]; then
  TRACKER="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-edits"
  echo "$FILE_PATH" >> "$TRACKER" 2>/dev/null
  EDIT_COUNT=$(grep -cF "$FILE_PATH" "$TRACKER" 2>/dev/null || echo "1")
  if [[ "$EDIT_COUNT" -eq 3 ]]; then
    # Soft nudge before crossing the threshold — visible to Claude, non-blocking.
    echo "Note: 3rd Edit to $FILE_PATH this session. If more changes are coming, consider Write or batching them in fewer Edit calls." >&2
  elif [[ "$EDIT_COUNT" -ge 4 ]]; then
    log_error "excessive-reedit" "$FILE_PATH" "edited $EDIT_COUNT times this session"
  fi
fi

# ── SPDX header auto-add (on Write, for new files) ──────────────────
# Eliminates the #1 recurring license fix category (35+ fix commits).
# Only runs on Write (new file creation), not Edit (modifications).
# Skips paths covered by REUSE.toml annotations (frontmatter files, binary, generated).
if [[ "$TOOL_NAME" == "Write" ]] && ! head -5 "$FILE_PATH" | grep -q 'SPDX-'; then
  # Skip paths where REUSE.toml annotations handle licensing:
  # - .claude/rules|agents|docs|skills|agent-memory: YAML frontmatter must be first line
  # - supply-chain: cargo-vet strips headers on regeneration
  # - LICENSES: license files themselves
  # - gradlew*: third-party (Apache-2.0)
  SKIP_SPDX=false
  case "$FILE_PATH" in
    */.claude/*) SKIP_SPDX=true ;;  # all .claude/ dirs: rules, agents, docs, skills, memory (YAML frontmatter)
    */supply-chain/*|*/LICENSES/*) SKIP_SPDX=true ;;
    */gradlew|*/gradlew.bat) SKIP_SPDX=true ;;
    *.snap|*.lock|*.plist|*.pbxproj|*.xcworkspacedata) SKIP_SPDX=true ;;
  esac

  if [[ "$SKIP_SPDX" == "false" ]]; then
    # REUSE-IgnoreStart
    SPDX_COPY="SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>"
    SPDX_LIC="SPDX-License-Identifier: GPL-3.0-or-later"
    # REUSE-IgnoreEnd
    HEADER=""
    case "$FILE_PATH" in
      *.rs|*.swift|*.kt|*.ts|*.js|*.tsx|*.jsx)
        HEADER="// ${SPDX_COPY}\n//\n// ${SPDX_LIC}\n" ;;
      *.sh|*.bash|*.py|*.toml|*.yml|*.yaml|*.feature|*.cfg)
        # Preserve shebang if present
        if head -1 "$FILE_PATH" | grep -q '^#!'; then
          SHEBANG=$(head -1 "$FILE_PATH")
          TAIL=$(tail -n +2 "$FILE_PATH")
          printf '%s\n# %s\n#\n# %s\n%s' "$SHEBANG" "$SPDX_COPY" "$SPDX_LIC" "$TAIL" > "$FILE_PATH"
          echo "Auto-added SPDX header to $FILE_PATH (after shebang). Re-read before editing again."
          HEADER=""  # already written
        else
          HEADER="# ${SPDX_COPY}\n#\n# ${SPDX_LIC}\n"
        fi
        ;;
      *.md|*.html|*.htm)
        HEADER="<!-- ${SPDX_COPY} -->\n<!-- ${SPDX_LIC} -->\n" ;;
      *.css|*.scss)
        HEADER="/* ${SPDX_COPY} */\n/* ${SPDX_LIC} */\n" ;;
    esac
    if [[ -n "$HEADER" ]]; then
      CONTENT=$(cat "$FILE_PATH")
      printf '%b\n%s' "$HEADER" "$CONTENT" > "$FILE_PATH"
      echo "Auto-added SPDX header to $FILE_PATH. Re-read before editing again."
    fi
  fi
fi

# ── Helpers ─────────────────────────────────────────────────────────

find_node_bin() {
  local tool="$1" dir="$2"
  while [[ "$dir" != "/" ]]; do
    if [[ -x "$dir/node_modules/.bin/$tool" ]]; then
      echo "$dir/node_modules/.bin/$tool"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  if command -v "$tool" &>/dev/null; then
    command -v "$tool"
    return 0
  fi
  return 1
}

check_test_assertions() {
  local file="$1"
  # Only check files that contain #[test]
  grep -q '#\[test\]' "$file" 2>/dev/null || return 0

  # Single awk pass: reads file once, finds all #[test] fns, checks for assertions.
  # Old version spawned sed per-line-per-test (O(tests*lines) subprocesses).
  # Strategy: for each #[test] fn, scan up to 200 lines (or next #[test]) for assertions.
  # Also recognizes assert helper calls (assert_*(...)) and // allow(zero_assertions).
  local output
  output=$(awk '
    /^[[:space:]]*#\[test\]/ {
      # Report previous test if it had no assertions
      if (scanning && !has_assert) {
        print saved_name " (line " saved_line ")"
      }
      test_line = NR
      should_panic = 0
      scanning = 0; has_assert = 0
      next
    }
    test_line > 0 && !scanning {
      if (/#\[should_panic/) { should_panic = 1 }
      if (/^[[:space:]]*(pub[[:space:]]+)?(async[[:space:]]+)?fn[[:space:]]+/) {
        fn_name = $0
        sub(/.*fn[[:space:]]+/, "", fn_name)
        sub(/[^a-zA-Z0-9_].*/, "", fn_name)
        if (should_panic) { test_line = 0; next }
        saved_name = fn_name; saved_line = NR
        scanning = 1; has_assert = 0; scan_limit = NR + 200
      }
      if (NR > test_line + 5) { test_line = 0 }
      next
    }
    scanning {
      if (NR > scan_limit) {
        if (!has_assert) { print saved_name " (line " saved_line ")" }
        scanning = 0; test_line = 0; next
      }
      if ($0 ~ /allow\(zero_assertions\)/) { has_assert = 1 }
      if ($0 ~ /assert(_eq|_ne)?!/ || \
          $0 ~ /assert_(snapshot|debug_snapshot|compact_snapshot|json_snapshot|yaml_snapshot|toml_snapshot|csv_snapshot|compact_json_snapshot|redaction_snapshot)!/ || \
          $0 ~ /snap!/ || \
          $0 ~ /prop_assert(_eq|_ne)?!/ || \
          $0 ~ /\.expect\(/ || \
          $0 ~ /\.expect_err\(/ || \
          $0 ~ /#\[should_panic\]/ || \
          $0 ~ /assert_[a-z_]+\(/) {
        has_assert = 1
      }
    }
    END {
      if (scanning && !has_assert) {
        print saved_name " (line " saved_line ")"
      }
    }
  ' "$file")

  if [[ -n "$output" ]]; then
    echo "WARNING: Zero-assertion test(s) detected in $file:"
    while IFS= read -r v; do
      echo "  - $v"
    done <<< "$output"
    echo ""
    echo "Every #[test] must have at least one assert*!, .expect(), or #[should_panic]."
    echo "See CC-03 and CC-17 in CLAUDE.md."
    log_error "zero-assertion" "$file" "$output"
    return 2
  fi
}

# ── Dispatch by file type ───────────────────────────────────────────

case "$FILE_PATH" in

  # ── Rust ──────────────────────────────────────────────────────────
  *.rs)
    # Auto-format
    if command -v rustfmt &>/dev/null; then
      if ! rustfmt --edition 2024 --check "$FILE_PATH" &>/dev/null; then
        rustfmt --edition 2024 "$FILE_PATH" 2>/dev/null
        echo "Auto-formatted $FILE_PATH with rustfmt. Re-read before editing again."
      fi
    fi
    # Test assertion check
    check_test_assertions "$FILE_PATH" || exit $?
    ;;

  # ── Swift ─────────────────────────────────────────────────────────
  *.swift)
    if command -v swiftformat &>/dev/null; then
      BEFORE=$(shasum -a 256 "$FILE_PATH" 2>/dev/null)
      swiftformat "$FILE_PATH" 2>/dev/null
      AFTER=$(shasum -a 256 "$FILE_PATH" 2>/dev/null)
      if [[ "$BEFORE" != "$AFTER" ]]; then
        echo "Auto-formatted $FILE_PATH with swiftformat. Re-read before editing again."
      fi
    fi
    ;;

  # ── Kotlin ────────────────────────────────────────────────────────
  *.kt)
    if command -v ktlint &>/dev/null; then
      BEFORE=$(shasum -a 256 "$FILE_PATH" 2>/dev/null)
      ktlint -F "$FILE_PATH" 2>/dev/null || true
      AFTER=$(shasum -a 256 "$FILE_PATH" 2>/dev/null)
      if [[ "$BEFORE" != "$AFTER" ]]; then
        echo "Auto-formatted $FILE_PATH with ktlint. Re-read before editing again."
      fi
    fi
    ;;

  # ── CSS / SCSS ────────────────────────────────────────────────────
  *.css|*.scss)
    # Auto-format with prettier
    PRETTIER=$(find_node_bin prettier "$(dirname "$FILE_PATH")")
    if [[ -n "$PRETTIER" ]]; then
      if ! "$PRETTIER" --check "$FILE_PATH" &>/dev/null; then
        "$PRETTIER" --write "$FILE_PATH" 2>/dev/null
        echo "Auto-formatted $FILE_PATH with prettier. Re-read before editing again."
      fi
    fi
    # Lint with stylelint
    STYLELINT=$(find_node_bin stylelint "$(dirname "$FILE_PATH")")
    if [[ -n "$STYLELINT" ]]; then
      OUTPUT=$("$STYLELINT" "$FILE_PATH" 2>&1)
      if [[ $? -ne 0 ]]; then
        echo "stylelint issues in $FILE_PATH:"
        echo "$OUTPUT" | head -20
        log_error "stylelint" "$FILE_PATH" "lint issues"
        exit 2
      fi
    fi
    ;;

  # ── HTML ──────────────────────────────────────────────────────────
  *.html|*.htm)
    # Auto-format with prettier
    PRETTIER=$(find_node_bin prettier "$(dirname "$FILE_PATH")")
    if [[ -n "$PRETTIER" ]]; then
      if ! "$PRETTIER" --check "$FILE_PATH" &>/dev/null; then
        "$PRETTIER" --write "$FILE_PATH" 2>/dev/null
        echo "Auto-formatted $FILE_PATH with prettier. Re-read before editing again."
      fi
    fi
    # Lint with htmlhint
    HTMLHINT=$(find_node_bin htmlhint "$(dirname "$FILE_PATH")")
    if [[ -n "$HTMLHINT" ]]; then
      OUTPUT=$("$HTMLHINT" "$FILE_PATH" 2>&1)
      if [[ $? -ne 0 ]]; then
        echo "htmlhint issues in $FILE_PATH:"
        echo "$OUTPUT" | head -20
        log_error "htmlhint" "$FILE_PATH" "lint issues"
        exit 2
      fi
    fi
    ;;

  # ── Cargo.toml ────────────────────────────────────────────────────
  */Cargo.toml)
    BAD_REFS=$(grep -n 'branch = ' "$FILE_PATH" 2>/dev/null | grep -v 'main' || true)
    if [[ -n "$BAD_REFS" ]]; then
      echo "WARNING: Non-main branch refs found in $FILE_PATH:"
      echo "$BAD_REFS"
      echo ""
      echo "Cargo.toml branch refs must point to 'main' unless explicitly told otherwise."
      log_error "cargo-branch-ref" "$FILE_PATH" "non-main branch ref"
      exit 2
    fi
    ;;

esac

exit 0
