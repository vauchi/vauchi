# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Deployment recipes
# Config: _private/infra/config/deploy.combined.yml

ssh_target := "vauchi@bold-hopper-vps"

# ═══════════════════════════════════════════════════════════════════
# VALIDATION
# ═══════════════════════════════════════════════════════════════════

# Run pre-flight validation checks
[group('deploy')]
validate *FLAGS:
    ./_private/infra/scripts/validate.sh {{FLAGS}}

# ═══════════════════════════════════════════════════════════════════
# STATUS
# ═══════════════════════════════════════════════════════════════════

# Check deployed versions against source
[group('deploy')]
deploy-check:
    #!/usr/bin/env bash
    set -euo pipefail

    source scripts/scripts/output-helpers.sh
    echo "Checking deployed service versions..."
    echo ""

    _DS_C1=12  # service name column
    _DS_C2=28  # status column (fits "STALE (99 commits behind)")

    check_service() {
        local name="$1" url="$2" repo="$3"
        local deployed_sha deployed_time status_text status_color

        local info
        info=$(curl -sf --max-time 5 "$url" 2>/dev/null) || {
            local _p=$(( _DS_C1 - ${#name} )); [[ $_p -lt 1 ]] && _p=1
            local msg="UNKNOWN"
            local _p2=$(( _DS_C2 - ${#msg} )); [[ $_p2 -lt 1 ]] && _p2=1
            printf "  %s%*s ${YELLOW}%s${NC}%*s %s\n" "$name" "$_p" "" "$msg" "$_p2" "" "Could not fetch $url"
            return
        }

        deployed_sha=$(echo "$info" | jq -r '.sha // "unknown"')
        deployed_time=$(echo "$info" | jq -r '.built // "unknown"')
        local short_sha="${deployed_sha:0:8}"

        # Get local main HEAD
        local main_sha
        main_sha=$(git -C "{{justfile_directory()}}/$repo" rev-parse origin/main 2>/dev/null || echo "unknown")
        local main_short="${main_sha:0:8}"

        if [ "$deployed_sha" = "$main_sha" ]; then
            status_text="UP TO DATE"
            status_color="$GREEN"
        else
            local behind
            behind=$(git -C "{{justfile_directory()}}/$repo" rev-list "$deployed_sha..origin/main" --count 2>/dev/null || echo "?")
            status_text="STALE ($behind behind)"
            status_color="$RED"
        fi

        local _p=$(( _DS_C1 - ${#name} )); [[ $_p -lt 1 ]] && _p=1
        local _p2=$(( _DS_C2 - ${#status_text} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "  %s%*s ${status_color}%s${NC}%*s deployed=%-10s main=%-10s  %s\n" \
            "$name" "$_p" "" "$status_text" "$_p2" "" "$short_sha" "$main_short" "$deployed_time"
    }

    _ds_hdr() {
        local c1="$1" c2="$2" c3="$3" c4="$4" c5="$5"
        local _p1=$(( _DS_C1 - ${#c1} )); [[ $_p1 -lt 1 ]] && _p1=1
        local _p2=$(( _DS_C2 - ${#c2} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "  %s%*s %s%*s %-22s %-22s  %s\n" "$c1" "$_p1" "" "$c2" "$_p2" "" "$c3" "$c4" "$c5"
    }
    _ds_hdr "SERVICE" "STATUS" "DEPLOYED" "MAIN" "BUILT"
    printf "  ${DIM}%s${NC}\n" "$(printf '%*s' $(( _DS_C1 + _DS_C2 + 48 )) '' | tr ' ' '-')"

    check_service "relay"   "https://relay.vauchi.app/build-info" "relay"
    check_service "website" "https://vauchi.app/build-info.json"  "website"
    check_service "docs"    "https://docs.vauchi.app/build-info.json" "docs"

    echo ""
    echo "Fetch latest: just git fetch"

# ═══════════════════════════════════════════════════════════════════
# PROXY MANAGEMENT
# ═══════════════════════════════════════════════════════════════════

# Upgrade kamal-proxy to latest version (brief downtime ~2-3s)
[group('deploy')]
[confirm('This will restart kamal-proxy with brief downtime. Continue?')]
proxy-upgrade:
    kamal proxy reboot -c _private/infra/config/deploy.combined.yml --confirmed

# Show kamal-proxy routing table
[group('deploy')]
proxy-list:
    ssh {{ssh_target}} "docker exec kamal-proxy kamal-proxy list"

# ═══════════════════════════════════════════════════════════════════
# KAMAL DEPLOYMENT (relay + landing)
# ═══════════════════════════════════════════════════════════════════

# Deploy relay + landing using pre-built CI images (auto-resolves version from relay origin/main)
[group('deploy')]
deploy: validate
    ./_private/infra/scripts/deploy-all.sh --skip-validation

# Deploy relay + landing with local build + push (escape hatch for manual builds)
[group('deploy')]
deploy-with-build: validate
    ./_private/infra/scripts/deploy-all.sh --skip-validation --with-build

# Deploy a specific image version
[group('deploy')]
deploy-version VERSION:
    ./_private/infra/scripts/deploy-all.sh --version={{VERSION}}

# Verify website image contains only expected files (no workspace leaks)
[group('deploy')]
test-website-image:
    ./_private/infra/scripts/test-website-image.sh

# Show relay logs
[group('deploy')]
relay-logs:
    kamal app logs -f -c _private/infra/config/deploy.combined.yml

# Rollback to previous deployment version
[group('deploy')]
[confirm('This will roll back to the previous deployment. Continue?')]
deploy-rollback:
    #!/usr/bin/env bash
    set -euo pipefail

    CONFIG="_private/infra/config/deploy.combined.yml"
    if [[ ! -f "$CONFIG" ]]; then
        echo "ERROR: Deploy config not found at $CONFIG"
        exit 1
    fi

    echo "── Current deployment ──"
    kamal app version -c "$CONFIG" 2>/dev/null || echo "(could not fetch current version)"
    echo ""

    echo "── Rolling back ──"
    kamal rollback -c "$CONFIG"

    echo ""
    echo "── Rollback complete — verifying ──"
    kamal app version -c "$CONFIG" 2>/dev/null || echo "(could not verify — check manually)"

# ═══════════════════════════════════════════════════════════════════
# MAIL DEPLOYMENT
# ═══════════════════════════════════════════════════════════════════

# Sync mail config + restart changed services
[group('deploy')]
deploy-mail:
    ./_private/infra/scripts/deploy-mail.sh

# Preview mail config changes (dry run)
[group('deploy')]
deploy-mail-dry:
    ./_private/infra/scripts/deploy-mail.sh --dry-run

# Prepare mail server for first-time setup
[group('deploy')]
mail-prepare:
    ./_private/infra/mail/prepare-mail.sh

# ═══════════════════════════════════════════════════════════════════
# BACKUP & RESTORE
# ═══════════════════════════════════════════════════════════════════

# Run backup on the VPS
[group('deploy')]
backup:
    ssh {{ssh_target}} "/opt/vauchi-infra/scripts/backup.sh"

# Verify latest backup is restorable (runs on VPS)
[group('deploy')]
verify-backup:
    ssh {{ssh_target}} "/opt/vauchi-infra/scripts/verify-backup.sh"

# ═══════════════════════════════════════════════════════════════════
# MONITORING (Prometheus + Grafana)
# ═══════════════════════════════════════════════════════════════════

# Deploy / update monitoring stack (Prometheus + Grafana + node_exporter)
[group('deploy')]
deploy-monitoring:
    ./_private/infra/scripts/deploy-monitoring.sh

# Show monitoring stack status
[group('deploy')]
monitoring-status:
    ./_private/infra/scripts/deploy-monitoring.sh --status

# Follow Grafana logs
[group('deploy')]
monitoring-logs:
    ./_private/infra/scripts/deploy-monitoring.sh --logs

# Re-create relay alias on monitoring network (run after each relay deploy)
[group('deploy')]
monitoring-relay-alias:
    #!/usr/bin/env bash
    set -euo pipefail
    RELAY=$(ssh "{{ssh_target}}" "docker ps --filter 'name=vauchi-relay-web-' --format '{{{{.Names}}' | head -1")
    if [ -z "$RELAY" ]; then
        echo "ERROR: No running relay container found"
        exit 1
    fi
    ssh "{{ssh_target}}" "docker network disconnect monitoring_monitoring $RELAY 2>/dev/null || true"
    ssh "{{ssh_target}}" "docker network connect --alias vauchi-relay-web monitoring_monitoring $RELAY"
    echo "Connected $RELAY to monitoring network as 'vauchi-relay-web'"

# ═══════════════════════════════════════════════════════════════════
# VRT (Visual Regression Tracker)
# ═══════════════════════════════════════════════════════════════════

# Deploy / update VRT stack (Visual Regression Tracker)
[group('deploy')]
deploy-vrt:
    ./_private/infra/scripts/deploy-vrt.sh

# Show VRT stack status
[group('deploy')]
vrt-status:
    ./_private/infra/scripts/deploy-vrt.sh --status

# Follow VRT logs
[group('deploy')]
vrt-logs:
    ./_private/infra/scripts/deploy-vrt.sh --logs

# ═══════════════════════════════════════════════════════════════════
# DEPLOY EVERYTHING
# ═══════════════════════════════════════════════════════════════════

# Deploy Kamal services + sync mail config + monitoring + VRT
[group('deploy')]
deploy-all: deploy deploy-mail deploy-monitoring deploy-vrt

# ═══════════════════════════════════════════════════════════════════
# MAIL MANAGEMENT
# ═══════════════════════════════════════════════════════════════════

# Show mail server logs
[group('deploy')]
mail-logs:
    ssh {{ssh_target}} "cd /opt/mail && docker compose logs -f mailserver"

# Mail server status
[group('deploy')]
mail-status:
    ssh {{ssh_target}} "cd /opt/mail && docker compose ps && echo '' && ./setup.sh email list"

# Webmail logs
[group('deploy')]
mail-webmail-logs:
    ssh {{ssh_target}} "cd /opt/mail && docker compose logs -f roundcube webmail-nginx"

# Add mail user
[group('deploy')]
mail-add-user email:
    ssh {{ssh_target}} "cd /opt/mail && ./setup.sh email add {{email}}"

# Update mail user password
[group('deploy')]
mail-update-password email:
    ssh {{ssh_target}} "cd /opt/mail && ./setup.sh email update {{email}}"

# List mail users
[group('deploy')]
mail-list-users:
    ssh {{ssh_target}} "cd /opt/mail && ./setup.sh email list"
