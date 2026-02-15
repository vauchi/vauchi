---
name: create-mr
description: Create GitLab merge requests for vauchi repos with proper templates and cross-repo linking
disable-model-invocation: true
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

Create GitLab merge requests for one or more vauchi repositories. $ARGUMENTS may specify which repos, or leave blank to auto-detect repos with branches ahead of main.

## Steps

1. **Detect repos needing MRs** — For each sub-repo and the root repo, check:
   - Current branch is not `main`
   - Has commits ahead of `origin/main`
   - No existing open MR for this branch (check GitLab web UI or API)

2. **For each repo needing an MR:**
   - Read the full diff: `git -C <dir> diff origin/main..HEAD`
   - Read the commit log: `git -C <dir> log origin/main..HEAD --oneline`
   - Ensure branch is pushed: `git -C <dir> push -u origin <branch>`

3. **Generate MR description** using this template:

   ```
   ## Summary
   - Bullet points of changes

   ## Related MRs
   - vauchi/<repo>!<number> - Description

   ## Test Plan
   - [ ] CI passes
   - [ ] Tests pass locally

   ## Checklist
   - [ ] Follows TDD (if code changes)
   - [ ] Documentation updated
   - [ ] Feature file updated (if applicable)
   ```

4. **Create the MR** using git push options:
   ```bash
   cd <repo-dir> && git push -u origin <branch> \
     -o merge_request.create \
     -o merge_request.target=main \
     -o merge_request.title="{type}: {description}" \
     -o merge_request.description="..."
   ```

   Useful push options:
   - `-o merge_request.draft` if work is incomplete
   - `-o merge_request.label="label"` to add labels
   - `-o merge_request.remove_source_branch` to auto-delete branch on merge

5. **Cross-link MRs** — After all MRs are created, update each MR's description via the GitLab web UI or API to include the actual MR numbers of related MRs.

6. **Report results** — Show a table with links to all created MRs.

## Pre-Requisite

Before creating MRs, run `/pre-mr-check` to ensure all CI checks pass locally. This prevents failed pipelines and wasted CI time.
