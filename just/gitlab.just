# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# GitLab operations: MRs, pipelines, issues
# Usage: just gitlab <recipe>

# ── Helpers ─────────────────────────────────────────────────────────

[private]
[no-cd]
[script]
_check-auth:
    if ! glab auth status &>/dev/null; then
        echo "ERROR: glab not authenticated — run 'glab auth login'"
        exit 1
    fi

# ── MR Operations ──────────────────────────────────────────────────

# List open merge requests
[no-cd]
[script]
mr-list repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab mr list -R "vauchi/$r"

# View merge request details
[no-cd]
[script]
mr-view id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab mr view "{{id}}" -R "vauchi/$r"

# Create merge request from current branch
# Usage: just gitlab mr-create [repo] [title]
#   just gitlab mr-create core                    # auto-fill from commits
#   just gitlab mr-create core "feat: my feature" # custom title
[no-cd]
[script]
mr-create repo='' title='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    dir=$(gitlab_repo_dir "{{repo}}")
    cd "$dir"
    branch=$(git branch --show-current)
    if [[ "$branch" == "main" ]]; then
        echo "ERROR: cannot create MR from main branch"
        exit 1
    fi
    # Push branch if not tracking remote (skip tests — CI runs them)
    export SKIP_TESTS=1
    if ! git rev-parse --abbrev-ref "@{u}" &>/dev/null; then
        git push -u origin "$branch"
    fi
    ARGS=(--fill --yes --target-branch main --push -R "vauchi/$r")
    if [[ -n "{{ title }}" ]]; then
        ARGS+=(--title "{{ title }}")
    fi
    glab mr create "${ARGS[@]}"

# Approve a merge request
[no-cd]
[script]
mr-approve id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab mr approve "{{id}}" -R "vauchi/$r"

# Merge a merge request
[no-cd]
[script]
mr-merge id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab mr merge "{{id}}" --yes -R "vauchi/$r"

# Close a merge request
[no-cd]
[script]
mr-close id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab mr close "{{id}}" -R "vauchi/$r"

