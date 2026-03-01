---
apply: always
---

## Commit Conventions

- **Format**: `{type}: {Short description}` — types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`
- **Co-author line**: `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- **Atomic commits**: One logical change per commit. If N behaviors, that's N commits.
- **TDD order**: `test:` commit before `feat:`/`fix:` commit
- **No direct push to main**: All repos have protected `main` — merge via MR only, force push disabled

## Branch Naming

`{type}/{short-description}` — types:

| Type | Use Case |
|------|----------|
| `feature/` | New functionality |
| `bugfix/` | Bug fixes |
| `refactor/` | Code restructuring |
| `investigation/` | Research/exploration |

## Multi-Repo Branch Sync

When work spans repos, **keep branch names in sync**:

```bash
git -C features checkout -b feature/my-feature
git -C core checkout -b feature/my-feature
git -C docs checkout -b feature/my-feature
```

## MR Description Template

```markdown
## Summary
- Bullet points of changes

## Related MRs
- vauchi/other-repo!123 - Description

## Test Plan
- [ ] Tests pass
- [ ] Manual testing done

## Checklist
- [ ] Follows TDD
- [ ] Documentation updated
- [ ] Feature file updated (if applicable)
```

Each MR must list related MRs in **Related MRs** so reviewers see the full picture.
Use GitLab reference format: `{group}/{project}!{mr_number}`.
