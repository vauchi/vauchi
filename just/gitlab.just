# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# GitLab operations: MRs, pipelines, issues
# Usage: just gitlab <recipe>

# ── Helpers ─────────────────────────────────────────────────────────

[private]
[no-cd]
[script('bash')]
_check-auth:
    if ! glab auth status &>/dev/null; then
        echo "ERROR: glab not authenticated — run 'glab auth login'"
        exit 1
    fi

# ── MR Operations ──────────────────────────────────────────────────

# List open merge requests
[no-cd]
[script('bash')]
mr-list repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab mr list -R "vauchi/$r"

# View merge request details
[no-cd]
[script('bash')]
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
[script('bash')]
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
    glab mr create --yes "${ARGS[@]}"

# Approve a merge request
[no-cd]
[script('bash')]
mr-approve id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab mr approve "{{id}}" -R "vauchi/$r"

# Merge a merge request
[no-cd]
[script('bash')]
mr-merge id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab mr merge "{{id}}" --yes -R "vauchi/$r"

# Close a merge request
[no-cd]
[script('bash')]
mr-close id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab mr close "{{id}}" -R "vauchi/$r"

# ── Pipeline Operations ────────────────────────────────────────────

# Show pipeline status for current branch
[no-cd]
[script('bash')]
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
[script('bash')]
pipeline-list repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab ci list -R "vauchi/$r"

# List jobs in a pipeline
[no-cd]
[script('bash')]
pipeline-jobs id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab ci list -R "vauchi/$r" --pipeline "{{id}}"

# View job log output
[no-cd]
[script('bash')]
pipeline-log job_id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab ci trace "{{job_id}}" -R "vauchi/$r"

# Retry a failed pipeline
[no-cd]
[script('bash')]
pipeline-retry id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab ci retry "{{id}}" -R "vauchi/$r"

# Cancel a running pipeline
[no-cd]
[script('bash')]
pipeline-cancel id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab ci delete "{{id}}" -R "vauchi/$r"

# ── Issue Operations ───────────────────────────────────────────────

# List open issues
[no-cd]
[script('bash')]
issue-list repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab issue list -R "vauchi/$r"

# View issue details
[no-cd]
[script('bash')]
issue-view id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab issue view "{{id}}" -R "vauchi/$r"

# Create an issue
[no-cd]
[script('bash')]
issue-create title repo='' *args='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab issue create --title "{{title}}" --no-editor --yes -R "vauchi/$r" {{args}}

# Close an issue
[no-cd]
[script('bash')]
issue-close id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab issue close "{{id}}" -R "vauchi/$r"

# ── Status & Wait ─────────────────────────────────────────────────

# Show MR status for current branch
[no-cd]
[script('bash')]
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
[script('bash')]
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
