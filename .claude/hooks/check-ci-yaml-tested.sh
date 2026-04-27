#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse hook: when a `git push` carries CI yaml changes, require an
# explicit acknowledgement that the changed command(s) were run locally
# with the actual flag set.
#
# Mechanism (soft):
#   - Block `git push` if the diff range against upstream contains a CI
#     yaml file (.gitlab-ci.yml, ci/*.yml, .github/workflows/*.yml).
#   - Bypass if the command line carries an inline assignment matching
#     ^|<space>CLAUDE_CI_TESTED= — Claude must add it consciously and
#     state which value applies (=1, =skip:<reason>).
#
# This is soft, not hard, because:
#   - Many CI commands need self-hosted runners, secrets, sibling clones,
#     or platform-specific tools we don't have locally.
#   - Auto-executing the changed command on every push is too expensive
#     and too surprising (could clobber target/, take 30+ minutes, etc.).
#   - The point is to force Claude to engage with the question "did I
#     actually run this?" rather than answer it implicitly.
#
# Why this hook exists:
#   2026-04-27 mutation:nightly fix shipped with --help/--list "verification"
#   only — missed cargo-mutants 26.x rejecting --in-place + --jobs together.
#   Two scheduled runs failed on argument parsing in ~10–22s before the gap
#   was caught. The user's correction: "this means you have not tested the
#   script locally before push." This hook makes that correction structural.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')

# Only intercept git push.
if ! echo "$COMMAND" | grep -qE '\bgit\s+(-C\s+\S+\s+)?push\b'; then
  exit 0
fi

# Skip branch/tag deletions and tag pushes — no code state changes.
if echo "$COMMAND" | grep -qF -- '--delete'; then
  exit 0
fi
if echo "$COMMAND" | grep -qF -- '--tags'; then
  exit 0
fi
# Skip dry-run pushes.
if echo "$COMMAND" | grep -qE -- '--dry-run\b'; then
  exit 0
fi

# Honor explicit ack via inline env-var assignment in the command string.
# Forms accepted:
#   CLAUDE_CI_TESTED=1 git push
#   CLAUDE_CI_TESTED=skip:doc-only git push
#   CLAUDE_CI_TESTED=skip:requires-runner git push
# Matches start-of-string or whitespace-prefixed assignment, so it can't
# be smuggled in via a substring of an argument value.
if echo "$COMMAND" | grep -qE '(^|[[:space:]])CLAUDE_CI_TESTED='; then
  exit 0
fi

# Resolve repo dir (same logic as gate-push.sh).
REPO_DIR="$CWD"
REL_DIR=$(echo "$COMMAND" | sed -n 's/.*git[[:space:]][[:space:]]*-C[[:space:]][[:space:]]*\([^[:space:]][^[:space:]]*\).*/\1/p')
if [[ -n "$REL_DIR" ]]; then
  if [[ "$REL_DIR" = /* ]]; then
    REPO_DIR="$REL_DIR"
  else
    REPO_DIR="$CWD/$REL_DIR"
  fi
fi
REPO_DIR=$(cd "$REPO_DIR" 2>/dev/null && pwd) || exit 0
REPO_NAME=$(basename "$REPO_DIR")

# Determine diff range (upstream → fallback to origin/main).
UPSTREAM=$(git -C "$REPO_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
if [[ -n "$UPSTREAM" ]]; then
  DIFF_RANGE="$UPSTREAM..HEAD"
else
  DIFF_RANGE="origin/main..HEAD"
fi

# Find changed CI yaml files in the diff range.
CI_FILES=$(git -C "$REPO_DIR" diff --name-only "$DIFF_RANGE" 2>/dev/null \
  | grep -E '(^|/)\.gitlab-ci\.yml$|(^|/)ci/[^/]+\.ya?ml$|(^|/)\.github/workflows/[^/]+\.ya?ml$' \
  || true)

if [[ -z "$CI_FILES" ]]; then
  exit 0
fi

# Detect known-bad flag combinations as an extra signal in the message.
HARD_HINTS=""
for f in $CI_FILES; do
  abs="$REPO_DIR/$f"
  [[ -f "$abs" ]] || continue
  # cargo-mutants 26: --in-place + --jobs are mutually exclusive.
  if grep -qE '\-\-in-place' "$abs" 2>/dev/null && grep -qE '\-\-jobs' "$abs" 2>/dev/null; then
    HARD_HINTS="${HARD_HINTS}\n  - $f mentions both --in-place and --jobs (cargo-mutants 26 rejects this combo)"
  fi
  # GitLab variable values containing $(...) — recursive expansion does not happen.
  if grep -qE '^[[:space:]]+[A-Z_]+:[[:space:]]+"[^"]*\$\([^)]+\)[^"]*"' "$abs" 2>/dev/null; then
    HARD_HINTS="${HARD_HINTS}\n  - $f has a GitLab variable value containing \$(...) — bash will not recursively evaluate it"
  fi
done

# Block with a self-contained explanation.
echo "" >&2
echo "Push blocked: CI yaml changes — confirm local verification." >&2
echo "" >&2
echo "Changed CI files in $REPO_NAME ($DIFF_RANGE):" >&2
while IFS= read -r f; do
  [[ -n "$f" ]] && echo "  - $f" >&2
done <<< "$CI_FILES"

if [[ -n "$HARD_HINTS" ]]; then
  echo "" >&2
  echo "Static-lint hints:" >&2
  printf '%b\n' "$HARD_HINTS" >&2
fi

cat >&2 <<'MSG'

Why this hook exists:
  CI yaml changes are shipped without iteration — the next scheduled or
  triggered pipeline is the first time the script actually runs. On
  2026-04-27 a mutation:nightly fix landed with --help/--list "verification"
  only and was rejected by cargo-mutants 26.x on the first scheduled run
  because --in-place and --jobs are mutually exclusive. --help and --list
  don't catch flag-conflicts.

Before pushing, run the actual command(s) the changed job will execute,
with the same flags, for at least one real iteration. For long-running
commands, Ctrl-C after the argument-parsing / startup phase is fine —
flag-conflict errors surface within seconds.

Then re-push with one of these inline assignments:
  CLAUDE_CI_TESTED=1 git push                       # ran the command, output OK
  CLAUDE_CI_TESTED=skip:doc-only git push           # comment- or doc-only change
  CLAUDE_CI_TESTED=skip:requires-runner git push    # CI-only env (secrets, self-hosted)
  CLAUDE_CI_TESTED=skip:platform-mismatch git push  # changed job runs on a different OS

Pick the most specific reason. The value is logged in the hook telemetry
and shows the user what you decided. "skip:other" is allowed but discouraged.

Reference: feedback_local_verification_real_flags.md in auto-memory.
MSG

exit 2
