#!/bin/bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Test runner for `.claude/hooks/check-destructive.sh`.
#
# Covers: recursive-rm target rules (home, bare glob/dot, absolute
# vs /tmp, variables allowed), find -delete root rules, xargs rm
# flags, git clean force vs dry-run, secret-dir references, the
# git-commit-body exemption, and compound-command segmentation.
#
# Run: bash .claude/hooks/tests/check-destructive.test.sh
# Exits 0 on full pass, 1 on any failure. Each case prints PASS/FAIL.
#
# shellcheck disable=SC2016  # literal $HOME/$TMP in case strings is the
# point — the hook matches unexpanded command text.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOK_DIR/check-destructive.sh"
FAKE_ROOT="/tmp/check-destructive.test.$$"

if [[ ! -x "$HOOK" ]]; then
    echo "FATAL: $HOOK not executable" >&2
    exit 1
fi

mkdir -p "$FAKE_ROOT/.claude"
touch "$FAKE_ROOT/.claude/.session-errors"
trap 'rm -rf "$FAKE_ROOT"' EXIT

PASS=0
FAIL=0

expect_exit() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  PASS  %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n    expected exit: %s\n    got:           %s\n' \
            "$name" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

run_hook() {
    local cmd="$1"
    local json
    json=$(jq -nc --arg cmd "$cmd" --arg cwd "$FAKE_ROOT" \
        '{tool_input:{command:$cmd},cwd:$cwd}')
    CLAUDE_PROJECT_DIR="$FAKE_ROOT" bash "$HOOK" <<< "$json" >/dev/null 2>&1
}

blocked() { run_hook "$1"; expect_exit "$2" 2 "$?"; }
allowed() { run_hook "$1"; expect_exit "$2" 0 "$?"; }

# ── Rule 2: recursive rm ──
blocked 'rm -rf ~/foo'                    'B1 rm -rf ~/foo'
blocked 'rm -fr /etc/x'                   'B2 rm -fr /etc/x (flag order)'
blocked 'rm -r -f /home/user/x'           'B3 rm -r -f abs path (split flags)'
blocked 'rm -rf *'                        'B4 rm -rf bare *'
blocked 'rm -rf .'                        'B5 rm -rf .'
blocked 'rm -rf ../other'                 'B6 rm -rf ../path'
blocked 'rm -rf "$HOME/x"'                'B7 rm -rf quoted $HOME'
blocked 'echo done && rm -rf /opt/data'   'B8 compound segment rm'
allowed 'rm -rf /tmp/foo'                 'A1 rm -rf /tmp path'
allowed 'rm -rf /var/folders/zz/x'        'A2 rm -rf macOS tempdir'
allowed 'rm -rf tmp/build cache/x'        'A3 rm -rf relative paths'
allowed 'rm -rf ./node_modules'           'A4 rm -rf ./relative'
allowed 'rm -rf "$TMP/dir"'               'A5 rm -rf variable target'
allowed 'rm file.txt'                     'A6 plain rm file'
allowed 'rm -f stale.lock'                'A7 rm -f non-recursive'

# ── Rule 3: find ──
blocked "find / -name '*.log' -delete"    'B9 find / -delete'
blocked 'find ~ -name x -exec rm {} \;'   'B10 find ~ -exec rm'
allowed 'find /tmp/x -delete'             'A8 find /tmp -delete'
allowed "find . -name '*.tmp' -delete"    'A9 find . -delete (relative)'
allowed 'find core -name "*.rs" -print'   'A10 find without delete'

# ── Rule 4: xargs rm ──
blocked 'ls | xargs rm -rf'               'B11 xargs rm -rf'
allowed 'git ls-files -z | xargs -0 rm'   'A11 xargs rm without flags'

# ── Rule 5: git clean ──
blocked 'git clean -fdx'                  'B12 git clean -fdx'
blocked 'git -C core clean -fd'           'B13 git -C clean -fd'
allowed 'git clean -n'                    'A12 git clean dry-run'
allowed 'git clean -dn'                   'A13 git clean dry-run with -d'

# ── Rule 1: secret dirs ──
blocked 'cat ~/.ssh/id_ed25519'           'B14 cat ssh key'
blocked 'cp x ~/.aws/credentials'         'B15 write aws credentials'
blocked 'grep token ~/.config/glab-cli/config.yml' 'B16 read glab config'
blocked 'ls /home/megloff1/.gnupg/'       'B17 abs-home gnupg'
allowed 'echo sshd_config docs'           'A14 ssh substring not a path'

# ── Exemptions ──
allowed 'git commit -m "docs: explain the rm -rf ~/.ssh guard"' 'A15 commit body skipped'
allowed 'git status'                      'A16 unrelated git'
allowed 'echo hello'                      'A17 trivial command'

echo ""
if [[ "$FAIL" -eq 0 ]]; then
    printf 'check-destructive.test: %d passed, 0 failed\n' "$PASS"
    exit 0
else
    printf 'check-destructive.test: %d passed, %d FAILED\n' "$PASS" "$FAIL"
    exit 1
fi
