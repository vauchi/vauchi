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

# BSD date takes an epoch with -r; GNU and BusyBox read -r as a file, so
# they fall through to -d @epoch.
_rig_format_epoch() {
    date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M' # portable-shell-ok: BSD first, GNU fallback
}

rig_describe() {
    local lock since note
    lock=$(_rig_lock "$1")
    since=$(_rig_field since "$lock")
    note=$(_rig_field note "$lock")
    printf '%s session:%s (slot %s, pid %s, since %s)' \
        "$(_rig_field harness "$lock")" "$(_rig_field session "$lock")" \
        "$(_rig_field slot "$lock")" "$(_rig_field pid "$lock")" \
        "$(_rig_format_epoch "${since:-0}")"
    [[ -n "$note" ]] && printf ' — %s' "$note"
    return 0
}

_rig_last_handover() {
    local state
    state=$(_rig_state "$1")
    [[ -f "$state" ]] && echo "  $1 last hand-over: $(head -n 1 "$state")"
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
            "$(slot_session_id)" "$(slot_harness)" "$(slot_name "${RIG_SLOT_ROOT:-$(pwd -P)}")" \
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
        _rig_report_claimed "$device"
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
    local reading
    for device in $mine; do
        printf 'released by %s session:%s at %s — %s\n' "$(slot_harness)" "$(slot_session_id)" \
            "$(date '+%Y-%m-%d %H:%M')" "${note:-no note}" > "$(_rig_state "$device")"
        # Read while still held: the next claim compares against this.
        reading=$(rig_readback "$device")
        [[ -n "$reading" ]] && printf 'readback: %s\n' "$reading" >> "$(_rig_state "$device")"
        rm -f "$(_rig_lock "$device")"
    done
    _rig_log "release: $(slot_session_id) released ${mine// /, } — ${note:-no note}"
    echo "✓ Released: ${mine// /, }"
}

# rig_install_wrappers <workspace-root>: link the device-tool wrapper as each
# tool it guards into $VAUCHI_RIG_HOME/bin (default ~/.vauchi/rig/bin), which
# goes first on PATH (#439, stage 3). The wrapper is copied, not linked, so a
# removed workspace slot does not break it; .workspace names the libraries
# and device table it reads.
rig_install_wrappers() {
    local root="$1" bin tool
    bin="${VAUCHI_RIG_HOME:-$HOME/.vauchi/rig}/bin"
    mkdir -p "$bin"
    cp "$root/just/rig-bin/rig-wrapper" "$bin/rig-wrapper"
    chmod +x "$bin/rig-wrapper"
    printf '%s\n' "$root" > "$bin/.workspace"
    for tool in adb ios maestro; do
        ln -sf rig-wrapper "$bin/$tool"
    done
    echo "✓ Wrappers for adb, ios and maestro in $bin (reading $root)"
    case ":$PATH:" in
        *":$bin:"*) ;;
        *) echo "  Put it first on PATH (e.g. in ~/.zshrc): export PATH=\"$bin:\$PATH\"" ;;
    esac
}

# ── Phone state on hand-over ──────────────────────────────────────────────
# Most runs lost on 2026-09-30 came from state changes nobody announced (a
# reinstall reset the camera permission and the identity). Release records
# what each phone reports; claim reads it again and names what changed. Only
# phones this session is releasing or has just claimed are read, read-only.
# iOS permissions are not readable through go-ios; the note must carry them.

_rig_table() {
    printf '%s' "${VAUCHI_RIG_DEVICE_TABLE:-${RIG_SLOT_ROOT:-$(pwd -P)}/_private/docs/testing/device-automation/rig-devices}"
}

# Prints "<platform> <first id>" for a phone, or nothing.
_rig_device_info() {
    local table
    table=$(_rig_table)
    [[ -f "$table" ]] || return 0
    awk -v d="$1" '$1 == d { print $2, $3; exit }' "$table"
}

_rig_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 15 "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout 15 "$@"
    else
        "$@"
    fi
}

_rig_grant() {
    local state
    state=$(printf '%s\n' "$2" | sed -n "s/.*$1: granted=\([a-z]*\).*/\1/p" | head -n 1)
    case "$state" in
        true) echo granted ;;
        false) echo denied ;;
        *) echo unknown ;;
    esac
}

