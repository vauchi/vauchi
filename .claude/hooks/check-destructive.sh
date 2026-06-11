#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse hook: blocks accidentally destructive Bash commands.
#
# This is an ACCIDENT guard, not an adversary defense. Obfuscated
# bypasses (bash -c, interpreters, encodings) are out of scope —
# accidents are not obfuscated, and the arms race against deliberate
# bypass is unwinnable at the grep layer. Deliberate destructive
# commands belong to the user via the `!` prefix.
#
# Accepted gap: variable targets (rm -rf "$TMP/x") are allowed because
# mktemp cleanup is the dominant legitimate pattern. $HOME and ~ are
# the exception — always blocked with recursive rm.
#
# Rules:
# 1. Any path reference to secret dirs (~/.ssh, ~/.gnupg, ~/.aws,
#    .config/gh, .config/glab-cli) → blocked.
# 2. Recursive rm (-r/-R in any flag form) targeting ~, $HOME, a bare
#    *, . or .., or an absolute path outside /tmp-like dirs → blocked.
# 3. find rooted at ~ or an absolute non-/tmp path with -delete or
#    -exec rm → blocked (relative roots like `find .` stay allowed).
# 4. xargs rm with -r/-R/-f flags → blocked.
# 5. git clean with -f/-d/-x or --force → blocked unless dry-run (-n).
#
# shellcheck disable=SC2016  # literal $HOME in regexes is intentional:
# the hook matches the UNEXPANDED command string Claude wrote.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$COMMAND" ]] && exit 0

# Skip git commit/tag commands (message body may mention blocked patterns)
if echo "$COMMAND" | grep -qE '(^|[[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(commit|tag)([[:space:]]|$)'; then
  exit 0
fi

log_error() {
  local category="$1" reason="$2"
  local log="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-errors"
  printf '{"ts":"%s","hook":"check-destructive","category":"%s","command":"%s","reason":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$category" "$(echo "$COMMAND" | head -c 200)" "$reason" >> "$log" 2>/dev/null
}

block() {
  local reason="$1"
  echo "[$CLAUDE_PROJECT_DIR/.claude/hooks/check-destructive.sh]: $reason" >&2
  cat >&2
  log_error "destructive" "$reason"
  exit 2
}

# ── Rule 1: secret-directory references ───────────────────────────
SECRET_RE='(~|\$HOME|/home/[^/[:space:]]+|/Users/[^/[:space:]]+)/\.(ssh|gnupg|aws)([^[:alnum:]]|$)|\.config/(gh|glab-cli)/'
if echo "$COMMAND" | grep -qE "$SECRET_RE"; then
  block "command references a secret directory" <<'EOF'
Bash access to ~/.ssh, ~/.gnupg, ~/.aws, ~/.config/gh, ~/.config/glab-cli
is blocked for the agent. If this is intentional, run it yourself with
the `!` prefix in the prompt.
EOF
fi

# Temp-dir prefixes that recursive deletes may target freely.
TMP_OK_RE='^/(tmp|private/tmp|var/folders)(/|$)'

# Split compound commands into segments on && || ; |
NORM=${COMMAND//'&&'/$'\n'}
NORM=${NORM//'||'/$'\n'}
NORM=$(printf '%s\n' "$NORM" | tr ';|' '\n')

while IFS= read -r seg; do
  # ── Rule 2: recursive rm on dangerous targets ──────────────────
  if printf '%s' "$seg" | grep -qE '^[[:space:]]*(sudo[[:space:]]+)?rm([[:space:]]|$)'; then
    if printf '%s' "$seg" | grep -qE '(^|[[:space:]])-[a-zA-Z]*[rR]'; then
      if printf '%s' "$seg" | grep -qE '(^|[[:space:]])["'\'']?(~|\$HOME)(/|["'\''[:space:]]|$)'; then
        block "recursive rm targeting home" <<'EOF'
Recursive rm targeting ~ or $HOME is blocked. Use an explicit
project-relative or /tmp path, or run it yourself with `!`.
EOF
      fi
      if printf '%s' "$seg" | grep -qE '[[:space:]](\*|\.|\.\.(/[^[:space:]]*)?)([[:space:]]|$)'; then
        block "recursive rm on bare glob/dot target" <<'EOF'
Recursive rm on `*`, `.` or a `../` path is blocked — in the wrong cwd
this deletes the workspace. Name the directory explicitly.
EOF
      fi
      # Absolute targets: every one must be under a temp prefix.
      while IFS= read -r tok; do
        [[ -z "$tok" ]] && continue
        tok=$(printf '%s' "$tok" | sed "s/^[[:space:]]*[\"']\{0,1\}//")
        if ! printf '%s' "$tok" | grep -qE "$TMP_OK_RE"; then
          block "recursive rm on absolute path outside /tmp" <<'EOF'
Recursive rm on an absolute path outside /tmp is blocked. Use a
project-relative path, move it to /tmp first, or run yourself with `!`.
EOF
        fi
      done < <(printf '%s' "$seg" | grep -oE '[[:space:]]["'\'']?/[^"'\''[:space:]]*' || true)
    fi
  fi

  # ── Rule 3: find -delete / -exec rm with dangerous root ─────────
  if printf '%s' "$seg" | grep -qE '^[[:space:]]*(sudo[[:space:]]+)?find[[:space:]]' \
     && printf '%s' "$seg" | grep -qE -- '-delete([[:space:]]|$)|-exec[[:space:]]+rm([[:space:]]|$)'; then
    root=$(printf '%s' "$seg" | awk '{print $2}' | sed "s/^[\"']//")
    # shellcheck disable=SC2088  # literal ~ match on the unexpanded string
    case "$root" in
      "~"|"~/"*|'$HOME'*) dangerous=1 ;;
      /*) if printf '%s' "$root" | grep -qE "$TMP_OK_RE"; then dangerous=0; else dangerous=1; fi ;;
      *) dangerous=0 ;;
    esac
    if [[ "$dangerous" == "1" ]]; then
      block "find -delete/-exec rm rooted outside /tmp" <<'EOF'
find with -delete or -exec rm rooted at ~ or an absolute path outside
/tmp is blocked. Root the search at a relative or /tmp path.
EOF
    fi
  fi

  # ── Rule 5: git clean force ──────────────────────────────────────
  if printf '%s' "$seg" | grep -qE '(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+clean([[:space:]]|$)'; then
    if printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*f[a-zA-Z]*|--force)([[:space:]]|$)' \
       && ! printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*n[a-zA-Z]*|--dry-run)([[:space:]]|$)'; then
      block "git clean --force" <<'EOF'
git clean -f deletes untracked files irreversibly — WIP, local configs,
path-override fences. Use `just git wip` to save work, `git clean -n`
to preview, or delete named paths explicitly.
EOF
    fi
  fi
done <<< "$NORM"

# ── Rule 4: xargs rm with recursive/force flags ────────────────────
if echo "$COMMAND" | grep -qE 'xargs([[:space:]]+-[^[:space:]]+)*[[:space:]]+rm[[:space:]]+-[a-zA-Z]*[rRf]'; then
  block "xargs rm with -r/-f" <<'EOF'
xargs rm with recursive/force flags is blocked — a bad upstream list
deletes silently. Use find under a named root with -delete, or review
the list first.
EOF
fi

exit 0
