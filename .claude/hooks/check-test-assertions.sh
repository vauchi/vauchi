#!/bin/bash
# Check that every #[test] function contains at least one assertion.
# Catches zero-assertion tests that would be rejected by CI quality gates.
# Runs after Write/Edit on Rust test files.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Only check Rust files
[[ "$FILE_PATH" =~ \.rs$ ]] || exit 0

# Only check files that contain #[test]
grep -q '#\[test\]' "$FILE_PATH" 2>/dev/null || exit 0

# Extract test function names and check for assertions.
# Strategy: for each #[test], find the function body and check for assertion macros.
VIOLATIONS=()

# Get line numbers of #[test] attributes
TEST_LINES=$(grep -n '#\[test\]' "$FILE_PATH" | cut -d: -f1)

for test_line in $TEST_LINES; do
  # Find the fn line (next line starting with fn or pub fn, within 5 lines)
  FN_LINE=""
  FN_NAME=""
  for offset in 1 2 3 4 5; do
    CHECK_LINE=$((test_line + offset))
    LINE_CONTENT=$(sed -n "${CHECK_LINE}p" "$FILE_PATH")
    if echo "$LINE_CONTENT" | grep -qE '^\s*(pub\s+)?(async\s+)?fn\s+'; then
      FN_LINE=$CHECK_LINE
      FN_NAME=$(echo "$LINE_CONTENT" | grep -oP 'fn\s+\K\w+')
      break
    fi
  done

  [[ -z "$FN_LINE" ]] && continue

  # Check for #[should_panic] between #[test] and fn
  ATTRS=$(sed -n "${test_line},${FN_LINE}p" "$FILE_PATH")
  if echo "$ATTRS" | grep -q '#\[should_panic'; then
    continue
  fi

  # Find the opening brace and extract the function body
  # Count braces from FN_LINE to find the closing brace
  BRACE_COUNT=0
  STARTED=false
  BODY_START=$FN_LINE
  BODY_END=""

  TOTAL_LINES=$(wc -l < "$FILE_PATH")
  for ((i = FN_LINE; i <= TOTAL_LINES; i++)); do
    LINE=$(sed -n "${i}p" "$FILE_PATH")
    OPENS=$(echo "$LINE" | tr -cd '{' | wc -c)
    CLOSES=$(echo "$LINE" | tr -cd '}' | wc -c)
    BRACE_COUNT=$((BRACE_COUNT + OPENS - CLOSES))

    if [[ $OPENS -gt 0 && "$STARTED" != "true" ]]; then
      STARTED=true
      BODY_START=$i
    fi

    if [[ "$STARTED" == "true" && $BRACE_COUNT -le 0 ]]; then
      BODY_END=$i
      break
    fi
  done

  [[ -z "$BODY_END" ]] && continue

  # Extract body and check for assertion patterns
  BODY=$(sed -n "${BODY_START},${BODY_END}p" "$FILE_PATH")

  # Assertion patterns: assert!, assert_eq!, assert_ne!, prop_assert!, .expect(, #[should_panic]
  if ! echo "$BODY" | grep -qE 'assert(_eq|_ne)?!|prop_assert!|\.expect\(|\.unwrap\(|#\[should_panic\]'; then
    VIOLATIONS+=("$FN_NAME (line $FN_LINE)")
  fi
done

if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  echo "WARNING: Zero-assertion test(s) detected in $FILE_PATH:"
  for v in "${VIOLATIONS[@]}"; do
    echo "  - $v"
  done
  echo ""
  echo "Every #[test] must have at least one assert*!, .expect(), or #[should_panic]."
  echo "See CC-03 and CC-17 in CLAUDE.md."
  # Exit 2 to block — zero-assertion tests are rejected by CI
  exit 2
fi

exit 0
