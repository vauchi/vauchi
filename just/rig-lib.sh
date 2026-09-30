# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# The device rig: one session at a time holds each phone (#439). On
# 2026-09-30 two sessions wiped phone state under another session's test
# runs because nothing said a phone was in use.
#
# Each phone has its own lock; a bare claim takes the exchange pair, since
# pair tests always need both, and a phone off the rig can be held on its
# own. Phones are named here, not by serial: this repo is public.
#
# The phones are shared by every workspace slot, so the locks live outside
# them. A holder is alive while its process runs: a run can sit inside one
# long Maestro command for many minutes, and a heartbeat rule would hand a
# phone over mid-run. The recorded start time guards against a reused pid.
#
# Needs slot-lib.sh sourced first (slot_session_id, slot_harness). Recipes
# set RIG_SLOT_ROOT to the workspace root: a module recipe runs in just/.

RIG_DIR="${VAUCHI_RIG_DIR:-$HOME/.vauchi/rig}"
RIG_DEVICES="${VAUCHI_RIG_DEVICES:-pixel iphone s7}"
RIG_PAIR="${VAUCHI_RIG_PAIR:-pixel iphone}"
RIG_LOG="$RIG_DIR/log"
RIG_LOCK_EXPIRY_HOURS="${RIG_LOCK_EXPIRY_HOURS:-24}"

_rig_lock() { printf '%s/%s.lock' "$RIG_DIR" "$1"; }
_rig_state() { printf '%s/%s.state' "$RIG_DIR" "$1"; }

_rig_field() {
    sed -n "s/^$1=//p" "$2" | head -n 1
}

_rig_started() {
    ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'
}

_rig_log() {
    mkdir -p "$RIG_DIR"
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$RIG_LOG"
}

_rig_comm() {
    basename "$(ps -o comm= -p "$1" 2>/dev/null | sed 's/ *$//')"
}

_rig_is_device() {
    local known
    for known in $RIG_DEVICES; do
        [[ "$known" == "$1" ]] && return 0
    done
    return 1
}

# Devices named by a first argument such as "s7" or "pixel,s7", when every
# name is a known phone; prints nothing otherwise (the argument is a note).
_rig_parse_devices() {
    local name names
    [[ -n "${1:-}" && "$1" =~ ^[a-z0-9,-]+$ ]] || return 0
    names=$(printf '%s' "$1" | tr ',' ' ')
    for name in $names; do
        _rig_is_device "$name" || return 0
    done
    printf '%s' "$names"
}

# The process whose life the claim lasts: the agent session (claude, codex,
# kimi) that ran the recipe, else the shell that ran `just` — a person at a
# terminal holds the phones until that shell exits.
rig_holder_pid() {
    if [[ -n "${VAUCHI_RIG_HOLDER_PID:-}" ]]; then
        echo "$VAUCHI_RIG_HOLDER_PID"
        return
    fi
    local pid=$$ parent caller=""
    while [[ "$pid" -gt 1 ]]; do
        parent=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [[ -n "$parent" ]] || break
        case "$(_rig_comm "$parent")" in
            claude | codex | kimi | kimi-code)
                echo "$parent"
                return
                ;;
        esac
        [[ -z "$caller" && "$(_rig_comm "$pid")" == just ]] && caller=$parent
        pid=$parent
    done
    echo "${caller:-$PPID}"
}

# rig_lock_state <device> prints: free | mine | held | stale
rig_lock_state() {
    local lock session pid started since age_h
    lock=$(_rig_lock "$1")
    [[ -f "$lock" ]] || {
        echo free
        return
    }
    session=$(_rig_field session "$lock")
    pid=$(_rig_field pid "$lock")
    started=$(_rig_field started "$lock")
    since=$(_rig_field since "$lock")
    age_h=$(( ($(date +%s) - ${since:-0}) / 3600 ))
    if [[ "$session" == "$(slot_session_id)" ]]; then
        echo mine
    elif [[ -z "$pid" || "$(_rig_started "$pid")" != "$started" || "$age_h" -ge "$RIG_LOCK_EXPIRY_HOURS" ]]; then
        echo stale
    else
        echo held
    fi
}

rig_describe() {
    local lock since note
    lock=$(_rig_lock "$1")
    since=$(_rig_field since "$lock")
    note=$(_rig_field note "$lock")
    printf '%s session:%s (slot %s, pid %s, since %s)' \
        "$(_rig_field harness "$lock")" "$(_rig_field session "$lock")" \
        "$(_rig_field slot "$lock")" "$(_rig_field pid "$lock")" \
        "$(date -r "${since:-0}" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@${since:-0}" '+%Y-%m-%d %H:%M')"
    [[ -n "$note" ]] && printf ' — %s' "$note"
    return 0
}

_rig_last_handover() {
    local state
    state=$(_rig_state "$1")
    [[ -f "$state" ]] && echo "  $1 last hand-over: $(cat "$state")"
    return 0
}

