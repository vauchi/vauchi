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
[no-cd]
[script('bash')]
mr-create repo='':
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
    # Push branch if not tracking remote
    if ! git rev-parse --abbrev-ref "@{u}" &>/dev/null; then
        git push -u origin "$branch"
    fi
    glab mr create --fill --target-branch main --push -R "vauchi/$r"

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
    glab mr merge "{{id}}" -R "vauchi/$r"

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
    glab issue create --title "{{title}}" --no-editor -R "vauchi/$r" {{args}}

# Close an issue
[no-cd]
[script('bash')]
issue-close id repo='':
    just gitlab _check-auth
    set -euo pipefail
    source scripts/scripts/resolve-repo.sh
    r=$(resolve_gitlab_repo "{{repo}}")
    glab issue close "{{id}}" -R "vauchi/$r"
