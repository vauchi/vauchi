#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run htmlhint after editing HTML files to catch lint issues early.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0
[[ "$FILE_PATH" =~ \.(html|htm)$ ]] || exit 0

# Skip node_modules and build artifacts
[[ "$FILE_PATH" == */node_modules/* || "$FILE_PATH" == */dist/* || "$FILE_PATH" == */target/* ]] && exit 0

# Find htmlhint by walking up from the file to the nearest node_modules/.bin.
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

HTMLHINT=$(find_node_bin htmlhint "$(dirname "$FILE_PATH")")
[[ -z "$HTMLHINT" ]] && exit 0

OUTPUT=$("$HTMLHINT" "$FILE_PATH" 2>&1)
STATUS=$?

if [[ $STATUS -ne 0 ]]; then
  echo "htmlhint issues in $FILE_PATH:"
  echo "$OUTPUT" | head -20
  exit 2
fi

exit 0
