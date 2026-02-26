---
apply: always
---

## Commit Conventions

- **Format**: `{type}: {Short description}` — types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`
- **Co-author line**: `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- **Atomic commits**: One logical change per commit. If N behaviors, that's N commits.
- **TDD order**: `test:` commit before `feat:`/`fix:` commit
- **No direct push to main**: All repos have protected `main` — merge via MR only
- **Branch naming**: `{type}/{short-description}` (e.g., `feature/nfc-active`, `bugfix/relay-timeout`)
