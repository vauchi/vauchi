# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# GitLab runner recipes

# ═══════════════════════════════════════════════════════════════════
# GITLAB RUNNERS (docker-local via systemd)
# ═══════════════════════════════════════════════════════════════════

# Start docker-local runner service
[group('runners')]
runners-start:
    @echo "Starting docker-local runner..."
    systemctl --user start gitlab-runner 2>/dev/null || echo "[SKIP] docker-local service not configured"
    @echo "Done. Run 'just runners-status' to verify."

# Stop docker-local runner service
[group('runners')]
runners-stop:
    @echo "Stopping docker-local runner..."
    systemctl --user stop gitlab-runner 2>/dev/null || echo "[SKIP] docker-local service not configured"

# Restart docker-local runner service
[group('runners')]
runners-restart:
    @echo "Restarting docker-local runner..."
    systemctl --user restart gitlab-runner 2>/dev/null || echo "[SKIP] docker-local service not configured"

# Show status of all runners
[group('runners')]
runners-status:
    @echo "── Runner Status ──"
    @echo ""
    @echo "Docker-local (systemd):"
    @systemctl --user status gitlab-runner --no-pager 2>&1 | head -5 || echo "  Not configured"
    @echo ""
    @echo "── GitLab Runner Config ──"
    @gitlab-runner list 2>&1 | head -20 || echo "  gitlab-runner not installed"

# View docker-local runner logs (follow mode)
[group('runners')]
runners-logs:
    journalctl --user -u gitlab-runner -f

# Check health of all self-hosted GitLab runners via API.
# Reports contacted_at staleness — if > 5 minutes, the runner is dead.
# Runner IDs are from _private/docs/reference/runner-runbook.md.
[group('runners')]
[no-cd]
[script]
runners-health:
    just gitlab _check-auth
    set -euo pipefail

    # Runner registry: id:name:host
    RUNNERS=(
        "51793663:nell-shell:nell"
        "52407190:allyson-docker:allyson"
    )
    STALE_THRESHOLD=300  # 5 minutes in seconds

    NOW=$(date +%s)
    ALL_HEALTHY=true

    printf "%-18s %-10s %-8s %s\n" "RUNNER" "HOST" "STATUS" "LAST CONTACT"
    printf "%-18s %-10s %-8s %s\n" "──────────────────" "──────────" "────────" "────────────────────"

    for entry in "${RUNNERS[@]}"; do
        IFS=: read -r rid rname rhost <<< "$entry"
        DATA=$(glab api "runners/$rid" 2>/dev/null || echo '{}')

        CONTACTED=$(echo "$DATA" | jq -r '.contacted_at // "unknown"')
        ACTIVE=$(echo "$DATA" | jq -r '.active // false')
        PAUSED=$(echo "$DATA" | jq -r '.paused // false')

        if [[ "$CONTACTED" == "unknown" || "$CONTACTED" == "null" ]]; then
            printf "%-18s %-10s %-8s %s\n" "$rname" "$rhost" "ERROR" "API unreachable"
            ALL_HEALTHY=false
            continue
        fi

        # Parse ISO8601 to epoch (portable: works on macOS and Linux)
        # GitLab returns UTC timestamps (trailing Z) — must parse in UTC
        CLEAN=${CONTACTED%%.*}  # strip fractional seconds
        CLEAN=${CLEAN%%Z}       # strip Z suffix
        CLEAN=${CLEAN%%+*}      # strip timezone offset if present
        CONTACT_EPOCH=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$CLEAN" +%s 2>/dev/null \
            || date -ud "$CONTACTED" +%s 2>/dev/null \
            || echo "0")

        AGE=$((NOW - CONTACT_EPOCH))
        AGE_MIN=$((AGE / 60))

        if [[ "$PAUSED" == "true" ]]; then
            STATUS="PAUSED"
        elif [[ "$AGE" -gt "$STALE_THRESHOLD" ]]; then
            STATUS="DEAD"
            ALL_HEALTHY=false
        else
            STATUS="OK"
        fi

        printf "%-18s %-10s %-8s %s (%dm ago)\n" "$rname" "$rhost" "$STATUS" "$CONTACTED" "$AGE_MIN"
    done

    echo ""
    if $ALL_HEALTHY; then
        echo "✓ All runners healthy"
    else
        echo "✗ One or more runners unhealthy — see runner-runbook.md for restart procedures"
        exit 1
    fi
