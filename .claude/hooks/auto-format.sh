#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Auto-format files after Write/Edit to prevent formatting CI failures.
# Runs the appropriate formatter based on file extension.
# Only outputs a message when the file was actually changed.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# Find a Node tool binary by walking up from the file to the nearest node_modules/.bin.
# Falls back to a global install.
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
  *.css|*.scss)
    # Skip node_modules and build artifacts
    [[ "$FILE_PATH" == */node_modules/* || "$FILE_PATH" == */dist/* || "$FILE_PATH" == */target/* ]] && exit 0
    PRETTIER=$(find_node_bin prettier "$(dirname "$FILE_PATH")")
    if [[ -n "$PRETTIER" ]]; then
      if ! "$PRETTIER" --check "$FILE_PATH" &>/dev/null; then
        "$PRETTIER" --write "$FILE_PATH" 2>/dev/null
        echo "Auto-formatted $FILE_PATH with prettier. Re-read before editing again."
      fi
    fi
    ;;
  *.html|*.htm)
    # Skip node_modules and build artifacts
    [[ "$FILE_PATH" == */node_modules/* || "$FILE_PATH" == */dist/* || "$FILE_PATH" == */target/* ]] && exit 0
    PRETTIER=$(find_node_bin prettier "$(dirname "$FILE_PATH")")
    if [[ -n "$PRETTIER" ]]; then
      if ! "$PRETTIER" --check "$FILE_PATH" &>/dev/null; then
        "$PRETTIER" --write "$FILE_PATH" 2>/dev/null
        echo "Auto-formatted $FILE_PATH with prettier. Re-read before editing again."
      fi
    fi
    ;;
esac

exit 0
