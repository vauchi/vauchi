<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

## Commit Conventions — Full Reference

### Branch Naming

`{type}/{short-description}` — types:

| Type | Use Case |
|------|----------|
| `feature/` | New functionality |
| `bugfix/` | Bug fixes |
| `refactor/` | Code restructuring |
| `tidy/` | Structural-only cleanup (Tidy First) |
| `investigation/` | Research/exploration |

### Recipes for Branch, Commit, Push, MR

| Action | Recipe |
|--------|--------|
| Create branch across repos | `just git branch feature/my-feature [repos]` |
| Interactive commit (multi-repo) | `just commit` |
| Non-interactive commit (single repo) | `just commit-repo <repo> <msg>` |
| Push all repos with commits ahead | `just git push-all` |
| Push without tests (fmt + clippy only) | `just git push-all skip-tests` |
| Create MR | `just gitlab mr-create [repo] [title]` |
| Approve MR | `just gitlab mr-approve <id> [repo]` |
| Merge MR | `just gitlab mr-merge <id> [repo]` |
| Pipeline status | `just gitlab pipeline-status [repo]` |
| Wait for pipeline | `just gitlab pipeline-wait [repo]` |

### Multi-Repo Branch Sync

When work spans repos, **keep branch names in sync**:

```bash
just git branch feature/my-feature features core docs
```

### MR Description Template

```markdown
## Summary
- Bullet points of changes

## Related MRs
- vauchi/other-repo!123 - Description

## Test Plan
- [ ] Tests pass
- [ ] Manual testing done

## Checklist
- [ ] Tidyings in separate `tidy:` commits (if any)
- [ ] Follows TDD
- [ ] Documentation updated
- [ ] Feature file updated (if applicable)
```

Each MR must list related MRs in **Related MRs** so reviewers see the full picture.
Use GitLab reference format: `{group}/{project}!{mr_number}`.

### Avoiding Unwanted Mentions

GitLab interprets `@word` in MR descriptions as user/group mentions — real people get notified.
Gherkin feature tags like `@duress`, `@hidden`, `@panic` **must** be escaped in MR text:

| Context | Safe? | Example |
|---------|-------|---------|
| Source code comments | Yes | `// Feature: foo.feature @duress` |
| MR description (raw) | **NO** | `@duress @hidden` → mentions users |
| MR description (backtick) | Yes | `` `@duress` `` `` `@hidden` `` |
| MR description (no prefix) | Yes | `duress, hidden, panic` |
