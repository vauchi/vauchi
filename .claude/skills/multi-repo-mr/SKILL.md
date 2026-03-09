---
name: multi-repo-mr
description: Push branches and create MRs across multiple vauchi repos in parallel with CI validation. Same as /create-mr but with explicit parallel sub-agent dispatch. Prefer /create-mr for most cases or /dependent-mrs for tiered ordering.
disable-model-invocation: true
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

Push branches and create merge requests across multiple vauchi repositories. $ARGUMENTS may list specific repos, or leave blank to auto-detect all repos with branches ahead of main.

## Constraints (MANDATORY)

- **MR creation**: Use `just gitlab mr-create [repo]` — handles push + MR creation with correct options
- **Directory safety**: Always use `git -C <absolute-path>` — NEVER cd without verifying
- **Branch refs**: Keep all `Cargo.toml` branch refs pointing to `main` — NEVER change to feature branches
- **Pre-push check**: Run `just check <repo>` in Rust repos before pushing

## Steps

1. **Detect repos with work to push** — For each sub-repo directory under the workspace root:
   ```bash
   WORKSPACE="$CLAUDE_PROJECT_DIR"
   for dir in core relay cli tui linux-gtk android ios e2e features docs scripts; do
     git -C "$WORKSPACE/$dir" rev-parse --abbrev-ref HEAD 2>/dev/null
     git -C "$WORKSPACE/$dir" log origin/main..HEAD --oneline 2>/dev/null
   done
   ```
   Also check the root repo itself.

2. **Validate before pushing** — For each repo with changes:
   - Verify no `Cargo.toml` files have non-main branch refs:
     ```bash
     grep -rn 'branch = ' "$CLAUDE_PROJECT_DIR/$dir/Cargo.toml" 2>/dev/null | grep -v 'main'
     ```
   - For Rust repos, run checks:
     ```bash
     just check $dir
     ```

3. **Push and create MRs in parallel** — Use Task sub-agents (one per repo) to:
   - Push with MR creation:
     ```bash
     git -C "$CLAUDE_PROJECT_DIR/$dir" push -u origin <branch> \
       -o merge_request.create \
       -o merge_request.target=main \
       -o merge_request.title="{type}: {description}" \
       -o merge_request.remove_source_branch
     ```
   - Each sub-agent reports: repo name, branch, MR URL, push status

4. **Cross-link related MRs** — After all MRs are created, list them in each MR's description under `## Related MRs` using format: `vauchi/<repo>!<number> - Description`

5. **Report results** — Show a summary table:

   | Repo | Branch | MR | Pipeline |
   |------|--------|----|----------|
   | core | feature/x | vauchi/core!42 | pending |
   | cli  | feature/x | vauchi/cli!15 | pending |

## Error Handling

- If a push fails (e.g., HTTPS auth, branch already exists), report the error and continue with other repos
- If cargo check fails, do NOT push that repo — report the failure and skip it
- If a branch ref check finds non-main refs, STOP and ask the user before proceeding
