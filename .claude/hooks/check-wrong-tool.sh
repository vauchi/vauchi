#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse Bash hook: blocks standalone shell commands that have a
# native tool equivalent (Read / Grep / Glob). Composed commands
# (pipelines, redirects, &&/||/;) are allowed — they're legitimate
# shell, not "use shell instead of the tool".
#
# Rationale: audit S1-3 deep evidence (2026-05-18) — 1189 wrong-tool
# events (8% of all hook events). The existing log-bash-errors.sh is
# observational only; this hook turns it into a deterministic block.
#
# Patterns blocked (anchored, no pipe/redirect/composition):
#   cat <file>            → Read
#   head [-n N] <file>    → Read with limit
#   tail [-n N] <file>    → Read with offset + limit
#   find <path> -name X   → Glob
#   grep -r/-R <pat> <p>  → Grep
#
# Companion: open problem record
# `_private/docs/problems/2026-04-20-excessive-reedit-reread-pattern/`
# (the "Option B" from the 2026-05-18 plan).
#
# Escape: ALLOW_RAW_BASH=1 for edge cases (e.g. debugging a tool
# regression).

set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[[ -z "$COMMAND" ]] && exit 0

# Escape hatch.
if [[ "${ALLOW_RAW_BASH:-0}" == "1" ]]; then
  exit 0
fi

# Composed shell — allow. Detects pipe, redirect, conditional,
# sequential, and command substitution. -exec / xargs cases are also
# composition.
if printf '%s' "$COMMAND" | grep -qE '[|;><`$()&]|--exec|xargs'; then
  exit 0
fi

# Trim leading whitespace for tidy matching.
TRIMMED=$(printf '%s' "$COMMAND" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

block() {
  local cmd_name="$1" alt="$2" example="$3"
  cat >&2 <<EOF
Blocked: \`$cmd_name\` dumps file content via shell — use $alt instead.

$alt is line-numbered, integrates with the file-state tracker, and
counts against the read/edit caps that prevent excessive re-access.

Example: $example

Override: set ALLOW_RAW_BASH=1 if the bash form is genuinely needed
(e.g. debugging a tool regression). Pipelines and composed commands
(\`cat foo | jq\`, \`find … -exec …\`) are not blocked.
EOF
  exit 2
}

case "$TRIMMED" in
  cat\ *|cat)
    block "cat <file>" "Read" 'Read(file_path="path/to/file")'
    ;;
  head\ *|head)
    block "head <file>" "Read with offset+limit" 'Read(file_path="path/to/file", offset=1, limit=10)'
    ;;
  tail\ *|tail)
    block "tail <file>" "Read with offset" 'Read(file_path="path/to/file", offset=<last_line_minus_10>)'
    ;;
  find\ *)
    # Block ONLY if the command is exactly a name-pattern search with
    # no other action or filter verb. `find -name X -delete/-newer/
    # -mtime/-prune/-type/-maxdepth/...` are NOT Glob equivalents —
    # Glob can't delete, filter by age, prune, etc.
    OTHER_VERBS='-delete|-newer|-mtime|-atime|-ctime|-size|-prune|-depth|-maxdepth|-mindepth|-type|-perm|-user|-group|-empty|-path|-ipath|-regex|-print|-printf|-print0|-quit|-fprintf|-fprint|-ls|-fls'
    if printf '%s' "$TRIMMED" | grep -qE -- '-name|-iname'; then
      if ! printf '%s' "$TRIMMED" | grep -qE -- "$OTHER_VERBS"; then
        block "find … -name <pat>" "Glob" 'Glob(pattern="**/*.rs")'
      fi
    fi
    ;;
  "grep -r "*|"grep -R "*|"grep --recursive "*|"grep -rn "*|"grep -Rn "*)
    block "grep -r <pat>" "Grep" 'Grep(pattern="symbol", output_mode="files_with_matches")'
    ;;
esac

exit 0
