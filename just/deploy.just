# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Deployment recipes
# Routine production operations are mediated by protected GitLab jobs.
# Exceptional host access starts from Hety's reviewed operator shell.

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

# Test the deploy-check recipe
[group('tests')]
test-deploy-check:
    python3 "{{justfile_directory()}}/tests/test_deploy_check_recipe.py" "{{justfile_directory()}}/just/deploy.just"

# Test the deploy-latest recipe
[group('tests')]
test-deploy-latest:
    python3 "{{justfile_directory()}}/tests/test_deploy_latest_recipe.py" "{{justfile_directory()}}/justfile"

# Check deployed versions against public and GitLab evidence.
[group('deploy')]
deploy-check *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail

    _DS_DEEP=0
    for _a in {{ARGS}}; do [ "$_a" = "--running" ] && _DS_DEEP=1; done
    if [ "$_DS_DEEP" -eq 1 ]; then
        echo "--running requires Hety's reviewed operator shell." >&2
        echo "Follow _private/docs/runbooks/ci-cd-deployment.md." >&2
        exit 2
    fi

    source scripts/scripts/output-helpers.sh
    echo "Checking deployed service versions..."
    echo "Ledger + approvals: https://gitlab.com/vauchi/private/-/environments"
    echo ""

    _DS_C1=12  # service name column
    _DS_C2=28  # status column (fits "STALE (99 commits behind)")
    _DS_STALE=0
    _DS_UNKNOWN=0

    _ds_unknown() {
        local name="$1" reason="$2"
        local _p=$(( _DS_C1 - ${#name} )); [[ $_p -lt 1 ]] && _p=1
        local msg="UNKNOWN"
        local _p2=$(( _DS_C2 - ${#msg} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "  %s%*s ${YELLOW}%s${NC}%*s %s\n" "$name" "$_p" "" "$msg" "$_p2" "" "$reason"
        _DS_UNKNOWN=$(( _DS_UNKNOWN + 1 ))
    }

    # Newest SUCCESSFUL main build SHA — the true "latest deployable" version.
    # origin/main HEAD may be unbuilt (pipeline still running) or failed, in
    # which case comparing against it reports a STALE that cannot actually be
    # deployed. Empty on API failure (caller falls back to origin/main).
    _latest_built_sha() {
        glab api "projects/vauchi%2F${1}/pipelines?ref=main&status=success&per_page=1" 2>/dev/null \
            | jq -r '.[0].sha // empty' 2>/dev/null
    }

    check_service() {
        local name="$1" url="$2" repo="$3"
        local deployed_sha deployed_time status_text status_color

        local info
        info=$(curl --fail-with-body -sSL --max-time 5 "$url" 2>/dev/null) || {
            _ds_unknown "$name" "Could not fetch $url"
            return
        }

        if ! jq -e '
            (.sha | type == "string" and test("^[0-9a-f]{40}$")) and
            (.built | type == "string" and length > 0)
        ' >/dev/null 2>&1 <<< "$info"; then
            _ds_unknown "$name" "Invalid build-info JSON from $url"
            return
        fi

        deployed_sha=$(jq -r '.sha' <<< "$info")
        deployed_time=$(jq -r '.built' <<< "$info")
        local short_sha="${deployed_sha:0:8}"

        # Refresh origin/main first — comparing against an unfetched ref
        # reports false UP TO DATE (the exact failure this alarm exists
        # to prevent). Tolerate offline: the stale ref is still shown.
        git -C "{{justfile_directory()}}/$repo" fetch origin main --quiet 2>/dev/null || true
        local main_sha
        main_sha=$(git -C "{{justfile_directory()}}/$repo" rev-parse origin/main 2>/dev/null || echo "unknown")

        # Compare against the newest SUCCESSFUL build, not origin/main HEAD:
        # an unbuilt or failed HEAD is not deployable, so "STALE vs HEAD" would
        # be a verdict you cannot act on. Fall back to HEAD if the API is down.
        local ref_sha ref_short unbuilt=""
        ref_sha=$(_latest_built_sha "$repo")
        [ -z "$ref_sha" ] && ref_sha="$main_sha"
        ref_short="${ref_sha:0:8}"
        # Note when main has advanced past the newest build (HEAD not yet built).
        if [ "$ref_sha" != "$main_sha" ] && [ "$main_sha" != "unknown" ]; then
            local ahead
            ahead=$(git -C "{{justfile_directory()}}/$repo" rev-list "$ref_sha..origin/main" --count 2>/dev/null || echo "?")
            unbuilt=" [HEAD +$ahead unbuilt]"
        fi

        if [ "$deployed_sha" = "$ref_sha" ]; then
            status_text="UP TO DATE"
            status_color="$GREEN"
        else
            local behind
            behind=$(git -C "{{justfile_directory()}}/$repo" rev-list "$deployed_sha..$ref_sha" --count 2>/dev/null || echo "?")
            status_text="STALE ($behind behind)"
            status_color="$RED"
            _DS_STALE=$(( _DS_STALE + 1 ))
        fi

        local _p=$(( _DS_C1 - ${#name} )); [[ $_p -lt 1 ]] && _p=1
        local _p2=$(( _DS_C2 - ${#status_text} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "  %s%*s ${status_color}%s${NC}%*s deployed=%-10s built=%-10s  %s%s\n" \
            "$name" "$_p" "" "$status_text" "$_p2" "" "$short_sha" "$ref_short" "$deployed_time" "$unbuilt"
    }

    # For services whose public surface deliberately hides version info
    # (relay R-SA1: no version disclosure on the main port), drift is
    # checked via GitLab instead: the image the last successful production
    # deploy job pinned vs the origin/main sha. No public endpoint required
    # or added. Registry tags are not evidence: :latest is the multi-arch
    # index and :<sha> the amd64 image, and every rebuild of a commit
    # re-pushes :<sha> (problems/2026-09-26-deploy-sha-tags-are-mutable).
    check_service_gitlab() {
        local name="$1" repo="$2" envpath="$3"
        local sha deployment dep_at job_id trace dep_image dep_tag running
        git -C "{{justfile_directory()}}/$repo" fetch origin main --quiet 2>/dev/null || true
        sha=$(git -C "{{justfile_directory()}}/$repo" rev-parse origin/main 2>/dev/null || echo "")
        deployment=$(glab api "projects/vauchi%2Fprivate/deployments?environment=${envpath}&status=success&order_by=created_at&sort=desc&per_page=1" 2>/dev/null || true)
        dep_at=$(jq -r 'if type == "array" then .[0].created_at // empty else empty end' <<<"$deployment" 2>/dev/null || true)
        job_id=$(jq -r 'if type == "array" then .[0].deployable.id // empty else empty end' <<<"$deployment" 2>/dev/null || true)
        trace=""
        if [[ -n "$job_id" ]]; then
            trace=$(glab api "projects/vauchi%2Fprivate/jobs/${job_id}/trace" 2>/dev/null || true)
        fi
        dep_image=$(sed -n 's/.*production deploy image is pinned: \([^[:space:]]*\).*/\1/p' <<<"$trace" | head -1)
        dep_tag=""
        [[ -n "$dep_image" ]] && dep_tag="${dep_image##*:}"
        running=$(sed -n 's/.*production running image: [^@]*@\(sha256:[0-9a-f]\{12\}\).*/\1/p' <<<"$trace" | head -1)

        local status_text status_color
        if [[ -z "$sha" || -z "$dep_tag" ]]; then
            # Never green-wash on missing evidence: without the main sha
            # and the deployed tag the comparison cannot prove currency.
            status_text="UNKNOWN"
            status_color="$YELLOW"
            _DS_UNKNOWN=$(( _DS_UNKNOWN + 1 ))
        elif [[ "$dep_tag" != "$sha" ]]; then
            status_text="STALE"
            status_color="$RED"
            _DS_STALE=$(( _DS_STALE + 1 ))
        else
            status_text="UP TO DATE"
            status_color="$GREEN"
        fi

        local _p=$(( _DS_C1 - ${#name} )); [[ $_p -lt 1 ]] && _p=1
        local _p2=$(( _DS_C2 - ${#status_text} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "  %s%*s ${status_color}%s${NC}%*s deployed=%-10s main=%-10s  %s\n" \
            "$name" "$_p" "" "$status_text" "$_p2" "" "${dep_tag:0:8}" "${sha:0:8}" \
            "at=${dep_at:0:16}${running:+ running=$running}"
    }

    _ds_hdr() {
        local c1="$1" c2="$2" c3="$3" c4="$4" c5="$5"
        local _p1=$(( _DS_C1 - ${#c1} )); [[ $_p1 -lt 1 ]] && _p1=1
        local _p2=$(( _DS_C2 - ${#c2} )); [[ $_p2 -lt 1 ]] && _p2=1
        printf "  %s%*s %s%*s %-22s %-22s  %s\n" "$c1" "$_p1" "" "$c2" "$_p2" "" "$c3" "$c4" "$c5"
    }
    _ds_hdr "SERVICE" "STATUS" "DEPLOYED" "MAIN" "BUILT"
    printf "  ${DIM}%s${NC}\n" "$(printf '%*s' $(( _DS_C1 + _DS_C2 + 48 )) '' | tr ' ' '-')"

    check_service_gitlab "relay" "relay"       "relay-prod"
    check_service_gitlab "ohttp" "ohttp-relay" "ohttp-relay-prod"
    check_service "website" "https://vauchi.app/build-info.json"  "website"
    check_service "docs"    "https://docs.vauchi.app/build-info.json" "docs"
    # cdn is built from the website repo, so its build-info sha is a website
    # commit — compare against website/origin/main. Reports UNKNOWN until the
    # cdn image starts baking build-info.json (vauchi/website!109).
    check_service "cdn"     "https://cdn.vauchi.app/build-info.json"  "website"

    echo ""
    _DS_RESULT=0
    if [[ "$_DS_STALE" -gt 0 ]]; then
        # Exit nonzero so callers (session-init) surface the drift — a
        # stale docs deploy sat unnoticed for 10 weeks before this alarm
        # (backlog 2026-07-10-docs-deploy-drift-alarm).
        printf "${RED}DRIFT: %d service(s) behind origin/main${NC} — run: just deploy-latest <service>\n" "$_DS_STALE"
        _DS_RESULT=1
    fi
    if [[ "$_DS_UNKNOWN" -gt 0 ]]; then
        printf "${YELLOW}EVIDENCE: %d service(s) could not be verified${NC}\n" "$_DS_UNKNOWN"
        _DS_RESULT=2
    fi
    [[ "$_DS_RESULT" -ne 0 ]] && exit "$_DS_RESULT"
    echo "Fetch latest: just git fetch"

# Hand me a deploy button pinned to the newest main build. Does not deploy or
# change deploy config: it verifies the service repo's origin/main image and
# gives the private pipeline that exact SHA-tagged image.
[group('deploy')]
deploy-latest service:
    #!/usr/bin/env bash
    set -euo pipefail
    SERVICE="{{service}}"
    case "$SERVICE" in
        docs)        REPO="docs" ;;
        landing)     REPO="website" ;;
        relay)       REPO="relay" ;;
        cdn)         REPO="website" ;;
        ohttp-relay) REPO="ohttp-relay" ;;
        monitoring)  REPO="private" ;;
        *) echo "Unknown service: $SERVICE (docs|landing|relay|cdn|ohttp-relay|monitoring)"; exit 1 ;;
    esac

    # Monitoring is config synced from _private (infra/monitoring/), not an
    # image: there is no build or registry tag to pin, and its button is the
    # deploy:monitoring job of a _private main pipeline.
    if [[ "$SERVICE" == monitoring ]]; then
        echo "minting _private main pipeline for deploy:monitoring..."
        PIPE_REQUEST=$(jq -n '{ref: "main", variables: [{key: "DEPLOY_SERVICE", value: "monitoring"}]}')
        PIPE=$(glab api -X POST "projects/vauchi%2Fprivate/pipeline" \
            -H "Content-Type: application/json" \
            --input - <<< "$PIPE_REQUEST" | jq -er '.id')
        CREATED_SERVICE=$(glab api "projects/vauchi%2Fprivate/pipelines/${PIPE}/variables" \
            | jq -r '.[] | select(.key=="DEPLOY_SERVICE") | .value')
        if [[ "$CREATED_SERVICE" != monitoring ]]; then
            echo "ERROR: pipeline did not retain DEPLOY_SERVICE=monitoring." >&2
            echo "       Inspect: https://gitlab.com/vauchi/private/-/pipelines/${PIPE}" >&2
            exit 1
        fi
        JOB_URL=""
        for _ in 1 2 3 4 5 6; do
            JOB_URL=$(glab api "projects/vauchi%2Fprivate/pipelines/${PIPE}/jobs?per_page=100" 2>/dev/null \
                | jq -r '.[] | select(.name=="deploy:monitoring") | .web_url' | head -1)
            [[ -n "$JOB_URL" ]] && break
            sleep 5
        done
        if [[ -z "$JOB_URL" ]]; then
            echo "Pipeline created but deploy:monitoring not visible yet:"
            echo "  https://gitlab.com/vauchi/private/-/pipelines/${PIPE}"
            exit 1
        fi
        echo ""
        echo "Press play here — this button syncs _private main's infra/monitoring/:"
        echo "  $JOB_URL"
        exit 0
    fi

    git -C "{{justfile_directory()}}/$REPO" fetch origin main --quiet 2>/dev/null || true
    SHA=$(git -C "{{justfile_directory()}}/$REPO" rev-parse origin/main)
    # glab prints the API error body ({"message":"401 ..."}) on stdout and
    # exits non-zero; piping it into `jq length` would count that one-key
    # object as one successful pipeline. Capture the exit status first and
    # only count a JSON array.
    if ! PIPELINES=$(glab api "projects/vauchi%2F${REPO}/pipelines?sha=${SHA}&ref=main&status=success" 2>/dev/null); then
        echo "ERROR: glab could not list $REPO pipelines (${PIPELINES:-no response})." >&2
        echo "       Check the token: glab auth status, or glab auth login." >&2
        exit 1
    fi
    BUILT=$(jq 'if type == "array" then length else 0 end' <<<"$PIPELINES")
    echo "newest main:    $REPO ${SHA:0:8} (successful build pipelines: $BUILT)"
    if [[ "$BUILT" -eq 0 ]]; then
        echo "ERROR: no successful pipeline for ${SHA:0:8} yet." >&2
        echo "       Wait for the $REPO main pipeline, then rerun." >&2
        exit 1
    fi

    RID=$(glab api "projects/vauchi%2F${REPO}/registry/repositories" 2>/dev/null | jq -r --arg p "vauchi/${REPO}" '.[] | select(.path==$p) | .id' | head -1 || true)
    if [[ -z "$RID" ]]; then
        echo "ERROR: no registry repository found for vauchi/$REPO." >&2
        exit 1
    fi

    SHA_DIGEST=$(glab api "projects/vauchi%2F${REPO}/registry/repositories/${RID}/tags/${SHA}" 2>/dev/null | jq -r '.digest // empty' || true)
    if [[ -z "$SHA_DIGEST" ]]; then
        echo "ERROR: no registry image for ${REPO}:${SHA}." >&2
        echo "       Wait for the image build, then rerun." >&2
        exit 1
    fi
    echo "registry:       :${SHA:0:8} exists (${SHA_DIGEST:0:19}...)"

    LATEST_DIGEST=$(glab api "projects/vauchi%2F${REPO}/registry/repositories/${RID}/tags/latest" 2>/dev/null | jq -r '.digest // empty' || true)
    if [[ -n "$LATEST_DIGEST" && "$LATEST_DIGEST" != "$SHA_DIGEST" ]]; then
        echo "registry note:  :latest differs; this link remains pinned to :${SHA:0:8}"
    fi

    DEPLOY_IMAGE="registry.gitlab.com/vauchi/${REPO}:${SHA}"
    echo "minting SHA-pinned _private main pipeline..."
    PIPE_REQUEST=$(jq -n \
        --arg service "$SERVICE" \
        --arg deploy_image "$DEPLOY_IMAGE" \
        --arg deploy_image_digest "$SHA_DIGEST" \
        '{ref: "main", variables: [
            {key: "DEPLOY_SERVICE", value: $service},
            {key: "DEPLOY_IMAGE", value: $deploy_image},
            {key: "DEPLOY_IMAGE_DIGEST", value: $deploy_image_digest}
        ]}')
    PIPE=$(glab api -X POST "projects/vauchi%2Fprivate/pipeline" \
        -H "Content-Type: application/json" \
        --input - <<< "$PIPE_REQUEST" | jq -er '.id')

    PIPE_VARIABLES=$(glab api "projects/vauchi%2Fprivate/pipelines/${PIPE}/variables")
    CREATED_SERVICE=$(jq -r '.[] | select(.key=="DEPLOY_SERVICE") | .value' <<< "$PIPE_VARIABLES")
    CREATED_IMAGE=$(jq -r '.[] | select(.key=="DEPLOY_IMAGE") | .value' <<< "$PIPE_VARIABLES")
    CREATED_DIGEST=$(jq -r '.[] | select(.key=="DEPLOY_IMAGE_DIGEST") | .value' <<< "$PIPE_VARIABLES")
    if [[ "$CREATED_SERVICE" != "$SERVICE" || "$CREATED_IMAGE" != "$DEPLOY_IMAGE" \
        || "$CREATED_DIGEST" != "$SHA_DIGEST" ]]; then
        echo "ERROR: pipeline did not retain the requested deploy variables." >&2
        echo "       Inspect: https://gitlab.com/vauchi/private/-/pipelines/${PIPE}" >&2
        exit 1
    fi
    echo "pipeline:       service, SHA-pinned image and digest verified"

    JOB_URL=""
    for _ in 1 2 3 4 5 6; do
        JOB_URL=$(glab api "projects/vauchi%2Fprivate/pipelines/${PIPE}/jobs?per_page=100" 2>/dev/null \
            | jq -r --arg n "kamal:deploy:${SERVICE}-production" '.[] | select(.name==$n) | .web_url' | head -1)
        [[ -n "$JOB_URL" ]] && break
        sleep 5
    done

    if [[ -z "$JOB_URL" ]]; then
        echo "Pipeline created but kamal:deploy:${SERVICE}-production job not visible yet:"
        echo "  https://gitlab.com/vauchi/private/-/pipelines/${PIPE}"
        exit 1
    fi
    echo ""
    echo "Press play here — this button deploys ${DEPLOY_IMAGE}"
    echo "(pinned to ${SHA_DIGEST}; the job refuses a re-pushed tag):"
    echo "  $JOB_URL"
    echo ""
    echo "Playing creates a deployment that waits for APPROVAL"
    echo "(protected environment ${SERVICE}-prod) — approve it on the"
    echo "job page or under Operate > Environments, or it stays blocked."
    echo "Afterwards verify with: just deploy-check"

# ═══════════════════════════════════════════════════════════════════
# PROXY MANAGEMENT
# ═══════════════════════════════════════════════════════════════════

# Proxy mutation requires protected GitLab approval.
[group('deploy')]
proxy-upgrade:
    @echo "Proxy upgrades are unavailable from the daily driver."
    @echo "Add a protected GitLab job through review before routine use."
    @echo "Use Hety only for recorded break-glass recovery."
    @exit 1

# Proxy inspection requires Hety's reviewed operator shell.
[group('deploy')]
proxy-list:
    @echo "Direct production inspection is unavailable from the daily driver."
    @echo "Use GitLab deployment evidence or Hety's reviewed operator shell."
    @exit 1

# ═══════════════════════════════════════════════════════════════════
# APP DEPLOYS (via CI — Kamal 2)
# ═══════════════════════════════════════════════════════════════════
#
# Apps (relay, landing, cdn, docs, ohttp-relay) deploy in CI via Kamal 2
# (kamal:deploy:<service>-production jobs), gated by GitLab
# protected-environment approval. Mint a fresh, always-current deploy button
# with:
#
#     just deploy-latest <service>
#
# The former hand-rolled `ci-deploy-service.sh` path was retired in 2026-07;
# it duplicated Kamal's health-gated swap/rollback logic and drove the
# container name/label drift behind the 2026-07-12 outage.

# Verify website image contains only expected files (no workspace leaks)
[group('deploy')]
test-website-image:
    ./_private/infra/scripts/test-website-image.sh

# Relay logs are available through centralized monitoring or reviewed access.
[group('deploy')]
relay-logs:
    @echo "Direct production logs are unavailable from the daily driver."
    @echo "Use Grafana, GitLab deployment evidence, or Hety's reviewed operator shell."
    @exit 1

# Rollback uses immutable GitLab deployment evidence and protected approval.
[group('deploy')]
deploy-rollback service:
    @echo "Local rollback of {{service}} is unavailable from the daily driver."
    @echo "Use the protected GitLab environment and immutable image evidence."
    @echo "Use Hety's reviewed operator shell only for break-glass recovery."
    @exit 1

# ═══════════════════════════════════════════════════════════════════
# MAIL DEPLOYMENT
# ═══════════════════════════════════════════════════════════════════

# Mail changes require protected GitLab approval.
[group('deploy')]
deploy-mail:
    @echo "Mail deployment is unavailable from the daily driver."
    @echo "Use the protected GitLab production job."
    @exit 1

# Preview mail changes in a protected GitLab pipeline.
[group('deploy')]
deploy-mail-dry:
    @echo "Mail deployment preview is unavailable from the daily driver."
    @echo "Use the GitLab validation pipeline."
    @exit 1

# Initial mail preparation requires reviewed Hety access.
[group('deploy')]
mail-prepare:
    @echo "Mail host preparation is unavailable from the daily driver."
    @echo "Use Hety's reviewed operator shell and the current deployment runbook."
    @exit 1

# ═══════════════════════════════════════════════════════════════════
# BACKUP & RESTORE
# ═══════════════════════════════════════════════════════════════════

# Backup execution requires Hety's FIDO2 operator boundary.
[group('deploy')]
backup:
    @echo "Backup is intentionally unavailable from the daily driver."
    @echo "Use Hety and _private/docs/runbooks/2026-07-11-backup-restore.md."
    @exit 1

# Restore verification requires independent credentials obtained on Hety.
[group('deploy')]
verify-backup:
    @echo "Backup verification is intentionally unavailable from the daily driver."
    @echo "Use Hety and _private/docs/runbooks/2026-07-11-backup-restore.md."
    @exit 1

# ═══════════════════════════════════════════════════════════════════
# MONITORING (Prometheus + Grafana)
# ═══════════════════════════════════════════════════════════════════

# Monitoring changes require protected GitLab approval.
[group('deploy')]
deploy-monitoring:
    @echo "Monitoring deployment is unavailable from the daily driver."
    @echo "Use the protected GitLab production job."
    @exit 1

# Monitoring status is available through Grafana or reviewed access.
[group('deploy')]
monitoring-status:
    @echo "Direct production status is unavailable from the daily driver."
    @echo "Use Grafana, GitLab deployment evidence, or Hety's reviewed operator shell."
    @exit 1

# Monitoring logs are available through reviewed access.
[group('deploy')]
monitoring-logs:
    @echo "Direct production logs are unavailable from the daily driver."
    @echo "Use Grafana or Hety's reviewed operator shell."
    @exit 1

# Monitoring-network repair requires reviewed Hety access.
[group('deploy')]
monitoring-relay-alias:
    @echo "Monitoring-network repair is unavailable from the daily driver."
    @echo "Use Hety's reviewed operator shell and record the break-glass action."
    @exit 1

# Landing monitoring-network repair requires reviewed Hety access.
[group('deploy')]
monitoring-landing-alias:
    @echo "Monitoring-network repair is unavailable from the daily driver."
    @echo "Use Hety's reviewed operator shell and record the break-glass action."
    @exit 1

# ═══════════════════════════════════════════════════════════════════
# VRT (Visual Regression Tracker)
# ═══════════════════════════════════════════════════════════════════

# VRT changes require protected GitLab approval.
[group('deploy')]
deploy-vrt *args:
    @echo "VRT deployment is unavailable from the daily driver."
    @echo "Use the protected GitLab production job."
    @exit 1

# VRT status requires reviewed access.
[group('deploy')]
vrt-status:
    @echo "Direct production status is unavailable from the daily driver."
    @echo "Use GitLab deployment evidence or Hety's reviewed operator shell."
    @exit 1

# VRT logs require reviewed access.
[group('deploy')]
vrt-logs:
    @echo "Direct production logs are unavailable from the daily driver."
    @echo "Use Hety's reviewed operator shell."
    @exit 1

# ═══════════════════════════════════════════════════════════════════
# DEPLOY EVERYTHING
# ═══════════════════════════════════════════════════════════════════

# Support-stack deployment requires protected GitLab jobs.
[group('deploy')]
deploy-all:
    @echo "Support-stack deployment is unavailable from the daily driver."
    @echo "Use the protected GitLab production jobs."
    @exit 1

# ═══════════════════════════════════════════════════════════════════
# MAIL MANAGEMENT
# ═══════════════════════════════════════════════════════════════════

# Mail logs require reviewed access.
[group('deploy')]
mail-logs:
    @echo "Direct production logs are unavailable from the daily driver."
    @echo "Use centralized monitoring or Hety's reviewed operator shell."
    @exit 1

# Mail status requires reviewed access.
[group('deploy')]
mail-status:
    @echo "Direct production status is unavailable from the daily driver."
    @echo "Use monitoring or Hety's reviewed operator shell."
    @exit 1

# Webmail logs require reviewed access.
[group('deploy')]
mail-webmail-logs:
    @echo "Direct production logs are unavailable from the daily driver."
    @echo "Use centralized monitoring or Hety's reviewed operator shell."
    @exit 1

# Mail-user administration requires reviewed access.
[group('deploy')]
mail-add-user email:
    @echo "Mail-user changes are unavailable from the daily driver."
    @echo "Use Hety's reviewed operator shell and record the administrative action."
    @exit 1

# Mail-user administration requires reviewed access.
[group('deploy')]
mail-update-password email:
    @echo "Mail-user changes are unavailable from the daily driver."
    @echo "Use Hety's reviewed operator shell and record the administrative action."
    @exit 1

# Mail-user listing requires reviewed access.
[group('deploy')]
mail-list-users:
    @echo "Mail-user listing is unavailable from the daily driver."
    @echo "Use Hety's reviewed operator shell."
    @exit 1
