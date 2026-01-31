<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

---
name: glab
description: GitLab CLI (glab) reference for creating MRs, managing issues, checking CI pipelines, and interacting with the GitLab API. Use when performing any GitLab operation.
---

# glab CLI Reference

Key difference from `gh` (GitHub CLI): flags use different names.

## Merge Requests

```bash
# Create MR (NOTE: --description/-d NOT --body, --yes/-y to skip prompts)
glab mr create --title "feat: ..." --target-branch main --description "..." --yes
glab mr create --fill --yes                # Auto-fill from commits, no prompts
glab mr create --fill --fill-commit-body --yes  # Fill body with commit bodies
glab mr create --draft --title "..." -b main -d "..." --yes  # Draft MR
glab mr create --push --title "..."        # Push + create in one step
glab mr create --label "bug,urgent" --assignee username --reviewer reviewer1

# List MRs
glab mr list                               # Open MRs in current project
glab mr list --all                         # All MRs (open + closed + merged)
glab mr list --source-branch branch-name   # Filter by source branch
glab mr list --assignee=@me               # MRs assigned to me
glab mr list --reviewer=@me               # MRs I'm reviewing
glab mr list --draft                       # Draft MRs only
glab mr list --merged                      # Merged MRs only
glab mr list --closed                      # Closed MRs only
glab mr list --label needs-review          # Filter by label
glab mr list --output json                 # JSON output

# View MR
glab mr view 42                            # View MR details
glab mr view                               # View MR for current branch
glab mr view 42 --comments                 # Include comments
glab mr view 42 --web                      # Open in browser
glab mr view 42 --output json              # JSON output

# Update MR
glab mr update 42 --title "new title"
glab mr update 42 --description "new desc"
glab mr update 42 --label "add-this"
glab mr update 42 --assignee user1,user2
glab mr update 42 --reviewer user1
glab mr update 42 --draft                  # Mark as draft
glab mr update 42 --ready                  # Mark as ready
glab mr update 42 --target-branch develop
glab mr update --unlabel "remove-this"
glab mr update --unassign                  # Remove all assignees

# Merge
glab mr merge 42                           # Merge (auto-merge enabled by default)
glab mr merge 42 --squash                  # Squash merge
glab mr merge 42 --rebase                  # Rebase before merge
glab mr merge 42 --remove-source-branch    # Delete branch after merge
glab mr merge 42 --yes                     # Skip confirmation

# Other MR operations
glab mr checkout 42                        # Check out MR locally
glab mr diff 42                            # View MR diff
glab mr note 42 -m "LGTM"                 # Add comment
glab mr rebase 42                          # Rebase source branch
glab mr approve 42                         # Approve MR
glab mr revoke 42                          # Revoke approval
glab mr close 42                           # Close MR
glab mr reopen 42                          # Reopen MR
```

## Issues

```bash
# Create issue (NOTE: --description/-d NOT --body, --title/-t required)
glab issue create --title "Bug: ..." --description "..." --label "bug" --yes
glab issue create --title "..." --assignee user1 --milestone "v1.0"

# List issues
glab issue list                            # Open issues
glab issue list --all                      # All issues
glab issue list --assignee=@me
glab issue list --label "bug"
glab issue list --milestone "v1.0"
glab issue list --output json

# View / update
glab issue view 42
glab issue view 42 --comments
glab issue note 42 -m "Working on this"
glab issue close 42
glab issue reopen 42
```

## CI/CD Pipelines

```bash
# View pipeline status
glab ci status                             # Current branch pipeline
glab ci status --branch main               # Specific branch
glab ci status --live                      # Real-time updates
glab ci status --compact                   # Compact view

# List pipelines
glab ci list                               # Recent pipelines
glab ci list --status=failed               # Failed pipelines only
glab ci list --output json

# Run pipelines
glab ci run                                # Run pipeline for current branch
glab ci run -b main                        # Run for specific branch
glab ci run --mr                           # Run MR pipeline
glab ci run --variables "KEY:value"        # With variables

# Jobs
glab ci trace                              # Trace job log (interactive)
glab ci trace 224356863                    # Trace specific job ID
glab ci trace lint                         # Trace job by name
glab ci trigger 224356863                  # Trigger manual job
glab ci view                               # Interactive pipeline viewer

# Lint CI config
glab ci lint                               # Validate .gitlab-ci.yml
```

## API (Direct GitLab API Access)

```bash
# Placeholders: :id :fullpath :repo :namespace :branch :user :username
glab api projects/:fullpath/releases
glab api projects/:id/merge_requests
glab api projects/:id/pipelines --paginate

# With fields
glab api projects/:id/merge_requests -f state=opened -f per_page=100

# GraphQL
glab api graphql -f query="query { currentUser { username } }"

# Comments on MR (alternative to mr view --comments)
glab api projects/:id/merge_requests/42/notes
```

## Cross-Repo Operations

```bash
# Use -R/--repo to target a different repo without cd
glab mr list -R vauchi/core
glab ci status -R vauchi/ios
glab mr view 42 -R vauchi/relay

# Or cd into the repo directory (glab reads git remote)
cd /path/to/repo && glab mr list
```

## Key Gotchas

- Use `--description` (or `-d`), NOT `--body` for MR/issue descriptions
- Use `--yes` (or `-y`) to skip interactive prompts
- Use `--fill` to auto-populate from commit messages
- `glab mr merge` has `--auto-merge` enabled by default
- `--output json` for machine-readable output (not `--json`)
- Use `glab ci view` for interactive TUI, `glab ci status` for quick check
