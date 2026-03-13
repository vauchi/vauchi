#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Validate Cargo.toml branch refs point to main after edits.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check Cargo.toml files
if [[ "$FILE_PATH" =~ Cargo\.toml$ ]]; then
  BAD_REFS=$(grep -n 'branch = ' "$FILE_PATH" 2>/dev/null | grep -v 'main' || true)
  if [[ -n "$BAD_REFS" ]]; then
    echo "WARNING: Non-main branch refs found in $FILE_PATH:"
    echo "$BAD_REFS"
    echo ""
    echo "Cargo.toml branch refs must point to 'main' unless explicitly told otherwise."
    exit 2
  fi
fi

exit 0