# rig_readback <phone>: "app <version>, camera ..., notifications ..." (iOS:
# "app <version>"), "app not installed", "not readable", or nothing when
# reading is off or the phone is not in the device table.
rig_readback() {
    local info platform id out version
    [[ "${VAUCHI_RIG_READBACK:-1}" == 0 ]] && return 0
    info=$(_rig_device_info "$1")
    [[ -n "$info" ]] || return 0
    platform=${info%% *}
    id=${info#* }
    case "$platform" in
        android)
            if ! out=$(_rig_timeout adb -s "$id" shell dumpsys package app.vauchi 2>/dev/null); then
                echo "not readable"
                return 0
            fi
            version=$(printf '%s\n' "$out" | sed -n 's/.*versionName=\([^ ]*\).*/\1/p' | head -n 1)
            if [[ -z "$version" ]]; then
                echo "app not installed"
                return 0
            fi
            echo "app $version, camera $(_rig_grant android.permission.CAMERA "$out"), notifications $(_rig_grant android.permission.POST_NOTIFICATIONS "$out")"
            ;;
        ios)
            if ! out=$(_rig_timeout ios apps --udid="$id" 2>/dev/null); then
                echo "not readable"
                return 0
            fi
            version=$(printf '%s' "$out" | python3 -c '
import json, sys
try:
    apps = json.load(sys.stdin)
except ValueError:
    apps = []
for app in apps if isinstance(apps, list) else []:
    if app.get("CFBundleIdentifier") == "app.vauchi.ios":
        print(app.get("CFBundleShortVersionString", "?"))
' 2>/dev/null)
            if [[ -z "$version" ]]; then
                echo "app not installed"
            else
                echo "app $version"
            fi
            ;;
    esac
}

# "key old -> new; ..." for the fields that differ between two readbacks.
_rig_readback_diff() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        n = split(a, x, ", ")
        for (i = 1; i <= n; i++) { k = x[i]; sub(/ .*/, "", k); v = x[i]; sub(/^[^ ]+ /, "", v); old[k] = v }
        m = split(b, y, ", "); out = ""
        for (i = 1; i <= m; i++) {
            k = y[i]; sub(/ .*/, "", k); v = y[i]; sub(/^[^ ]+ /, "", v)
            if ((k in old) && old[k] != v) out = out (out == "" ? "" : "; ") k " " old[k] " -> " v
        }
        print out
    }'
}

# Report a phone this session just claimed: what it says now, and what
# changed since the last hand-over's reading.
_rig_report_claimed() {
    local device="$1" now before="" changed state
    now=$(rig_readback "$device")
    [[ -n "$now" ]] || return 0
    echo "  $device now: $now"
    state=$(_rig_state "$device")
    if [[ -f "$state" ]]; then
        before=$(sed -n 's/^readback: //p' "$state")
    fi
    [[ -n "$before" && "$before" != "not readable" && "$now" != "not readable" ]] || return 0
    changed=$(_rig_readback_diff "$before" "$now")
    if [[ -n "$changed" ]]; then
        echo "  $device changed since the hand-over: $changed"
    else
        echo "  $device unchanged since the hand-over"
    fi
}

# rig_check [phones] — for scripts that drive phones and cannot source this
# library (POSIX sh harnesses, tools called by absolute path): exits 1 when
# another live session holds one of the phones, naming it; a free phone
# passes with a reminder to claim it. Claims nothing. Defaults to the pair.
rig_check() {
    local devices phone held="" free=""
    devices=$(_rig_parse_devices "$(printf '%s' "$*" | tr ' ' ',')")
    [[ -n "$devices" ]] || devices=$RIG_PAIR
    for phone in $devices; do
        case "$(rig_lock_state "$phone")" in
            held) held="$held"$'\n'"  $phone: held by $(rig_describe "$phone")" ;;
            free | stale) free="$free $phone" ;;
        esac
    done
    if [[ -n "$held" ]]; then
        echo "[rig] Another live session holds a phone this needs (#439):$held" >&2
        echo "  Ask that session first; it releases with: just rig release" >&2
        return 1
    fi
    [[ -z "${free// /}" ]] || echo "[rig] Not claimed:$free — run: just rig claim ${free# } \"<what you run>\"" >&2
    return 0
}