# Create or update MRs for all repos on the same feature branch
# Idempotent: creates MR if none exists, rebases + force-pushes if one does.
# Usage: just gitlab mr-create-all                    # auto-fill title from commits
#        just gitlab mr-create-all "feat: my feature" # custom title
[no-cd]
[script]
mr-create-all title='':
    just gitlab _check-auth
    source scripts/scripts/output-helpers.sh
    set -euo pipefail
    timer_start

    created=()
    updated=()
    uptodate=()
    failed=()

    for dir in */; do
        [[ -d "${dir}.git" ]] || continue
        label="${dir%/}"
        branch=$(git -C "$dir" branch --show-current 2>/dev/null)

        # Skip repos on main or detached HEAD
        [[ "$branch" == "main" || -z "$branch" ]] && continue

        # Skip repos with no commits ahead
        ahead=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
        [[ "$ahead" -eq 0 ]] && continue

        echo ""
        echo "── $label ($branch, $ahead commits) ──"

        # Check for existing MR
        source scripts/scripts/resolve-repo.sh
        gl_name=$(_dir_to_gitlab_name "$label")
        existing=$(glab mr list -R "vauchi/$gl_name" --source-branch "$branch" --json url 2>/dev/null | grep -c "url" || true)
        has_mr=$([[ "$existing" -gt 0 ]] && echo "yes" || echo "no")

        # Rebase on origin/main
        git -C "$dir" fetch origin main --quiet 2>/dev/null
        behind=$(git -C "$dir" rev-list --count HEAD..origin/main 2>/dev/null || echo "0")
        rebased=no
        if [[ "$behind" -gt 0 ]]; then
            printf "  ↓ %s commits behind — rebasing...\n" "$behind"
            if ! git -C "$dir" rebase origin/main 2>&1 | sed 's/^/  /'; then
                echo "  ✗ CONFLICT — skipping (resolve manually)"
                git -C "$dir" rebase --abort 2>/dev/null
                failed+=("$label")
                continue
            fi
            rebased=yes
        fi

        export SKIP_TESTS=1

        if [[ "$has_mr" == "yes" ]]; then
            # MR exists — force-push if rebased, otherwise up-to-date
            if [[ "$rebased" == "yes" ]]; then
                echo "  MR exists — force-pushing rebased branch..."
                if git -C "$dir" push --force-with-lease origin "$branch" 2>&1 | sed 's/^/  /'; then
                    updated+=("$label")
                else
                    echo "  Force-push failed"
                    failed+=("$label")
                fi
            else
                echo "  MR exists, already up to date"
                uptodate+=("$label")
            fi
        else
            # No MR — create one via push options
            PUSH_OPTS=(-u origin "$branch")
            PUSH_OPTS+=(-o merge_request.create)
            PUSH_OPTS+=(-o merge_request.target=main)
            PUSH_OPTS+=(-o merge_request.remove_source_branch)

            if [[ -n "{{ title }}" ]]; then
                mr_title="{{ title }}"
            else
                mr_title=$(git -C "$dir" log origin/main..HEAD --reverse --format=%s | head -1)
            fi
            PUSH_OPTS+=(-o "merge_request.title=$mr_title")

            echo "  Pushing and creating MR..."
            if git -C "$dir" push "${PUSH_OPTS[@]}" 2>&1 | sed 's/^/  /'; then
                created+=("$label")

                # Update MR description via API (push options don't support multiline)
                mr_iid=$(glab api "projects/vauchi%2F${gl_name}/merge_requests?state=opened&source_branch=${branch}&per_page=1" 2>/dev/null \
                  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['iid'] if d else '')" 2>/dev/null || true)
                if [[ -n "$mr_iid" ]]; then
                    # Generate description from commits and changed files
                    commits=$(git -C "$dir" log origin/main..HEAD --reverse --format="- %s")
                    files=$(git -C "$dir" diff --stat origin/main..HEAD | tail -1 | sed 's/^ //')
                    desc="## Summary\n\n${commits}\n\n---\n_${files}_"
                    glab api -X PUT "projects/vauchi%2F${gl_name}/merge_requests/${mr_iid}" \
                      -f "description=${desc}" >/dev/null 2>&1 || true
                    echo "  Updated MR !${mr_iid} description"
                fi
            else
                echo "  Push failed"
                failed+=("$label")
            fi
        fi
        echo ""
    done

    elapsed=$(timer_elapsed)
    echo ""
    echo "── Summary (${elapsed}s) ──"
    [[ ${#created[@]}  -gt 0 ]] && printf "  ${GREEN}✓${NC} Created  (%d):  %s\n" "${#created[@]}" "${created[*]}"
    [[ ${#updated[@]}  -gt 0 ]] && printf "  ${GREEN}✓${NC} Updated  (%d):  %s\n" "${#updated[@]}" "${updated[*]}"
    [[ ${#uptodate[@]} -gt 0 ]] && printf "  ${DIM}·${NC} Up-to-date (%d): %s\n" "${#uptodate[@]}" "${uptodate[*]}"
    [[ ${#failed[@]}   -gt 0 ]] && printf "  ${RED}✗${NC} Failed   (%d):   %s\n" "${#failed[@]}" "${failed[*]}"
    [[ ${#failed[@]}   -gt 0 ]] && exit 1 || true

# ── Pipeline Operations ────────────────────────────────────────────

# Show pipeline status for current branch
[no-cd]
[script]
pipeline-status repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    dir=$(gitlab_repo_dir "{{repo}}")
    branch=$(cd "$dir" && git branch --show-current)
    glab ci status --branch "$branch" -R "vauchi/$r"

# List recent pipelines
[no-cd]
[script]
pipeline-list repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab ci list -R "vauchi/$r"

# List jobs in a pipeline
[no-cd]
[script]
pipeline-jobs id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab ci list -R "vauchi/$r" --pipeline "{{id}}"

# View job log output
[no-cd]
[script]
pipeline-log job_id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab ci trace "{{job_id}}" -R "vauchi/$r"

# Retry a failed pipeline
[no-cd]
[script]
pipeline-retry id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab ci retry "{{id}}" -R "vauchi/$r"

# Cancel a running pipeline
[no-cd]
[script]
pipeline-cancel id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab ci delete "{{id}}" -R "vauchi/$r"

# ── Issue Operations ───────────────────────────────────────────────

# List open issues
[no-cd]
[script]
issue-list repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab issue list -R "vauchi/$r"

# View issue details
[no-cd]
[script]
issue-view id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab issue view "{{id}}" -R "vauchi/$r"

# Create an issue
[no-cd]
[script]
issue-create title repo='' *args='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab issue create --title "{{title}}" --no-editor --yes -R "vauchi/$r" {{args}}

# Close an issue
[no-cd]
[script]
issue-close id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab issue close "{{id}}" -R "vauchi/$r"

# ── Status & Wait ─────────────────────────────────────────────────

# Show MR status for current branch
[no-cd]
[script]
mr-status repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    dir=$(gitlab_repo_dir "{{repo}}")
    branch=$(cd "$dir" && git branch --show-current)
    if [[ "$branch" == "main" ]]; then
        echo "On main branch — no MR to show"
        exit 0
    fi
    # Find MR for this branch
    mr_json=$(glab mr list -R "vauchi/$r" --source-branch "$branch" --json number,title,state,mergedAt,webUrl 2>/dev/null || echo "[]")
    count=$(echo "$mr_json" | jq 'length')
    if [[ "$count" == "0" ]]; then
        echo "No MR found for branch '$branch' in vauchi/$r"
        exit 0
    fi
    echo "$mr_json" | jq -r '.[] | "MR !\(.number): \(.title)\n  State: \(.state)\n  URL:   \(.webUrl)\n"'
    # Show pipeline status
    echo "Pipeline:"
    glab ci status --branch "$branch" -R "vauchi/$r" 2>/dev/null || echo "  No pipeline found"

# Wait for pipeline to complete on current branch
# Usage: just gitlab pipeline-wait [repo]
#   Polls every 30s until pipeline finishes (passed/failed/canceled)
[no-cd]
[script]
pipeline-wait repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    dir=$(gitlab_repo_dir "{{repo}}")
    branch=$(cd "$dir" && git branch --show-current)
    echo "Waiting for pipeline on $branch in vauchi/$r..."
    echo "(polling every 30s, Ctrl+C to stop)"
    echo ""
    while true; do
        # Get pipeline status via glab ci status
        output=$(glab ci status --branch "$branch" -R "vauchi/$r" 2>&1 || true)
        # Check for terminal states
        if echo "$output" | grep -qiE "passed|success"; then
            echo "$output"
            echo ""
            echo "Pipeline PASSED"
            exit 0
        elif echo "$output" | grep -qiE "failed"; then
            echo "$output"
            echo ""
            echo "Pipeline FAILED"
            exit 1
        elif echo "$output" | grep -qiE "canceled|cancelled"; then
            echo "$output"
            echo ""
            echo "Pipeline CANCELED"
            exit 1
        elif echo "$output" | grep -qiE "no pipeline"; then
            echo "  No pipeline found yet..."
        else
            # Still running — show compact status
            timestamp=$(date +%H:%M:%S)
            echo "  [$timestamp] Running..."
        fi
        sleep 30
    done

# ── Metrics Operations ────────────────────────────────────────────

# Trigger all metrics pipelines to refresh Grafana dashboard data
# Triggers: coverage, binary-size, design-drift, daily engineering metrics
[no-cd]
[group('metrics')]
metrics-refresh:
    #!/usr/bin/env bash
    set -euo pipefail
    just gitlab _check-auth
    echo "── Metrics Refresh ──"
    echo ""
    # METRICS_REFRESH=true tells CI templates to run coverage + binary-size
    # jobs even on API-triggered pipelines (normally skipped to avoid
    # redundant work on downstream verification triggers)
    echo "  Triggering metrics:daily (scripts)..."
    glab ci run -R vauchi/scripts -b main 2>/dev/null \
      && echo "    ✓ scripts pipeline created" \
      || echo "    ⚠ scripts trigger failed"
    for repo in core cli tui relay; do
        echo "  Triggering coverage + binary-size ($repo)..."
        glab ci run -R "vauchi/$repo" -b main --variables "METRICS_REFRESH:true" 2>/dev/null \
          && echo "    ✓ $repo pipeline created" \
          || echo "    ⚠ $repo trigger failed"
    done
    echo "  Triggering binary-size + design-drift (linux-gtk)..."
    glab ci run -R vauchi/linux-gtk -b main --variables "METRICS_REFRESH:true" 2>/dev/null \
      && echo "    ✓ linux-gtk pipeline created" \
      || echo "    ⚠ linux-gtk trigger failed"
    for repo in linux-qt macos windows web-demo; do
        echo "  Triggering design-drift ($repo)..."
        glab ci run -R "vauchi/$repo" -b main --variables "METRICS_REFRESH:true" 2>/dev/null \
          && echo "    ✓ $repo pipeline created" \
          || echo "    ⚠ $repo trigger failed"
    done
    echo ""
    echo "── Triggered 9 pipelines ──"
    echo ""
    echo "Dashboard: https://grafana.vauchi.app/d/vauchi-engineering-metrics/engineering-metrics"
    echo ""
    echo "Metrics populate after pipelines complete (~5-15 min)."
    echo "Run 'just gitlab metrics-status' to check progress."

# Show status of metrics-related CI jobs across repos
[no-cd]
[group('metrics')]
metrics-status:
    #!/usr/bin/env bash
    set -euo pipefail
    just gitlab _check-auth
    printf "%-12s %-12s %-12s %-12s %-12s\n" "REPO" "COVERAGE" "BINARY-SIZE" "DESIGN-DRIFT" "PIPELINE"
    printf "%-12s %-12s %-12s %-12s %-12s\n" "----------" "----------" "----------" "----------" "----------"
    for repo in core cli tui relay linux-gtk linux-qt macos windows web-demo; do
        pipeline_status=$(glab api "projects/vauchi%2F${repo}/pipelines?ref=main&per_page=1" 2>/dev/null \
          | python3 -c "import sys,json;d=json.load(sys.stdin);print(d[0]['status'] if d else 'none')" 2>/dev/null || echo "?")
        case "$repo" in
            core)     cov="yes" bs="yes"  dd="-"   ;;
            cli|tui)  cov="yes" bs="yes"  dd="yes"  ;;
            relay)    cov="yes" bs="yes"  dd="-"   ;;
            linux-gtk) cov="-" bs="yes"  dd="yes"  ;;
            linux-qt|macos|windows|web-demo) cov="-" bs="-" dd="yes" ;;
            *) cov="-" bs="-" dd="-" ;;
        esac
        printf "%-12s %-12s %-12s %-12s %-12s\n" "$repo" "$cov" "$bs" "$dd" "$pipeline_status"
    done
    echo ""
    echo "Dashboard: https://grafana.vauchi.app/d/vauchi-engineering-metrics/engineering-metrics"
