#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run cargo check after editing Rust files to catch compilation errors early.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only run cargo check for .rs files
if [[ "$FILE_PATH" =~ \.rs$ ]]; then
  # Determine the workspace root by walking up from the file
  DIR=$(dirname "$FILE_PATH")
  while [[ "$DIR" != "/" ]]; do
    if [[ -f "$DIR/Cargo.toml" ]]; then
      cargo check --quiet --manifest-path "$DIR/Cargo.toml" 2>&1 | head -20
      break
    fi
    DIR=$(dirname "$DIR")
  done
fi

exit 0
