---
name: dependent-mrs
description: Create tiered merge requests respecting the dependency graph (Tier 0 before Tier 1), or unblock downstream Draft MRs after upstream merges. Use instead of /create-mr when repos have dependency ordering (e.g. core before cli/desktop).
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Dependent MRs

Create and manage merge requests across repos respecting the dependency graph.
Two modes: **create** (make MRs in order) and **unblock** (check upstream, un-draft downstream).

## Dependency Graph

```
Tier 0 (no deps):     core, relay, _private, features, docs, scripts, locales
Tier 1 (needs core):  cli, tui, desktop, e2e
Tier 2 (auto — skip): ios, android (handled by CI trigger chain after core merge)
```

iOS/Android MRs are **never created manually** — core's release pipeline auto-triggers
binding distribution repos, which auto-create version-bump MRs with auto-merge.

## Mode: Create

`$ARGUMENTS`: list of repo names, e.g. `core cli desktop`

### Steps

1. **Parse repos** from arguments. If empty, auto-detect repos with branches ahead of main:
   ```bash
   WORKSPACE="$CLAUDE_PROJECT_DIR"
   for dir in core relay cli tui desktop e2e features docs scripts _private locales; do
     BRANCH=$(git -C "$WORKSPACE/$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
     if [ "$BRANCH" != "main" ] && [ -n "$BRANCH" ]; then
       AHEAD=$(git -C "$WORKSPACE/$dir" rev-list origin/main..HEAD --count 2>/dev/null)
       [ "$AHEAD" -gt 0 ] && echo "$dir ($BRANCH, $AHEAD commits)"
     fi
   done
   ```

2. **Classify into tiers** using the graph above. Warn if ios/android are listed (they're automated).

3. **Verify branch name consistency** — all repos MUST use the same branch name:
   ```bash
   # Collect branch names — if they differ, STOP and ask user
   for dir in <repos>; do
     git -C "$CLAUDE_PROJECT_DIR/$dir" rev-parse --abbrev-ref HEAD
   done
   ```

4. **Run pre-push validation** for each repo:
   - Rust repos: `cargo check --quiet --manifest-path "$CLAUDE_PROJECT_DIR/$dir/Cargo.toml"`
   - Check no `Cargo.toml` has non-main branch refs:
     ```bash
     grep -rn 'branch = ' "$CLAUDE_PROJECT_DIR/$dir/"**/Cargo.toml 2>/dev/null | grep -v 'main'
     ```

5. **Create MRs tier by tier:**

   **Tier 0 repos** — create as ready MRs:
   ```bash
   cd "$CLAUDE_PROJECT_DIR/$dir" && git push -u origin "$BRANCH" \
     -o merge_request.create \
     -o merge_request.target=main \
     -o merge_request.title="{type}: {description}" \
     -o merge_request.remove_source_branch
   ```

   **Tier 1 repos** — create as Draft MRs:
   ```bash
   cd "$CLAUDE_PROJECT_DIR/$dir" && git push -u origin "$BRANCH" \
     -o merge_request.create \
     -o merge_request.target=main \
     -o merge_request.title="Draft: {type}: {description}" \
     -o merge_request.remove_source_branch
   ```

6. **Generate MR descriptions** — each MR must include:
   ```markdown
   ## Summary
   - Bullet points of changes

   ## Related MRs
   - vauchi/core!XX - Core changes (merge first)
   - vauchi/cli!XX - CLI changes (Draft — waiting on core)

   ## Merge Order
   1. vauchi/core!XX (merge first)
   2. vauchi/cli!XX, vauchi/desktop!XX (after core merges to main)
   3. iOS/Android (automated by CI trigger chain)

   ## Test Plan
   - [ ] CI passes
   - [ ] Tests pass locally

   ## Checklist
   - [ ] Follows TDD (if code changes)
   - [ ] Documentation updated
   ```

7. **Report results** — show summary table:
   ```
   | Tier | Repo    | Branch      | MR                  | Status |
   |------|---------|-------------|---------------------|--------|
   | 0    | core    | feature/foo | vauchi/core!42      | Ready  |
   | 1    | cli     | feature/foo | vauchi/cli!15       | Draft  |
   | 1    | desktop | feature/foo | vauchi/desktop!28   | Draft  |
   ```

   Then print:
   ```
   Next steps:
   1. Review and merge vauchi/core!42
   2. Wait for CI + release pipeline (~5-10 min)
   3. Run `/dependent-mrs unblock` to un-draft downstream MRs
   ```

## Mode: Unblock

`$ARGUMENTS`: `unblock` (optionally followed by branch name if not on the branch)

### Steps

1. **Detect branch name** from current repo or arguments.

2. **Find all MRs for this branch** across repos using GitLab API:
   ```bash
   GITLAB_TOKEN="${GITLAB_TOKEN:-$(git config --global gitlab.token)}"
   BRANCH="<branch-name>"

   for project in core relay cli tui desktop e2e; do
     ENCODED=$(echo "vauchi/$project" | sed 's|/|%2F|g')
     curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
       "https://gitlab.com/api/v4/projects/$ENCODED/merge_requests?source_branch=$BRANCH&state=opened" \
       | jq -r '.[] | "\(.iid) \(.title) \(.web_url)"'
   done
   ```

   Also check for merged MRs (state=merged) to detect completed upstream:
   ```bash
   curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
     "https://gitlab.com/api/v4/projects/$ENCODED/merge_requests?source_branch=$BRANCH&state=merged" \
     | jq -r '.[] | "\(.iid) MERGED"'
   ```

3. **Check upstream status** — for each Tier 1 repo, verify its Tier 0 dependencies are merged.

4. **Un-draft ready MRs** — if all upstream MRs are merged, remove "Draft: " prefix:
   ```bash
   # Get current title
   TITLE=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
     "https://gitlab.com/api/v4/projects/$ENCODED/merge_requests/$MR_IID" \
     | jq -r '.title')

   # Remove "Draft: " prefix
   NEW_TITLE="${TITLE#Draft: }"

   curl -s --request PUT \
     --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
     --header "Content-Type: application/json" \
     --data "{\"title\": \"$NEW_TITLE\"}" \
     "https://gitlab.com/api/v4/projects/$ENCODED/merge_requests/$MR_IID"
   ```

5. **Report status:**
   ```
   | Repo    | MR                | Upstream | Action          |
   |---------|-------------------|----------|-----------------|
   | core    | vauchi/core!42    | N/A      | MERGED          |
   | cli     | vauchi/cli!15     | core: OK | Un-drafted      |
   | desktop | vauchi/desktop!28 | core: OK | Un-drafted      |

   All downstream MRs are now ready for review and merge.
   ```

   If upstream is NOT yet merged:
   ```
   | Repo    | MR                | Upstream       | Action          |
   |---------|-------------------|----------------|-----------------|
   | core    | vauchi/core!42    | N/A            | Still open      |
   | cli     | vauchi/cli!15     | core: PENDING  | Still draft     |

   Waiting on: vauchi/core!42 to be merged.
   ```

## Error Handling

- **No GITLAB_TOKEN**: Check `$GITLAB_TOKEN` env var. If missing, print:
  `"Set GITLAB_TOKEN to a GitLab personal access token with api scope"`
- **Branch name mismatch**: STOP and list the mismatched branches. Ask user to align.
- **Pre-push cargo check fails**: Skip that repo, report failure, continue with others.
- **API rate limit**: Wait and retry once. If still failing, report raw error.

## Prerequisites

- `GITLAB_TOKEN` env var with `api` scope (for unblock mode)
- `jq` installed (for API response parsing)
- Same branch name across all affected repos