rig_status() {
    local device line
    for device in $RIG_DEVICES; do
        case "$(rig_lock_state "$device")" in
            free) line="free" ;;
            mine) line="held by you — $(rig_describe "$device")" ;;
            held) line="held by $(rig_describe "$device")" ;;
            stale) line="free (stale lock, holder process gone: $(rig_describe "$device"))" ;;
        esac
        printf '%-8s %s\n' "$device" "$line"
    done
    for device in $RIG_DEVICES; do
        _rig_last_handover "$device"
    done
}

# rig_claim [--force] [devices] [note...] — devices default to the pair.
rig_claim() {
    local force=0 devices device given state pid started tmp note taken=""
    if [[ "${1:-}" == --force ]]; then
        force=1
        shift
    fi
    devices=$(_rig_parse_devices "${1:-}")
    if [[ -n "$devices" ]]; then
        shift
    else
        devices=$RIG_PAIR
    fi
    note=$(printf '%s' "$*" | tr '\n' ' ')
    mkdir -p "$RIG_DIR"

    # All or nothing: check every phone before taking any.
    for device in $devices; do
        if [[ "$(rig_lock_state "$device")" == held && "$force" == 0 ]]; then
            echo "HELD: $device is held by $(rig_describe "$device")"
            echo "  Nothing claimed. Ask its holder first; the owner can take it with:"
            echo "  just rig claim --force $device <reason>"
            return 1
        fi
    done

    pid=$(rig_holder_pid)
    started=$(_rig_started "$pid")
    if [[ -z "$started" ]]; then
        echo "rig: holder process $pid not found" >&2
        return 2
    fi
    for device in $devices; do
        state=$(rig_lock_state "$device")
        case "$state" in
            held)
                echo "  Forcing $device from $(rig_describe "$device")"
                _rig_log "force: $(slot_session_id) took $device from $(_rig_field session "$(_rig_lock "$device")") — $note"
                ;;
            stale)
                echo "  Taking over a stale $device lock (holder process gone): $(rig_describe "$device")"
                _rig_log "stale takeover: $(slot_session_id) took $device from $(_rig_field session "$(_rig_lock "$device")")"
                ;;
        esac
        tmp=$(mktemp "$RIG_DIR/.$device.lock.XXXXXX")
        printf 'session=%s\nharness=%s\nslot=%s\npid=%s\nstarted=%s\nsince=%s\nnote=%s\n' \
            "$(slot_session_id)" "$(slot_harness)" "$(basename "${RIG_SLOT_ROOT:-$(pwd -P)}")" \
            "$pid" "$started" "$(date +%s)" "$note" > "$tmp"
        if [[ "$state" == free ]]; then
            # ln refuses an existing target, so two sessions racing for a
            # free phone cannot both win; the loser gives back what it took.
            if ! ln "$tmp" "$(_rig_lock "$device")" 2>/dev/null; then
                rm -f "$tmp"
                for given in $taken; do rm -f "$(_rig_lock "$given")"; done
                echo "HELD: another session claimed the phones just now — nothing claimed; run: just rig status"
                return 1
            fi
            rm -f "$tmp"
        else
            mv -f "$tmp" "$(_rig_lock "$device")"
        fi
        taken="$taken $device"
    done
    taken=${taken# }
    _rig_log "claim: $(slot_session_id) pid $pid took ${taken// /, } — $note"
    echo "✓ Held by this session: ${taken// /, } ($(slot_harness) session:$(slot_session_id), pid $pid)"
    for device in $taken; do
        _rig_last_handover "$device"
    done
}

# rig_release [devices] [state note...] — devices default to all this session holds.
rig_release() {
    local devices device note mine=""
    devices=$(_rig_parse_devices "${1:-}")
    if [[ -n "$devices" ]]; then
        shift
        for device in $devices; do
            if [[ "$(rig_lock_state "$device")" != mine ]]; then
                echo "$device is not held by this session — nothing released"
                return 1
            fi
        done
        mine=$devices
    else
        for device in $RIG_DEVICES; do
            [[ "$(rig_lock_state "$device")" == mine ]] && mine="$mine $device"
        done
        mine=${mine# }
        if [[ -z "$mine" ]]; then
            echo "This session holds no phone — nothing to release"
            return 1
        fi
    fi
    note=$(printf '%s' "$*" | tr '\n' ' ')
    [[ -n "$note" ]] || echo "  No state note: the next holder will not know the phones' state (build, identity, permissions, reinstalled?)"
    for device in $mine; do
        printf 'released by %s session:%s at %s — %s\n' "$(slot_harness)" "$(slot_session_id)" \
            "$(date '+%Y-%m-%d %H:%M')" "${note:-no note}" > "$(_rig_state "$device")"
        rm -f "$(_rig_lock "$device")"
    done
    _rig_log "release: $(slot_session_id) released ${mine// /, } — ${note:-no note}"
    echo "✓ Released: ${mine// /, }"
}
