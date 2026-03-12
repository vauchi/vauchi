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

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Skip build artifacts and deps
[[ "$FILE_PATH" == */node_modules/* || "$FILE_PATH" == */dist/* || "$FILE_PATH" == */target/* ]] && exit 0

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

  local violations=()
  local test_lines
  test_lines=$(grep -n '#\[test\]' "$file" | cut -d: -f1)
  local total_lines
  total_lines=$(wc -l < "$file")

  for test_line in $test_lines; do
    local fn_line="" fn_name=""
    for offset in 1 2 3 4 5; do
      local check_line=$((test_line + offset))
      local line_content
      line_content=$(sed -n "${check_line}p" "$file")
      if echo "$line_content" | grep -qE '^\s*(pub\s+)?(async\s+)?fn\s+'; then
        fn_line=$check_line
        fn_name=$(echo "$line_content" | sed -E 's/.*fn[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
        break
      fi
    done

    [[ -z "$fn_line" ]] && continue

    # Skip #[should_panic] tests
    local attrs
    attrs=$(sed -n "${test_line},${fn_line}p" "$file")
    echo "$attrs" | grep -q '#\[should_panic' && continue

    # Find function body via brace counting
    local brace_count=0 started=false body_start=$fn_line body_end=""
    for ((i = fn_line; i <= total_lines; i++)); do
      local line
      line=$(sed -n "${i}p" "$file")
      local opens closes
      opens=$(echo "$line" | tr -cd '{' | wc -c)
      closes=$(echo "$line" | tr -cd '}' | wc -c)
      brace_count=$((brace_count + opens - closes))

      if [[ $opens -gt 0 && "$started" != "true" ]]; then
        started=true
        body_start=$i
      fi

      if [[ "$started" == "true" && $brace_count -le 0 ]]; then
        body_end=$i
        break
      fi
    done

    [[ -z "$body_end" ]] && continue

    local body full_range_end full_range
    body=$(sed -n "${body_start},${body_end}p" "$file")
    full_range_end=$((fn_line + 200))
    [[ $full_range_end -gt $total_lines ]] && full_range_end=$total_lines
    full_range=$(sed -n "${fn_line},${full_range_end}p" "$file")

    local assertion_re='assert(_eq|_ne)?!|assert_(snapshot|debug_snapshot|compact_snapshot|json_snapshot|yaml_snapshot|toml_snapshot|csv_snapshot|compact_json_snapshot|redaction_snapshot)!|snap!|prop_assert(_eq|_ne)?!|\.expect\(|#\[should_panic\]'
    if ! echo "$body" | grep -qE "$assertion_re"; then
      if ! echo "$full_range" | grep -qE "$assertion_re"; then
        violations+=("$fn_name (line $fn_line)")
      fi
    fi
  done

  if [[ ${#violations[@]} -gt 0 ]]; then
    echo "WARNING: Zero-assertion test(s) detected in $file:"
    for v in "${violations[@]}"; do
      echo "  - $v"
    done
    echo ""
    echo "Every #[test] must have at least one assert*!, .expect(), or #[should_panic]."
    echo "See CC-03 and CC-17 in CLAUDE.md."
    return 2
  fi
}

# ── Dispatch by file type ───────────────────────────────────────────

case "$FILE_PATH" in

  # ── Rust ──────────────────────────────────────────────────────────
  *.rs)
    # Auto-format
    if command -v rustfmt &>/dev/null; then
      if ! rustfmt --edition 2021 --check "$FILE_PATH" &>/dev/null; then
        rustfmt --edition 2021 "$FILE_PATH" 2>/dev/null
        echo "Auto-formatted $FILE_PATH with rustfmt. Re-read before editing again."
      fi
    fi
    # Test assertion check
    check_test_assertions "$FILE_PATH" || exit $?
    ;;

  # ── Swift ─────────────────────────────────────────────────────────
  *.swift)
    if command -v swiftformat &>/dev/null; then
      BEFORE=$(md5sum "$FILE_PATH" 2>/dev/null)
      swiftformat "$FILE_PATH" 2>/dev/null
      AFTER=$(md5sum "$FILE_PATH" 2>/dev/null)
      if [[ "$BEFORE" != "$AFTER" ]]; then
        echo "Auto-formatted $FILE_PATH with swiftformat. Re-read before editing again."
      fi
    fi
    ;;

  # ── Kotlin ────────────────────────────────────────────────────────
  *.kt)
    if command -v ktlint &>/dev/null; then
      BEFORE=$(md5sum "$FILE_PATH" 2>/dev/null)
      ktlint -F "$FILE_PATH" 2>/dev/null || true
      AFTER=$(md5sum "$FILE_PATH" 2>/dev/null)
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
      exit 2
    fi
    ;;

esac

exit 0
