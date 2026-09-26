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

# Same key as `just gitlab claim`, so a slot and a claim name one session.
slot_session_id() {
    printf '%s' "${VAUCHI_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-$(hostname -s):${CLAUDE_PROJECT_DIR:-$(pwd)}}}" \
        | shasum -a 256 | cut -c1-12
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
            free* | stale*) names+=("$(basename "$slot")") ;;
        esac
    done <<EOF
$(slot_siblings "$1")
EOF
    echo "${names[*]:-none}"
}

slot_acquire() {
    local root="$1" state
    read -r -a state <<< "$(slot_lock_state "$root")"
    if [[ "${state[0]}" == held ]]; then
        echo "HELD: slot $(basename "$root") is used by ${state[2]} session:${state[1]} (seen ${state[3]}h ago)"
        echo "  Start this session in another slot — free: $(slot_free_names "$root")"
        return 1
    fi
    if [[ "${state[0]}" == stale ]]; then
        echo "  Taking over stale slot lock (${state[2]} session:${state[1]}, ${state[3]}h old)"
    fi
    printf 'session=%s harness=%s seen=%s\n' "$(slot_session_id)" "$(slot_harness)" "$(date +%s)" \
        > "$root/$SLOT_LOCK_FILE"
    echo "✓ Slot $(basename "$root") held by this session ($(slot_harness) session:$(slot_session_id))"
}

slot_release() {
    local root="$1" state
    read -r -a state <<< "$(slot_lock_state "$root")"
    if [[ "${state[0]}" == mine ]]; then
        rm -f "$root/$SLOT_LOCK_FILE"
        echo "✓ Released slot $(basename "$root")"
    else
        echo "  Slot $(basename "$root") is not held by this session — left as is"
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
    local slot state lock off dirty repository branch
    printf '%-12s %s\n' "SLOT" "LOCK / REPOS"
    while IFS= read -r slot; do
        read -r -a state <<< "$(slot_lock_state "$slot")"
        case "${state[0]}" in
            free) lock="free" ;;
            mine) lock="held by you (${state[1]}, ${state[2]}h)" ;;
            held) lock="held by ${state[2]} session:${state[1]} (${state[3]}h)" ;;
            stale) lock="free (stale lock: ${state[2]} session:${state[1]}, ${state[3]}h)" ;;
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
        printf '%-12s %s — %d off main, %d dirty\n' "$(basename "$slot")" "$lock" "$off" "$dirty"
    done <<EOF
$(slot_siblings "$1")
EOF
}

# Claim stamp shared by `just gitlab claim` and the claim listings.
slot_claim_tag() {
    printf 'session:%s slot:%s\n' "$(slot_session_id)" "$(basename "$(cd "$1" && pwd -P)")"
}

# "<session> @<slot>" from a claim commit message; slot omitted on old claims.
slot_claim_owner() {
    local session slot
    session=$(printf '%s' "$1" | grep -oE 'session:[a-f0-9]+' | cut -d: -f2 || true)
    slot=$(printf '%s' "$1" | grep -oE 'slot:[A-Za-z0-9._-]+' | cut -d: -f2 || true)
    printf '%s%s\n' "${session:-unknown}" "${slot:+ @$slot}"
}

# "<repo> <path> <branch> <dirty-count>" for every linked worktree of the
# slot's repos. Slots replaced worktrees, so any found here is stray — made
# by hand or by a harness's own isolation — and may hold unsaved work.
slot_linked_worktrees() {
    local root="$1" repository main_path line path="" branch=""
    while IFS= read -r repository; do
        main_path=$(cd "$repository" && pwd -P)
        while IFS= read -r line; do
            case "$line" in
                "worktree "*) path=${line#worktree } ;;
                "branch "*) branch=${line#branch refs/heads/} ;;
                "")
                    if [[ -n "$path" && "$path" != "$main_path" ]]; then
                        printf '%s %s %s %s\n' "$(basename "$repository")" "$path" "${branch:-detached}" \
                            "$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
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
