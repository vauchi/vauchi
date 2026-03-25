# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# GitLab operations: MRs, pipelines, issues
# Usage: just gitlab <recipe>

# Metrics repo groups (non-overlapping — each repo in exactly one group)
metrics_coverage_repos := "core cli tui relay ohttp-relay"
metrics_binary_drift_repos := "linux-gtk"
metrics_drift_only_repos := "linux-qt macos windows web-demo"
metrics_all_repos := "core cli tui relay ohttp-relay linux-gtk linux-qt macos windows web-demo"

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
# After all MRs exist, auto-populates Related MRs and marks downstream as Draft.
#
# Usage: just gitlab mr-create-all                    # auto-fill title from commits
#        just gitlab mr-create-all "feat: my feature" # custom title
[no-cd]
[script]
mr-create-all title='':
    just gitlab _check-auth
    source scripts/scripts/output-helpers.sh
    source scripts/scripts/resolve-repo.sh
    source scripts/scripts/for-each-repo.sh
    set -euo pipefail
    timer_start

    # ── Dependency graph for Draft detection ──────────────────────────
    # Tier 0 = upstream (no vauchi git deps). If tier 0 has an MR,
    # everything downstream is Draft. Derived from Cargo.toml git deps.
    UPSTREAM_REPOS="core"
    # Repos that depend on core via git (tier 1+)
    DOWNSTREAM_OF_CORE="cli tui relay linux-gtk e2e"

    created=()
    updated=()
    uptodate=()
    failed=()

    # Collect MR IIDs + labels for the cross-reference pass
    # Format: "label:gl_name:iid" per entry
    mr_registry=()

    _process_repo() {
        local label="$1" dir="$2"
        branch=$(git -C "$dir" branch --show-current 2>/dev/null)

        # Skip repos on main or detached HEAD
        [[ "$branch" == "main" || -z "$branch" ]] && return 0

        # Skip repos with no commits ahead
        ahead=$(git -C "$dir" rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
        [[ "$ahead" -eq 0 ]] && return 0

        echo ""
        echo "── $label ($branch, $ahead commits) ──"

        gl_name=$(_dir_to_gitlab_name "$label")

        # Check for existing MR
        existing_iid=$(glab api "projects/vauchi%2F${gl_name}/merge_requests?state=opened&source_branch=${branch}&per_page=1" 2>/dev/null \
          | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['iid'] if d else '')" 2>/dev/null || true)
        has_mr=$([[ -n "$existing_iid" ]] && echo "yes" || echo "no")

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
                return 0
            fi
            rebased=yes
        fi

        export SKIP_TESTS=1

        if [[ "$has_mr" == "yes" ]]; then
            # MR exists — force-push if rebased, otherwise up-to-date
            if [[ "$rebased" == "yes" ]]; then
                echo "  MR exists (!${existing_iid}) — force-pushing rebased branch..."
                if git -C "$dir" push --force-with-lease origin "$branch" 2>&1 | sed 's/^/  /'; then
                    updated+=("$label")
                else
                    echo "  Force-push failed"
                    failed+=("$label")
                    return 0
                fi
            else
                echo "  MR exists (!${existing_iid}), already up to date"
                uptodate+=("$label")
            fi
            mr_registry+=("${label}:${gl_name}:${existing_iid}")
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
                # Fetch the new MR IID
                new_iid=$(glab api "projects/vauchi%2F${gl_name}/merge_requests?state=opened&source_branch=${branch}&per_page=1" 2>/dev/null \
                  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['iid'] if d else '')" 2>/dev/null || true)
                [[ -n "$new_iid" ]] && mr_registry+=("${label}:${gl_name}:${new_iid}")
            else
                echo "  Push failed"
                failed+=("$label")
            fi
        fi
    }
    for_each_repo --no-root _process_repo

    # ── Pass 2: Cross-reference Related MRs + Draft downstream ────────
    if [[ ${#mr_registry[@]} -gt 1 ]]; then
        echo ""
        echo "── Cross-referencing ${#mr_registry[@]} MRs ──"

        # Determine if upstream (core) has an MR — if so, downstream should be Draft
        upstream_has_mr=false
        for entry in "${mr_registry[@]}"; do
            entry_label="${entry%%:*}"
            if echo " $UPSTREAM_REPOS " | grep -q " $entry_label "; then
                upstream_has_mr=true
                break
            fi
        done

        for entry in "${mr_registry[@]}"; do
            IFS=: read -r elabel egl eiid <<< "$entry"

            # Build description: commits + related MRs
            commits=$(git -C "$elabel" log origin/main..HEAD --reverse --format="- %s" 2>/dev/null || true)
            files=$(git -C "$elabel" diff --stat origin/main..HEAD 2>/dev/null | tail -1 | sed 's/^ //' || true)

            # Related MRs = all except self
            other_mrs=""
            for other in "${mr_registry[@]}"; do
                IFS=: read -r ol ogl oiid <<< "$other"
                [[ "$ol" == "$elabel" ]] && continue
                other_mrs="${other_mrs}- vauchi/${ogl}!${oiid}\n"
            done

            desc="## Summary\n\n${commits}\n\n## Related MRs\n\n${other_mrs}\n---\n_${files}_"

            # Mark downstream repos as Draft if upstream has an MR
            is_downstream=false
            if $upstream_has_mr && echo " $DOWNSTREAM_OF_CORE " | grep -q " $elabel "; then
                is_downstream=true
            fi

            update_args=(-f "description=${desc}")
            if $is_downstream; then
                # Get current title and prepend Draft: if not already
                current_title=$(glab api "projects/vauchi%2F${egl}/merge_requests/${eiid}" 2>/dev/null \
                  | python3 -c "import sys,json; print(json.load(sys.stdin).get('title',''))" 2>/dev/null || true)
                if [[ -n "$current_title" && "$current_title" != Draft:* ]]; then
                    update_args+=(-f "title=Draft: ${current_title}")
                fi
            fi

            glab api -X PUT "projects/vauchi%2F${egl}/merge_requests/${eiid}" "${update_args[@]}" >/dev/null 2>&1 || true

            if $is_downstream; then
                printf "  ✓ %s !%s — Related MRs + Draft\n" "$elabel" "$eiid"
            else
                printf "  ✓ %s !%s — Related MRs\n" "$elabel" "$eiid"
            fi
        done
    fi

    elapsed=$(timer_elapsed)
    echo ""
    echo "── Summary (${elapsed}s) ──"
    [[ ${#created[@]}  -gt 0 ]] && printf "  ${GREEN}✓${NC} Created  (%d):  %s\n" "${#created[@]}" "${created[*]}"
    [[ ${#updated[@]}  -gt 0 ]] && printf "  ${GREEN}✓${NC} Updated  (%d):  %s\n" "${#updated[@]}" "${updated[*]}"
    [[ ${#uptodate[@]} -gt 0 ]] && printf "  ${DIM}·${NC} Up-to-date (%d): %s\n" "${#uptodate[@]}" "${uptodate[*]}"
    [[ ${#failed[@]}   -gt 0 ]] && printf "  ${RED}✗${NC} Failed   (%d):   %s\n" "${#failed[@]}" "${failed[*]}"
    if [[ ${#mr_registry[@]} -gt 1 ]]; then
        printf "  ${GREEN}✓${NC} Cross-referenced %d MRs\n" "${#mr_registry[@]}"
    fi
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
    glab ci cancel "{{id}}" -R "vauchi/$r"

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
    for repo in {{ metrics_coverage_repos }}; do
        echo "  Triggering coverage + binary-size ($repo)..."
        glab ci run -R "vauchi/$repo" -b main --variables "METRICS_REFRESH:true" 2>/dev/null \
          && echo "    ✓ $repo pipeline created" \
          || echo "    ⚠ $repo trigger failed"
    done
    for repo in {{ metrics_binary_drift_repos }}; do
        echo "  Triggering binary-size + design-drift ($repo)..."
        glab ci run -R "vauchi/$repo" -b main --variables "METRICS_REFRESH:true" 2>/dev/null \
          && echo "    ✓ $repo pipeline created" \
          || echo "    ⚠ $repo trigger failed"
    done
    for repo in {{ metrics_drift_only_repos }}; do
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
    for repo in {{ metrics_all_repos }}; do
        pipeline_status=$(glab api "projects/vauchi%2F${repo}/pipelines?ref=main&per_page=1" 2>/dev/null \
          | python3 -c "import sys,json;d=json.load(sys.stdin);print(d[0]['status'] if d else 'none')" 2>/dev/null || echo "?")
        case "$repo" in
            core)     cov="yes" bs="yes"  dd="-"   ;;
            cli|tui)  cov="yes" bs="yes"  dd="yes"  ;;
            relay)    cov="yes" bs="yes"  dd="-"   ;;
            ohttp-relay) cov="yes" bs="-"  dd="-"   ;;
            linux-gtk) cov="-" bs="yes"  dd="yes"  ;;
            linux-qt|macos|windows|web-demo) cov="-" bs="-" dd="yes" ;;
            *) cov="-" bs="-" dd="-" ;;
        esac
        printf "%-12s %-12s %-12s %-12s %-12s\n" "$repo" "$cov" "$bs" "$dd" "$pipeline_status"
    done
    echo ""
    echo "Dashboard: https://grafana.vauchi.app/d/vauchi-engineering-metrics/engineering-metrics"

# ── Package Registry ──────────────────────────────────────────────

# Show latest published binding versions across all distribution channels
# Usage: just gitlab published
[no-cd]
[script]
published:
    just gitlab _check-auth
    set -euo pipefail

    # Workspace root: just sets this to the directory containing the justfile
    WS="${JUST_INVOCATION_DIRECTORY:-$(dirname "$(dirname "$0")")}"
    # Fallback: walk up from cwd until we find the top-level justfile
    if [[ ! -f "$WS/justfile" ]]; then
        WS="$(pwd)"
        while [[ "$WS" != "/" && ! -f "$WS/justfile" ]]; do WS="$(dirname "$WS")"; done
    fi

    printf "\n%-22s %-22s %-22s %s\n" "Channel" "Latest" "Previous" "Published"
    printf "%-22s %-22s %-22s %s\n" "─────────────────────" "─────────────────────" "─────────────────────" "──────────────────"

    # Helper: query GitLab package registry (latest 2 by creation date, descending)
    query_packages() {
        local project="$1" label="$2"
        glab api "projects/${project}/packages?per_page=2&sort=desc&order_by=created_at" 2>/dev/null \
        | python3 -c "
    import sys,json
    pkgs=json.load(sys.stdin)[:2]
    label='$label'
    if len(pkgs)>=2: print(f'{label:22s} {pkgs[0][\"version\"]:22s} {pkgs[1][\"version\"]:22s} {pkgs[0][\"created_at\"][:16]}')
    elif len(pkgs)==1: print(f'{label:22s} {pkgs[0][\"version\"]:22s} {\"—\":22s} {pkgs[0][\"created_at\"][:16]}')
    else: print(f'{label:22s} {\"(none)\":22s}')
    " 2>/dev/null || printf "%-22s (query failed)\n" "$label"
    }

    query_packages "vauchi%2Fcore"                     "core (generic)"
    query_packages "vauchi%2Fvauchi-platform-kotlin"    "kotlin (maven)"

    # Swift SPM (uses git tags, not package registry)
    git -C "$WS/vauchi-platform-swift" ls-remote --tags origin 2>/dev/null \
    | sed 's|.*refs/tags/||' | grep -E '^v[0-9]' | sort -V | tail -2 \
    | python3 -c "
    import sys
    tags=[l.strip() for l in sys.stdin if l.strip()]
    if len(tags)>=2: print(f\"{'swift (spm tags)':22s} {tags[1]:22s} {tags[0]:22s}\")
    elif len(tags)==1: print(f\"{'swift (spm tags)':22s} {tags[0]:22s}\")
    else: print(f\"{'swift (spm tags)':22s} {'(none)':22s}\")
    " 2>/dev/null || printf "%-22s (query failed)\n" "swift (spm tags)"

    # Local versions (source vs consumer) — use git show to avoid branch drift
    printf "%-22s %-22s\n" "──────────────────────" "──────────────────────"
    CARGO_VER=$(git -C "$WS/core" show origin/main:Cargo.toml 2>/dev/null | grep '^version' | head -1 | sed 's/.*"\(.*\)"/\1/' || echo "?")
    printf "%-22s %-22s\n" "core (Cargo.toml)" "$CARGO_VER"
    ANDROID_VER=$(git -C "$WS/android" show origin/main:app/build.gradle.kts 2>/dev/null | grep -E 'vauchi-platform:' | grep -v '//' | sed 's/.*vauchi-platform:\(.*\)").*/\1/' | head -1 || echo "?")
    printf "%-22s %-22s\n" "android (consumer)" "$ANDROID_VER"
    # iOS uses SPM git tags directly — consumer version is the swift tag
    IOS_VER=$(git -C "$WS/ios" show origin/main:Vauchi.xcodeproj/project.pbxproj 2>/dev/null | grep -E 'version.*=.*"[0-9]' | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "(uses spm tag)")
    printf "%-22s %-22s\n" "ios (consumer)" "$IOS_VER"
    echo ""
