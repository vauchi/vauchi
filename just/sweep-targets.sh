#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Sweeps stale Cargo artifacts from each repo named on the command line, from
# the workspace root. Exits 1 if any repo failed, after trying them all: this
# is housekeeping, and session-init must still reach the issue queue when one
# repo's Cargo.toml cannot be parsed (private#1095).

set -uo pipefail

readonly AGGRESSIVE_SWEEP_ABOVE_MB=20480

target_size_mb() {
    du -sm "$1/target" 2>/dev/null | cut -f1
}

sweep_older_than_days() {
    local days="$1" dir="$2" error
    if ! error=$(cargo sweep --time "$days" "$dir" 2>&1 >/dev/null); then
        echo "  WARNING: sweep failed in $dir: $(printf '%s\n' "$error" | head -n 1)"
        echo "    reproduce: cargo sweep --time $days $dir"
        return 1
    fi
}

failed=0
total_freed=0
for dir in "$@"; do
    [[ -d "$dir/target" ]] || continue
    before=$(target_size_mb "$dir")
    if ! sweep_older_than_days 2 "$dir"; then
        failed=1
        continue
    fi
    after=$(target_size_mb "$dir")
    if [[ $after -gt $AGGRESSIVE_SWEEP_ABOVE_MB ]]; then
        sweep_older_than_days 1 "$dir" || failed=1
        after=$(target_size_mb "$dir")
    fi
    freed=$((before - after))
    total_freed=$((total_freed + freed))
    if [[ $freed -gt 100 ]]; then
        echo "  $dir: freed ${freed} MB (${before} → ${after} MB)"
    fi
done

if [[ $total_freed -gt 100 ]]; then
    echo "  Total freed: ${total_freed} MB"
else
    echo "  (clean — <100 MB to sweep)"
fi
exit "$failed"
