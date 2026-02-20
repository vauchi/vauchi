#!/bin/bash
# Auto-format files after Write/Edit to prevent formatting CI failures.
# Runs the appropriate formatter based on file extension.
# Only outputs a message when the file was actually changed.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

case "$FILE_PATH" in
  *.rs)
    if command -v rustfmt &>/dev/null; then
      if ! rustfmt --edition 2021 --check "$FILE_PATH" &>/dev/null; then
        rustfmt --edition 2021 "$FILE_PATH" 2>/dev/null
        echo "Auto-formatted $FILE_PATH with rustfmt. Re-read before editing again."
      fi
    fi
    ;;
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
esac

exit 0
