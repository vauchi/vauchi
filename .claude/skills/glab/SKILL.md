---
name: glab
description: GitLab CLI (glab) reference for creating MRs, managing issues, checking CI pipelines, and interacting with the GitLab API. Use when performing any GitLab operation.
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# glab CLI Reference

**glab is NOT gh.** Different flags, different behavior. This skill documents what actually works.

## CRITICAL: gh vs glab Flag Differences

| Operation | gh (GitHub) | glab (GitLab) |
|-----------|-------------|---------------|
| MR/PR description | `--body` | `--description` or `-d` |
| Skip prompts | `--yes` | `--yes` or `-y` |
| JSON output | `--json` | `--output json` |
| Squash merge | `--squash` | `--squash` |
| Delete branch | `--delete-branch` | `--remove-source-branch` |

**Never use `--body`. Always use `--description`.**

## CRITICAL: Repo Context

glab reads the git remote from the current working directory. Always `cd` into the correct repo before running glab commands:

```bash
# WRONG — runs against root repo remote
glab mr create --title "..."

# RIGHT — runs against the _private repo remote
cd _private && glab mr create --title "..."

# ALTERNATIVE — use -R flag (doesn't always work for create)
glab mr list -R vauchi/core
```

## Merge Requests

### Create

```bash
# Standard MR creation (ALWAYS use --description, NEVER --body)
cd <repo-dir> && glab mr create \
  --title "feat: Short description" \
  --target-branch main \
  --description "$(cat <<'EOF'
## Summary
- Changes

## Test Plan
- [ ] CI passes
EOF
)" \
  --yes

# Auto-fill from commits (no description needed)
glab mr create --fill --yes
glab mr create --fill --fill-commit-body --yes

# Draft MR
glab mr create --draft --title "..." -b main -d "..." --yes

# Push + create in one step
glab mr create --push --title "..."

# With metadata
glab mr create --label "bug,urgent" --assignee username --reviewer reviewer1
```

### View / List / Update

```bash
# View
glab mr view 42                            # View MR details
glab mr view                               # View MR for current branch
glab mr view 42 --comments                 # Include comments
glab mr view 42 --output json              # JSON output

# List
glab mr list                               # Open MRs
glab mr list --source-branch branch-name   # By source branch
glab mr list --assignee=@me               # My MRs
glab mr list --output json                 # JSON output

# Update (ALWAYS --description, NEVER --body)
glab mr update 42 --description "new desc"
glab mr update 42 --title "new title"
glab mr update 42 --draft                  # Mark as draft
glab mr update 42 --ready                  # Mark as ready
```

### Merge

```bash
# Merge (auto-merge is enabled by default)
glab mr merge 42 --yes
glab mr merge 42 --squash --yes                   # Squash merge
glab mr merge 42 --squash --remove-source-branch --yes  # Squash + delete branch
glab mr merge 42 --rebase --yes                   # Rebase before merge
```

**Wrong flags:** `--squash-before-merge` does NOT exist. Use `--squash`.

### Other Operations

```bash
glab mr checkout 42                        # Check out MR locally
glab mr diff 42                            # View MR diff
glab mr note 42 -m "LGTM"                 # Add comment
glab mr rebase 42                          # Rebase source branch
glab mr approve 42                         # Approve MR
glab mr close 42                           # Close MR
```

## CI/CD Pipelines

### Check Status

```bash
glab ci status                             # Current branch pipeline
glab ci status --branch main               # Specific branch
glab ci status --live                      # Real-time updates
```

### Read Job Logs

**`glab ci trace` is unreliable** — it requires a numeric job ID and is interactive. Use the API instead:

```bash
# Step 1: Get pipeline ID from glab ci status output or MR view
# Step 2: Get jobs for that pipeline
glab api projects/:fullpath/pipelines/<PIPELINE_ID>/jobs

# Step 3: Get job trace (log output)
glab api projects/:fullpath/jobs/<JOB_ID>/trace
```

Pipe through `tail` or parse with python for readability:

```bash
glab api projects/:fullpath/jobs/<JOB_ID>/trace 2>&1 | tail -30
```

### Trigger / Retry Pipelines

**Branch pipelines** (jobs with `rules: if: $CI_COMMIT_BRANCH`):
```bash
glab ci run                                # Current branch
glab ci run -b main                        # Specific branch
```

**MR pipelines** (jobs with `rules: if: $CI_PIPELINE_SOURCE == "merge_request_event"`):

`glab ci run` creates BRANCH pipelines, NOT MR pipelines. MR-only jobs won't run.

To trigger an MR pipeline, push a new commit (even empty):
```bash
git commit --allow-empty -m "chore: Trigger CI" && git push
```

To retry a failed MR pipeline:
```bash
# Get the pipeline ID from glab ci status
glab api --method POST projects/:fullpath/pipelines/<PIPELINE_ID>/retry
```

### Lint CI Config

```bash
glab ci lint                               # Validate .gitlab-ci.yml
```

## Issues

```bash
# Create (--description NOT --body)
glab issue create --title "Bug: ..." --description "..." --label "bug" --yes

# List
glab issue list
glab issue list --assignee=@me
glab issue list --label "bug"

# View / comment
glab issue view 42
glab issue view 42 --comments
glab issue note 42 -m "Working on this"
glab issue close 42
```

## API (Direct Access)

```bash
# glab auto-resolves :fullpath and :id from current repo git remote
glab api projects/:fullpath/releases
glab api projects/:id/merge_requests
glab api projects/:id/pipelines --paginate

# With fields
glab api projects/:id/merge_requests -f state=opened -f per_page=100

# POST requests
glab api --method POST projects/:id/pipelines/<PIPELINE_ID>/retry

# GraphQL
glab api graphql -f query="query { currentUser { username } }"

# Cross-repo API (URL-encode the path)
glab api projects/vauchi%2Fcore/pipelines
glab api projects/vauchi%2Fprivate/merge_requests
```

## Cross-Repo Operations

```bash
# Use -R flag for read operations
glab mr list -R vauchi/core
glab ci status -R vauchi/ios
glab mr view 42 -R vauchi/relay

# For write operations (create, merge), cd into the repo
cd core && glab mr create --title "..." --yes
cd _private && glab mr merge 32 --yes
```

## Gotchas Summary

1. **`--description` NOT `--body`** — Every time, always
2. **`--squash` NOT `--squash-before-merge`** — Flag doesn't exist
3. **`cd` into repo before glab** — glab reads git remote from cwd
4. **`glab ci run` = branch pipeline** — Won't trigger MR-only jobs
5. **`glab ci trace` needs job ID** — Use API for reliable log reading
6. **`--output json` NOT `--json`** — glab uses `--output` flag
7. **`--yes` to skip prompts** — Always add for non-interactive use
8. **`--no-editor` for create** — Prevents editor popup when description provided
