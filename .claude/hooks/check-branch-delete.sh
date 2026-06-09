#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PreToolUse Bash hook: guards `git branch -D` (force-delete) against
# losing commits that are not yet in origin/main.
#
# Why this exists — the project's most-recurrent *reasoning* error
# (4 incidents in .claude/docs/log_reasoning_errors.md):
#   - 2026-05-04 "Deleted local branch with unmerged MR-bound commit"
#   - 2026-05-04 "Trilogy MRs already landed via different SHAs"
#   - 2026-06-07 "Used `git diff A...B` to judge is-this-merged"
#   - and the squash-merge false-positive in `branch-health`.
# The common thread: deciding "this branch is safe to delete" from a
# reachability view (`git branch -d`, 3-dot diff, ahead/behind) that
# CANNOT see through a squash-merge.
#
# The fix is `git cherry origin/main <branch>` (patch-id):
#   `-` marker  → that commit's patch is already in main  → safe
#   `+` marker  → that commit is NOT in main              → would be lost
# So this hook BLOCKS a force-delete only when cherry proves a `+`
# (genuinely-unmerged work), and stays out of the way for squash-merged
# branches that plain `git branch -d` would wrongly refuse.
#
# Scope: only LOCAL force-deletes — `git branch -D`, or `branch` with a
# delete flag AND a force flag. Plain `git branch -d` is left to git's
# own (reachability) safety. Remote deletes (`git push --delete`) are
# ignored — they don't drop local history.
#
# Fail-open: if origin/main can't be resolved (not fetched) the hook
# cannot verify, so it emits an advisory and ALLOWS — a guard that
# can't prove danger must not block (Chesterton's-fence direction).

set -uo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

[[ -z "$COMMAND" ]] && exit 0

# Fast reject: must be a `git` invocation that mentions the `branch`
# subcommand. (push --delete, switch, etc. never reach the slow path.)
printf '%s' "$COMMAND" | grep -qE '\bgit\b' || exit 0
printf '%s' "$COMMAND" | grep -qE '\bbranch\b' || exit 0

read -ra TOKENS <<< "$COMMAND"

# Locate the `branch` subcommand and extract a `-C <dir>` target.
REPO_DIR=""
BIDX=-1
for ((i = 0; i < ${#TOKENS[@]}; i++)); do
    case "${TOKENS[i]}" in
        -C) REPO_DIR="${TOKENS[i + 1]:-}" ;;
        branch) [[ "$BIDX" -eq -1 ]] && BIDX=$i ;;
    esac
done
[[ "$BIDX" -eq -1 ]] && exit 0

# Force-delete detection: `-D`, or a delete flag together with a force flag.
HAS_DELETE=0
HAS_FORCE=0
IS_FORCE_DELETE=0
for t in "${TOKENS[@]}"; do
    case "$t" in
        -D) IS_FORCE_DELETE=1; HAS_DELETE=1 ;;
        -d | --delete) HAS_DELETE=1 ;;
        -f | --force) HAS_FORCE=1 ;;
    esac
done
[[ "$HAS_DELETE" -eq 1 && "$HAS_FORCE" -eq 1 ]] && IS_FORCE_DELETE=1
[[ "$IS_FORCE_DELETE" -eq 1 ]] || exit 0

# Collect branch-name operands after `branch` (skip flags; stop at a
# shell operator that ends this command segment).
NAMES=()
for ((i = BIDX + 1; i < ${#TOKENS[@]}; i++)); do
    t="${TOKENS[i]}"
    case "$t" in
        '&&' | '||' | ';' | '|' | '>' | '>>') break ;;
        -*) continue ;;
        *) NAMES+=("$t") ;;
    esac
done
[[ ${#NAMES[@]} -eq 0 ]] && exit 0

# Resolve the repo directory. Prefer `-C <dir>`, else the tool's cwd,
# else the project root. Relative `-C` paths resolve against cwd.
BASE="${CWD:-${CLAUDE_PROJECT_DIR:-.}}"
if [[ -z "$REPO_DIR" ]]; then
    REPO_DIR="$BASE"
elif [[ "$REPO_DIR" != /* ]]; then
    REPO_DIR="$BASE/$REPO_DIR"
fi

log_error() {
    local category="$1" reason="$2"
    local log="${CLAUDE_PROJECT_DIR:-.}/.claude/.session-errors"
    printf '{"ts":"%s","hook":"check-branch-delete","category":"%s","command":"%s","reason":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$category" \
        "$(printf '%s' "$COMMAND" | head -c 200 | tr '"' "'")" "$reason" \
        >> "$log" 2>/dev/null
}

# If origin/main isn't resolvable we cannot judge — advise and allow.
if ! git -C "$REPO_DIR" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    cat >&2 <<EOF
Advisory: could not verify branch safety before force-delete — origin/main
is not resolvable in $REPO_DIR (not fetched?). Run 'git -C <repo> fetch origin'
then 'git -C <repo> cherry origin/main <branch>' yourself: all '-' = safe,
any '+' = unmerged work that -D would discard. Proceeding without a guard.
EOF
    log_error "branch-delete-unverified" "origin/main unresolved"
    exit 0
fi

UNMERGED=()
for b in "${NAMES[@]}"; do
    # Branch must exist locally; if not, let git produce its own error.
    git -C "$REPO_DIR" rev-parse --verify --quiet "refs/heads/$b" >/dev/null 2>&1 || continue
    # `git cherry origin/main <b>` prints one line per commit on <b> that
    # is not (by patch-id) in origin/main, prefixed `+`. Any `+` = unmerged.
    if git -C "$REPO_DIR" cherry origin/main "$b" 2>/dev/null | grep -qE '^\+ '; then
        UNMERGED+=("$b")
    fi
done

[[ ${#UNMERGED[@]} -eq 0 ]] && exit 0

{
    printf 'Blocked: force-delete would discard unmerged commits.\n\n'
    printf 'These branches have commits NOT in origin/main (git cherry shows "+"):\n'
    for b in "${UNMERGED[@]}"; do
        printf '  %s\n' "$b"
        git -C "$REPO_DIR" cherry -v origin/main "$b" 2>/dev/null \
            | grep -E '^\+ ' | sed 's/^/      /'
    done
    cat <<'EOF'

`git branch -d` (reachability) cannot see through squash-merges; that is
exactly why -D is tempting here. But `git cherry` (patch-id) says these
patches are NOT in main yet — deleting loses them from local history.

Before retrying, verify ONE of:
  1. The MR merged:  glab mr view <num>   (state = merged), OR
  2. The work is on main:  git -C <repo> cherry origin/main <branch>
     returns ALL '-' markers (no '+'), OR
  3. The branch is pushed and you only want it gone locally — then it is
     recoverable from origin; delete is still your call, but confirm the
     remote has it: git -C <repo> ls-remote --heads origin <branch>.

If you have verified and still want it gone, run the delete in a real
terminal (this guard only intercepts the agent's Bash tool).
EOF
} >&2

log_error "unsafe-branch-delete" "cherry '+' on: ${UNMERGED[*]}"
exit 2
