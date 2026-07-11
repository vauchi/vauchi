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
    _DS_STALE=0

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

        # Refresh origin/main first — comparing against an unfetched ref
        # reports false UP TO DATE (the exact failure this alarm exists
        # to prevent). Tolerate offline: the stale ref is still shown.
        git -C "{{justfile_directory()}}/$repo" fetch origin main --quiet 2>/dev/null || true
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
            _DS_STALE=$(( _DS_STALE + 1 ))
        fi

        local _p=$(( _DS_C1 - ${#name} )); [[ $_p -lt 1 ]] && _p=1
        local _p2=$(( _DS_C2 - ${#status_text} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "  %s%*s ${status_color}%s${NC}%*s deployed=%-10s main=%-10s  %s\n" \
            "$name" "$_p" "" "$status_text" "$_p2" "" "$short_sha" "$main_short" "$deployed_time"
    }

    # For services whose public surface deliberately hides version info
    # (relay R-SA1: no version disclosure on the main port), drift is
    # checked via GitLab instead: registry digest of :latest vs the
    # origin/main sha tag, and the last successful deployment vs the
    # image build time. No public endpoint required or added.
    check_service_gitlab() {
        local name="$1" repo="$2" envpath="$3"
        local sha rid dig_l dig_s dep_at fin_at
        git -C "{{justfile_directory()}}/$repo" fetch origin main --quiet 2>/dev/null || true
        sha=$(git -C "{{justfile_directory()}}/$repo" rev-parse origin/main 2>/dev/null || echo "")
        rid=$(glab api "projects/vauchi%2F${repo}/registry/repositories" 2>/dev/null | jq -r --arg p "vauchi/${repo}" '.[] | select(.path==$p) | .id' | head -1 || true)
        dig_l=$(glab api "projects/vauchi%2F${repo}/registry/repositories/${rid}/tags/latest" 2>/dev/null | jq -r '.digest // empty' || true)
        dig_s=$(glab api "projects/vauchi%2F${repo}/registry/repositories/${rid}/tags/${sha}" 2>/dev/null | jq -r '.digest // empty' || true)
        dep_at=$(glab api "projects/vauchi%2Fprivate/deployments?environment=${envpath}&status=success&order_by=created_at&sort=desc&per_page=1" 2>/dev/null | jq -r '.[0].created_at // empty' || true)
        # finished_at only exists on the pipeline DETAIL endpoint —
        # the list response omits it (silently empty otherwise).
        local pid
        pid=$(glab api "projects/vauchi%2F${repo}/pipelines?sha=${sha}&ref=main&status=success" 2>/dev/null | jq -r '.[0].id // empty' || true)
        fin_at=""
        if [[ -n "$pid" ]]; then
            fin_at=$(glab api "projects/vauchi%2F${repo}/pipelines/${pid}" 2>/dev/null | jq -r '.finished_at // empty' || true)
        fi

        local status_text status_color
        if [[ -z "$sha" || -z "$dig_l" || -z "$dep_at" || -z "$fin_at" ]]; then
            # Never green-wash on missing evidence: without all four
            # facts the comparison below cannot prove currency.
            status_text="UNKNOWN"
            status_color="$YELLOW"
        elif [[ "$dig_l" != "$dig_s" ]]; then
            # :latest is not origin/main's image — wrong image tagged
            status_text="IMAGE DRIFT"
            status_color="$RED"
            _DS_STALE=$(( _DS_STALE + 1 ))
        elif [[ "${dep_at:0:19}" < "${fin_at:0:19}" ]]; then
            # Newest main image was built after the last deploy. A
            # same-sha rebuild also lands here — redeploying is a no-op
            # then, but only a deploy proves the host runs this image.
            status_text="STALE (image newer)"
            status_color="$RED"
            _DS_STALE=$(( _DS_STALE + 1 ))
        else
            status_text="UP TO DATE"
            status_color="$GREEN"
        fi

        local _p=$(( _DS_C1 - ${#name} )); [[ $_p -lt 1 ]] && _p=1
        local _p2=$(( _DS_C2 - ${#status_text} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "  %s%*s ${status_color}%s${NC}%*s deployed=%-10s main=%-10s  %s\n" \
            "$name" "$_p" "" "$status_text" "$_p2" "" "${dep_at:0:10}" "${sha:0:8}" "img-built=${fin_at:0:16}"
    }

    _ds_hdr() {
        local c1="$1" c2="$2" c3="$3" c4="$4" c5="$5"
        local _p1=$(( _DS_C1 - ${#c1} )); [[ $_p1 -lt 1 ]] && _p1=1
        local _p2=$(( _DS_C2 - ${#c2} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "  %s%*s %s%*s %-22s %-22s  %s\n" "$c1" "$_p1" "" "$c2" "$_p2" "" "$c3" "$c4" "$c5"
    }
    _ds_hdr "SERVICE" "STATUS" "DEPLOYED" "MAIN" "BUILT"
    printf "  ${DIM}%s${NC}\n" "$(printf '%*s' $(( _DS_C1 + _DS_C2 + 48 )) '' | tr ' ' '-')"

    check_service_gitlab "relay" "relay"       "production%2Frelay"
    check_service_gitlab "ohttp" "ohttp-relay" "production%2Fohttp-relay"
    check_service "website" "https://vauchi.app/build-info.json"  "website"
    check_service "docs"    "https://docs.vauchi.app/build-info.json" "docs"

    echo ""
    if [[ "$_DS_STALE" -gt 0 ]]; then
        # Exit nonzero so callers (session-init) surface the drift — a
        # stale docs deploy sat unnoticed for 10 weeks before this alarm
        # (backlog 2026-07-10-docs-deploy-drift-alarm).
        printf "${RED}DRIFT: %d service(s) behind origin/main${NC} — run: just deploy-latest <service>\n" "$_DS_STALE"
        exit 1
    fi
    echo "Fetch latest: just git fetch"

# Hand me the deploy button that is guaranteed to ship the newest main
# build. Does not deploy and changes no deploy config: it verifies the
# service repo's origin/main image is built, mints a FRESH _private main
# pipeline (its manual deploy:<service> job uses :latest by existing
# rule), and prints that job's URL. Sha-pinned buttons on older
# pipelines go stale the moment another MR merges — this one cannot.
[group('deploy')]
deploy-latest service:
    #!/usr/bin/env bash
    set -euo pipefail
    SERVICE="{{service}}"
    case "$SERVICE" in
        docs)        REPO="docs" ;;
        landing)     REPO="website" ;;
        relay)       REPO="relay" ;;
        ohttp-relay) REPO="ohttp-relay" ;;
        # cdn is excluded: its image lives at vauchi/website/cdn and
        # ci-deploy-service.sh has no :latest fallback for it — the
        # minted button would fail (verified 2026-07-10).
        *) echo "Unknown service: $SERVICE (docs|landing|relay|ohttp-relay)"; exit 1 ;;
    esac

    git -C "{{justfile_directory()}}/$REPO" fetch origin main --quiet 2>/dev/null || true
    SHA=$(git -C "{{justfile_directory()}}/$REPO" rev-parse origin/main)
    BUILT=$(glab api "projects/vauchi%2F${REPO}/pipelines?sha=${SHA}&ref=main&status=success" 2>/dev/null | jq 'length' || echo 0)
    echo "newest main:    $REPO ${SHA:0:8} (successful build pipelines: $BUILT)"
    if [[ "$BUILT" -eq 0 ]]; then
        echo "WARNING: no successful pipeline for ${SHA:0:8} yet —"
        echo "         :latest is older. Wait for the $REPO main pipeline, then rerun."
    fi

    # Prove :latest actually IS this sha's image (registry digests),
    # instead of assuming tag order.
    RID=$(glab api "projects/vauchi%2F${REPO}/registry/repositories" 2>/dev/null | jq -r --arg p "vauchi/${REPO}" '.[] | select(.path==$p) | .id' | head -1 || true)
    if [[ -n "$RID" ]]; then
        LATEST_DIGEST=$(glab api "projects/vauchi%2F${REPO}/registry/repositories/${RID}/tags/latest" 2>/dev/null | jq -r '.digest // empty' || true)
        SHA_DIGEST=$(glab api "projects/vauchi%2F${REPO}/registry/repositories/${RID}/tags/${SHA}" 2>/dev/null | jq -r '.digest // empty' || true)
        if [[ -n "$LATEST_DIGEST" && "$LATEST_DIGEST" == "$SHA_DIGEST" ]]; then
            echo "registry:       :latest digest == :${SHA:0:8} digest — verified"
        else
            echo "WARNING: :latest digest differs from :${SHA:0:8} — an older or"
            echo "         newer image holds the latest tag. Investigate before deploying."
        fi
    fi

    echo "minting fresh _private main pipeline..."
    PIPE=$(glab api -X POST "projects/vauchi%2Fprivate/pipeline?ref=main" | jq -r '.id')

    JOB_URL=""
    for _ in 1 2 3 4 5 6; do
        JOB_URL=$(glab api "projects/vauchi%2Fprivate/pipelines/${PIPE}/jobs?per_page=100" 2>/dev/null \
            | jq -r --arg n "deploy:${SERVICE}" '.[] | select(.name==$n) | .web_url' | head -1)
        [[ -n "$JOB_URL" ]] && break
        sleep 5
    done

    if [[ -z "$JOB_URL" ]]; then
        echo "Pipeline created but deploy:${SERVICE} job not visible yet:"
        echo "  https://gitlab.com/vauchi/private/-/pipelines/${PIPE}"
        exit 1
    fi
    echo ""
    echo "Press play here — this button deploys ${REPO}:latest:"
    echo "  $JOB_URL"
    echo ""
    echo "Playing creates a deployment that waits for APPROVAL"
    echo "(protected environment production/${SERVICE}) — approve it on the"
    echo "job page or under Operate > Environments, or it stays blocked."
    echo "Afterwards verify with: just deploy-check"

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

# Re-create landing page alias on monitoring network (run after each landing deploy)
[group('deploy')]
monitoring-landing-alias:
    #!/usr/bin/env bash
    set -euo pipefail
    # 'name=landing' matches both deploy paths: the generic docker-run
    # path (vauchi-landing-<digest>) and the Goal-6 compose path
    # (vauchi-relay-landing) — a path-specific filter went stale twice
    # and left the landing dashboards dark (2026-07-10, 2026-07-11).
    LANDING=$(ssh "{{ssh_target}}" "docker ps --filter 'name=landing' --format '{{{{.Names}}' | head -1")
    if [ -z "$LANDING" ]; then
        echo "ERROR: No running landing container found"
        exit 1
    fi
    ssh "{{ssh_target}}" "docker network disconnect monitoring_monitoring $LANDING 2>/dev/null || true"
    ssh "{{ssh_target}}" "docker network connect --alias vauchi-landing-web monitoring_monitoring $LANDING"
    echo "Connected $LANDING to monitoring network as 'vauchi-landing-web'"

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
