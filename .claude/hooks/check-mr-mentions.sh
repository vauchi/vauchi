#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse hook: blocks glab/gh MR/PR create/update commands whose
# description body contains an unescaped `@tag`.
#
# Why: GitLab and GitHub interpret bare `@username` as a user mention
# and email-notify the matching account (or break if the handle does
# not exist). Gherkin tags, ADR refs, and other `@word` markers must
# be wrapped in backticks (`` `@duress` ``) to render as code rather
# than mentions.
#
# Rule: `.claude/rules/multi-repo-awareness.md` — "No `@` in MR
# descriptions: Wrap Gherkin tags in backticks".

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Match only commands that create or update an MR/PR. The body is
# carried as `--description` / `--body` / `-d` / `-b`. Anything else
# is out of scope (e.g. `glab mr list`, `gh pr view`).
if ! echo "$COMMAND" | grep -qE '\b(glab[^|]*mr[[:space:]]+(create|update|edit)|gh[[:space:]]+pr[[:space:]]+(create|edit))\b' \
   && ! echo "$COMMAND" | grep -qE '\bjust[[:space:]]+gitlab[[:space:]]+mr-(create|update)\b'; then
  exit 0
fi

# Strip code spans (`...`) so legitimately-escaped tags don't trigger.
# Also strip emails (foo@bar.tld) — they aren't mentions.
# Then look for a bare @word (alphanumeric tag, no dot, not in backticks).
STRIPPED=$(printf '%s\n' "$COMMAND" \
  | sed -E 's/`[^`]*`//g'                         `# strip inline code spans` \
  | sed -E 's/[A-Za-z0-9_.+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}//g'  `# strip emails`)

# Find @word (must start with a letter, no '.' anywhere — '.' would
# look more like an email/URL fragment than a Gherkin/user tag).
MATCH=$(printf '%s\n' "$STRIPPED" | grep -oE '@[A-Za-z][A-Za-z0-9_-]*' | head -5)

if [ -n "$MATCH" ]; then
  cat >&2 <<EOF
[check-mr-mentions]: MR/PR description contains an unescaped \`@tag\`:
$(printf '  %s\n' $MATCH)

GitLab and GitHub treat \`@word\` as a user mention. Wrap every Gherkin
tag, ADR reference, or other \`@\` marker in backticks before pushing.

Examples:
  WRONG: "promotes @implemented scenarios"
  RIGHT: "promotes \`@implemented\` scenarios"

Re-edit the heredoc body and retry. The rule is
\`.claude/rules/multi-repo-awareness.md\` — "No \`@\` in MR descriptions".
EOF
  log="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-errors"
  printf '{"ts":"%s","hook":"check-mr-mentions","matches":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(printf '%s' "$MATCH" | tr '\n' ' ')" \
    >> "$log" 2>/dev/null
  exit 2
fi

exit 0
