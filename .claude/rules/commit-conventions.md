---
apply: always
---

## Commit Conventions

- **Format**: `{type}: {Short description}` — types: `feat`, `fix`, `refactor`, `tidy`, `docs`, `test`, `chore`
- **Co-author**: `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- **Atomic**: One logical change per commit. TDD order: `tidy:` (optional) → `test:` → `feat:`/`fix:`
- **Branches**: `just git branch <name> [repos]` — `feature/`, `bugfix/`, `refactor/`, `tidy/`, `investigation/`
- **Committing**: `just commit` (interactive, multi-repo) or `just commit-repo <repo> <msg>` (automation)
- **MRs**: `just gitlab mr-create [repo]` — never raw `glab`. `just gitlab mr-approve`, `just gitlab mr-merge`.
- **Pre-MR rebase**: Always `git fetch origin main && git rebase origin/main` before creating an MR. GitLab requires fast-forward merges — branches behind main can't merge.
- **Pushing**: `just git push-all` (runs checks). Never raw `git push` to multiple repos.
- **No direct push to main**: Merge via MR only. Sync branch names across repos.
- **No `@` in MR descriptions**: GitLab interprets `@word` as user/group mentions. In MR descriptions, wrap Gherkin tags in backticks (`` `@duress` ``) or omit the `@` prefix entirely. Source code comments are fine.

MR template, multi-repo sync examples: `.claude/docs/commit-conventions.md`
