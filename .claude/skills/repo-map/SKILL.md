---
name: repo-map
description: Multi-repo file location map and common pitfalls. Use when locating files, running git commands, or committing across the vauchi workspace.
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi Multi-Repo File Location Map

Every sub-directory is its own git repo. Always use `git -C <dir>` to target the correct one.

## Repo → Content Mapping

| Content | Repo Directory | Git Remote |
|---------|---------------|------------|
| Problem records, investigations, planning | `_private/` | `vauchi/private` |
| Problem workflow doc | `_private/docs/2026-01-23-problem-to-solution-flow.md` | `vauchi/private` |
| Internal roadmap, proposals, strategy | `_private/docs/planning/` | `vauchi/private` |
| Infra configs, deploy secrets | `_private/infra/` | `vauchi/private` |
| Public architecture docs, guides | `docs/` | `vauchi/docs` |
| Gherkin feature specs | `features/` | `vauchi/features` |
| Rust core + mobile bindings | `core/` | `vauchi/core` |
| Relay server | `relay/` | `vauchi/relay` |
| CLI app | `cli/` | `vauchi/cli` |
| TUI app | `tui/` | `vauchi/tui` |
| Desktop (Tauri + SolidJS) | `desktop/` | `vauchi/desktop` |
| iOS app | `ios/` | `vauchi/ios` |
| Android app | `android/` | `vauchi/android` |
| E2E tests | `e2e/` | `vauchi/e2e` |
| Website / landing page | `website/` | `vauchi/website` |
| Shared locales (canonical) | `locales/` | `vauchi/locales` |
| Justfile, CI, workspace config | root | `vauchi/vauchi` |

## Common Pitfalls

### 1. `docs/` vs `_private/docs/` — NOT the same repo

- `docs/` is a **separate public sub-repo** (`vauchi/docs`) for architecture guides
- `_private/docs/` is inside the **private sub-repo** (`vauchi/private`) for problem records, planning, internal strategy
- Problem records live in `_private/docs/problems/`
- The problem workflow doc is at `_private/docs/2026-01-23-problem-to-solution-flow.md`

### 2. Git commands must target the correct repo

```bash
# WRONG — runs in root repo, _private/ changes won't show
git status

# RIGHT — runs in the _private repo
git -C _private status
```

When committing changes in a sub-repo:
```bash
git -C _private checkout -b investigation/my-branch
git -C _private add docs/problems/...
git -C _private commit -m "docs: ..."
git -C _private push -u origin investigation/my-branch
```

### 3. MR creation targets the sub-repo remote

```bash
# Must cd into the repo for glab to detect the correct remote
cd _private && glab mr create --title "..." --target-branch main --description "..." --yes
```

### 4. glab is NOT gh

- Use `--description` (NOT `--body`) for MR/issue descriptions
- Use `--yes` to skip prompts
- Use `/create-mr` skill for the full MR workflow

### 5. Branch names should match across repos

When work spans multiple repos, use the same branch name everywhere:
```bash
git -C _private checkout -b feature/my-feature
git -C core checkout -b feature/my-feature
git -C features checkout -b feature/my-feature
```

## Quick Reference: Where Does This File Go?

| File Type | Location |
|-----------|----------|
| Problem record README | `_private/docs/problems/YYYY-MM-DD-slug/README.md` |
| Investigation artifact | `_private/docs/problems/YYYY-MM-DD-slug/investigation.md` |
| Implementation plan | `_private/docs/problems/YYYY-MM-DD-slug/implementation-plan.md` |
| Retrospective | `_private/docs/problems/YYYY-MM-DD-slug/retrospective.md` |
| Planning proposal | `_private/docs/planning/proposals/YYYY-MM-DD-name.md` |
| Planning todo | `_private/docs/planning/todo/YYYY-MM-DD-name.md` |
| Public architecture doc | `docs/YYYY-MM-DD-name.md` |
| Gherkin feature | `features/feature-name.feature` |
| Shared locale file | `locales/en.json` (`vauchi/locales` repo) |
| Core Rust code | `core/vauchi-core/src/` |
