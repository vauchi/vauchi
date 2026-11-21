# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Workspace slots: every full clone of the workspace (vauchi, vauchi-1, ...)
# is a slot hosting one session at a time. Parallel sessions take separate
# slots instead of git worktrees, which leave the root's .claude link
# dangling and start every claim with a cold build
# (problems/2026-09-25-work-tracking-on-gitlab-issues).

SLOT_LOCK_FILE=".slot.lock"
SLOT_LOCK_EXPIRY_HOURS="${SLOT_LOCK_EXPIRY_HOURS:-12}"

# sha256sum exists on BusyBox, GNU and macOS; shasum only on macOS and Perl
# hosts. Both print the same digest, so ids match `just gitlab claim`.
_slot_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256
    else
        echo "slot-lib: need sha256sum or shasum" >&2
        return 1
    fi
}

# Same key as `just gitlab claim`, so a slot and a claim name one session.
slot_session_id() {
    printf '%s' "${VAUCHI_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-$(hostname -s 2>/dev/null || hostname):${CLAUDE_PROJECT_DIR:-$(pwd)}}}" \
        | _slot_sha256 | cut -c1-12
}

slot_harness() {
    case "${VAUCHI_SESSION_ID:-}" in
        codex-*) echo codex ;;
        kimi-*) echo kimi ;;
        claude-*) echo claude ;;
        "") [[ -n "${CLAUDE_CODE_SESSION_ID:-}" ]] && echo claude || echo shell ;;
        *) echo other ;;
    esac
}

# "<host>/<folder>[/<agent>]": slots are per machine, so the host comes first;
# the agent segment names the harness holding the slot, so a free slot has none.
slot_name() {
    local root agent
    root=$(cd "$1" && pwd -P)
    agent=${2:-}
    printf '%s/%s%s\n' "$(hostname -s 2>/dev/null || hostname)" "$(basename "$root")" "${agent:+/$agent}"
}

slot_siblings() {
    local root parent family candidate
    root=$(cd "$1" && pwd -P)
    parent=$(dirname "$root")
    family=$(basename "$root")
    family=${family%-[0-9]*}
    for candidate in "$parent/$family" "$parent/$family"-*; do
        [[ "$(basename "$candidate")" =~ ^${family}(-[0-9]+)?$ ]] || continue
        [[ -f "$candidate/justfile" && -f "$candidate/CLAUDE.md" ]] || continue
        printf '%s\n' "$candidate"
    done
}

# Prints: free | mine <harness> <age_h> | held <session> <harness> <age_h> | stale <session> <harness> <age_h>
slot_lock_state() {
    local lock="$1/$SLOT_LOCK_FILE" session harness seen age_h
    if [[ ! -f "$lock" ]]; then
        echo free
        return
    fi
    session=$(sed -n 's/.*session=\([^ ]*\).*/\1/p' "$lock")
    harness=$(sed -n 's/.*harness=\([^ ]*\).*/\1/p' "$lock")
    seen=$(sed -n 's/.*seen=\([0-9]*\).*/\1/p' "$lock")
    age_h=$(( ($(date +%s) - ${seen:-0}) / 3600 ))
    if [[ "$session" == "$(slot_session_id)" ]]; then
        echo "mine $harness $age_h"
    elif [[ "$age_h" -ge "$SLOT_LOCK_EXPIRY_HOURS" ]]; then
        echo "stale $session $harness $age_h"
    else
        echo "held $session $harness $age_h"
    fi
}

slot_free_names() {
    local slot names=()
    while IFS= read -r slot; do
        case "$(slot_lock_state "$slot")" in
            free* | stale*) names+=("$(slot_name "$slot")") ;;
        esac
    done <<EOF
$(slot_siblings "$1")
EOF
    echo "${names[*]:-none}"
}

slot_acquire() {
    local root state
    root=$(cd "$1" && pwd -P)
    read -r -a state <<< "$(slot_lock_state "$root")"
    if [[ "${state[0]}" == held ]]; then
        echo "HELD: slot $(slot_name "$root" "${state[2]}") is used by session:${state[1]} (seen ${state[3]}h ago)"
        echo "  Start this session in another slot — free: $(slot_free_names "$root")"
        return 1
    fi
    if [[ "${state[0]}" == stale ]]; then
        echo "  Taking over stale slot lock (${state[2]} session:${state[1]}, ${state[3]}h old)"
    fi
    printf 'session=%s harness=%s seen=%s\n' "$(slot_session_id)" "$(slot_harness)" "$(date +%s)" \
        > "$root/$SLOT_LOCK_FILE"
    echo "✓ Slot $(slot_name "$root" "$(slot_harness)") held by this session (session:$(slot_session_id))"
}

