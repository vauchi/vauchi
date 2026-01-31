---
name: create-mr
description: Create GitLab merge requests for vauchi repos with proper templates and cross-repo linking
disable-model-invocation: true
---

Create GitLab merge requests for one or more vauchi repositories. $ARGUMENTS may specify which repos, or leave blank to auto-detect repos with branches ahead of main.

## Steps

1. **Detect repos needing MRs** — For each sub-repo and the root repo, check:
   - Current branch is not `main`
   - Has commits ahead of `origin/main`
   - No existing open MR for this branch (`glab mr list --source-branch <branch>`)

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

4. **Create the MR** using glab:
   ```bash
   cd <repo-dir> && glab mr create \
     --title "{type}: {description}" \
     --target-branch main \
     --description "..." \
     --yes
   ```

   IMPORTANT glab flags:
   - Use `--description` (NOT `--body`)
   - Use `--yes` to skip prompts
   - Use `--draft` if work is incomplete

5. **Cross-link MRs** — After all MRs are created, update each MR's description to include the actual MR numbers of related MRs using `glab mr update <id> --description "..."`.

6. **Report results** — Show a table with links to all created MRs.
