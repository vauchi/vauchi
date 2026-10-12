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

# Test the runners-health recipe
[group('tests')]
test-runners-health:
    python3 "{{justfile_directory()}}/tests/test_runners_health_recipe.py" "{{justfile_directory()}}/just/runners.just"

# Check health of all self-hosted GitLab runners via API.
# A runner is DEAD when GitLab reports it offline. contacted_at is shown
# but not judged: GitLab.com does not refresh it for an idle runner's polls,
# so it ages past minutes while the runner still takes a job within a
# second (pam and shelly-ann, 2026-10-12, private#10).
# Runners are named here and resolved to IDs through the group's runner list.
[group('runners')]
[no-cd]
[script]
runners-health:
    just gitlab _check-auth
    set -euo pipefail

    # Names, not IDs: an ID changes on every re-registration and drifted
    # from this list twice (private#10 T5.4); a name does not. The host is
    # the name without its role suffix.
    RUNNERS=(allyson-shell allyson-docker nell-shell shelly-ann-arm64 pam-shell)

    # Runner reads need a Maintainer-role token; the glab bot is Developer
    # and gets 403. Resolve a read-only token: env first, then the
    # Vaultwarden item via an unlocked bw session. Never fall back to the
    # bot token — that would reproduce the 403 as a fake outage. Distinct
    # from the CI-side RUNNER_HEALTH_TOKEN (api scope, probe observer).
    VAULT_ITEM="GitLab runners-health token"
    if [[ -z "${RUNNERS_HEALTH_READ_TOKEN:-}" && -n "${BW_SESSION:-}" ]] && command -v bw >/dev/null 2>&1; then
        RUNNERS_HEALTH_READ_TOKEN=$(bw get password "$VAULT_ITEM" 2>/dev/null) || RUNNERS_HEALTH_READ_TOKEN=""
    fi
    if [[ -z "${RUNNERS_HEALTH_READ_TOKEN:-}" ]]; then
        echo "ERROR: no runner-read token. Export RUNNERS_HEALTH_READ_TOKEN (group access token, Maintainer, read_api)"
        echo "       or unlock Vaultwarden (BW_SESSION) so the '$VAULT_ITEM' item can be read."
        exit 2
    fi
    export GITLAB_TOKEN="$RUNNERS_HEALTH_READ_TOKEN"

    if ! GROUP=$(glab api "groups/vauchi/runners?type=group_type&per_page=100" 2>/dev/null); then
        echo "ERROR: cannot list the group's runners: $(printf '%s' "$GROUP" | jq -r '.message // "API unreachable"' 2>/dev/null || echo "API unreachable")"
        exit 2
    fi

    NOW=$(date +%s)
    ALL_HEALTHY=true

    printf "%-18s %-10s %-8s %s\n" "RUNNER" "HOST" "STATUS" "LAST CONTACT"
    printf "%-18s %-10s %-8s %s\n" "──────────────────" "──────────" "────────" "────────────────────"

    for rname in "${RUNNERS[@]}"; do
        rhost=${rname%-*}
        MATCHES=$(printf '%s' "$GROUP" | jq -r --arg n "$rname" '.[] | select(.description == $n) | .id')
        case $(printf '%s' "$MATCHES" | grep -c .) in
            0)
                printf "%-18s %-10s %-8s %s\n" "$rname" "$rhost" "MISSING" "not registered in the vauchi group"
                ALL_HEALTHY=false
                continue
                ;;
            1) rid=$MATCHES ;;
            *)
                printf "%-18s %-10s %-8s %s\n" "$rname" "$rhost" "DUPLICATE" "registered as $(printf '%s' "$MATCHES" | tr '\n' ' ')"
                ALL_HEALTHY=false
                continue
                ;;
        esac
        # glab prints the API error body on stdout before exiting
        # non-zero, so appending a fallback document would hand jq two
        # JSON values and turn a 403/404 into a bogus "DEAD (epoch 0)".
        if ! DATA=$(glab api "runners/$rid" 2>/dev/null); then
            API_MESSAGE=$(printf '%s' "$DATA" | jq -r '.message // "API unreachable"' 2>/dev/null || echo "API unreachable")
            printf "%-18s %-10s %-8s %s\n" "$rname" "$rhost" "ERROR" "$API_MESSAGE"
            ALL_HEALTHY=false
            continue
        fi

        CONTACTED=$(echo "$DATA" | jq -r '.contacted_at // "unknown"')
        GITLAB_STATUS=$(echo "$DATA" | jq -r '.status // "unknown"')
        ACTIVE=$(echo "$DATA" | jq -r '.active // false')
        PAUSED=$(echo "$DATA" | jq -r '.paused // false')

        if [[ "$CONTACTED" == "unknown" || "$CONTACTED" == "null" ]]; then
            printf "%-18s %-10s %-8s %s\n" "$rname" "$rhost" "ERROR" "no contacted_at in API response"
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
        elif [[ "$GITLAB_STATUS" != "online" ]]; then
            STATUS="DEAD"
            ALL_HEALTHY=false
        else
            STATUS="OK"
        fi

        printf "%-18s %-10s %-8s %s (%dm ago, GitLab: %s)\n" "$rname" "$rhost" "$STATUS" "$CONTACTED" "$AGE_MIN" "$GITLAB_STATUS"
    done

    echo ""
    if $ALL_HEALTHY; then
        echo "✓ All runners healthy"
    else
        echo "✗ One or more runners unhealthy — see runner-runbook.md for restart procedures"
        exit 1
    fi
