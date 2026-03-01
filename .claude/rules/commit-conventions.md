---
apply: always
---

## Commit Conventions

- **Format**: `{type}: {Short description}` — types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`
- **Co-author**: `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- **Atomic**: One logical change per commit. TDD order: `test:` before `feat:`/`fix:`
- **Branches**: `{type}/{short-description}` — `feature/`, `bugfix/`, `refactor/`, `investigation/`
- **No direct push to main**: Merge via MR only. Sync branch names across repos.

MR template, multi-repo sync examples: `.claude/docs/commit-conventions.md`