# Heartbeat: re-stamps seen= on a lock this session holds, so a live session
# older than SLOT_LOCK_EXPIRY_HOURS is not taken over as stale (#414).
# Silent and a no-op for a free slot or another session's lock.
slot_touch() {
    local root state
    root=$(cd "$1" && pwd -P)
    read -r -a state <<< "$(slot_lock_state "$root")"
    [[ "${state[0]}" == mine ]] || return 0
    printf 'session=%s harness=%s seen=%s\n' "$(slot_session_id)" "${state[1]}" "$(date +%s)" \
        > "$root/$SLOT_LOCK_FILE"
}

slot_release() {
    local root state
    root=$(cd "$1" && pwd -P)
    read -r -a state <<< "$(slot_lock_state "$root")"
    if [[ "${state[0]}" == mine ]]; then
        rm -f "$root/$SLOT_LOCK_FILE"
        echo "✓ Released slot $(slot_name "$root" "$(slot_harness)")"
    else
        echo "  Slot $(slot_name "$root") is not held by this session — left as is"
    fi
}

slot_repositories() {
    local root="$1" entry
    printf '%s\n' "$root"
    for entry in "$root"/*/; do
        [[ -e "$entry/.git" ]] && printf '%s\n' "${entry%/}"
    done
}

slot_status() {
    local slot state lock agent off dirty repository branch
    printf '%-28s %s\n' "SLOT" "LOCK / REPOS"
    while IFS= read -r slot; do
        read -r -a state <<< "$(slot_lock_state "$slot")"
        case "${state[0]}" in
            free) lock="free"; agent="" ;;
            mine) lock="held by you (${state[1]}, ${state[2]}h)"; agent=${state[1]} ;;
            held) lock="held by ${state[2]} session:${state[1]} (${state[3]}h)"; agent=${state[2]} ;;
            stale) lock="free (stale lock: ${state[2]} session:${state[1]}, ${state[3]}h)"; agent="" ;;
        esac
        off=0
        dirty=0
        while IFS= read -r repository; do
            branch=$(git -C "$repository" branch --show-current 2>/dev/null || true)
            [[ -n "$branch" && "$branch" != main ]] && off=$((off + 1))
            [[ -n "$(git -C "$repository" status --porcelain 2>/dev/null)" ]] && dirty=$((dirty + 1))
        done <<EOF
$(slot_repositories "$slot")
EOF
        printf '%-28s %s — %d off main, %d dirty\n' "$(slot_name "$slot" "$agent")" "$lock" "$off" "$dirty"
    done <<EOF
$(slot_siblings "$1")
EOF
}

# Claim stamp shared by `just gitlab claim` and the claim listings. Slots are
# per machine but claims are shared, so the slot is qualified by its host.
slot_claim_tag() {
    printf 'session:%s slot:%s\n' "$(slot_session_id)" "$(slot_name "$1" "$(slot_harness)")"
}

# "<session> @<slot>" from a claim commit message; slot omitted on old claims.
slot_claim_owner() {
    local session slot
    session=$(printf '%s' "$1" | grep -oE 'session:[a-f0-9]+' | cut -d: -f2 || true)
    slot=$(printf '%s' "$1" | grep -oE 'slot:[A-Za-z0-9._/-]+' | cut -d: -f2 || true)
    printf '%s%s\n' "${session:-unknown}" "${slot:+ @$slot}"
}

# "<repo> <path> <branch> <dirty-count|missing>" for every linked worktree of the
# slot's repos. Slots replaced worktrees, so any found here is stray — made
# by hand or by a harness's own isolation — and may hold unsaved work.
slot_linked_worktrees() {
    local root="$1" repository main_path line path="" branch="" state
    while IFS= read -r repository; do
        # `git rev-parse --show-toplevel` returns the same path shape as
        # `git worktree list --porcelain` on every platform. `pwd -P` on
        # Git-Bash returned `/c/...` while worktree list returned `C:/...`,
        # so every normal clone was reported as a stray worktree (private#1334).
        main_path=$(git -C "$repository" rev-parse --show-toplevel 2>/dev/null)
        while IFS= read -r line; do
            case "$line" in
                "worktree "*) path=${line#worktree } ;;
                "branch "*) branch=${line#branch refs/heads/} ;;
                "")
                    if [[ -n "$path" && "$path" != "$main_path" ]]; then
                        if [[ -d "$path" ]]; then
                            state=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
                        else
                            state=missing
                        fi
                        printf '%s %s %s %s\n' "$(basename "$repository")" "$path" "${branch:-detached}" "$state"
                    fi
                    path=""
                    branch=""
                    ;;
            esac
        done <<LIST
$(git -C "$repository" worktree list --porcelain 2>/dev/null)

LIST
    done <<REPOS
$(slot_repositories "$root")
REPOS
}
