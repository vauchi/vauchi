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

### WIP, Resume & Worktree Recipes

| Action | Recipe |
|--------|--------|
| Save WIP checkpoint commits | `just git wip [msg] [repos]` |
| Undo WIP commits (soft reset) | `just git wip-undo [repos]` |
| Switch to main (with save options) | `just git main` / `just git main wip` |
| Resume a branch (undo WIP on return) | `just git resume <branch> [repos]` |
| Show stale branches | `just git stale-branches [days]` |
| Create parallel worktree | `just worktree create <branch> [repos]` |
| List worktrees | `just worktree list` |
| Remove worktree | `just worktree remove <branch>` |
| Remove worktree (non-interactive) | `just worktree remove-force <branch>` |

### Multi-Repo Branch Sync

When work spans repos, **keep branch names in sync**:

```bash
just git branch feature/my-feature features core docs
```

### Context Switching Safely

When you need to switch branches mid-work, prefer WIP commits over stashing:

```bash
# Save current work as WIP commits (safer than stash)
just git wip "halfway through exchange refactor"

# Switch to main to fix something urgent
just git main wip        # auto-WIP-commits and switches to main

# Return to your branch — WIP commits are auto-undone
just git resume feature/exchange-refactor
```

For truly parallel work (working on two branches at once), use worktrees:

```bash
# Create a parallel checkout for the bugfix
just worktree create bugfix/crash-fix core cli

# Work in the worktree (your main checkout is untouched)
cd .worktrees/bugfix/crash-fix/core && cargo test

# Clean up when done
just worktree remove bugfix/crash-fix
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

### Plan-Task Trailers

Standard git trailers that link commits to plan tasks and problem records.

**Format:**

```
Plan-Task: <slug>#<task-number>
Problem: <slug>
```

**Rules:**

- `Plan-Task:` is a standard git trailer — one per line, multiple allowed
- Slug matches plan filenames by substring (date prefix stripped): `2026-02-26-sp24-desktop-phone-exchange.plan.md` → slug `sp24-desktop-exchange`
- `#N` references the task number (list item order in `.plan.md`)
- Optional `Problem:` trailer for direct problem record references
- Trailers are **advisory, not enforced** — missing trailers don't block merge or push
- Pre-push hook shows a soft warning on `feature/*` branches for commits without trailers

**How CI uses trailers:**

- After merge to main, CI parses `Plan-Task:` trailers and creates an MR updating referenced plan tasks to `[x]`
- drift-detector inference fills gaps for commits without trailers
- All updates go through MR review — never direct to main

**Example:**

```
feat: implement BLE transport for desktop exchange

Implement connection handling and data transfer for
desktop-phone exchange over BLE.

Plan-Task: sp24-desktop-exchange#4
Plan-Task: sp24-desktop-exchange#5
Problem: sp24-desktop-exchange
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```
