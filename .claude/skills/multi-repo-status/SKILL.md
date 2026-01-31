---
name: multi-repo-status
description: Check git status, branches, and uncommitted changes across all vauchi sub-repositories
disable-model-invocation: true
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

Check git status across all vauchi sub-repositories. For each repo that has changes, show the branch, uncommitted changes, and commits ahead of main.

## Steps

1. Loop through all known sub-repo directories:
   `android core relay cli tui desktop e2e features ios docs website scripts assets _private vauchi-mobile-android vauchi-mobile-swift`

2. For each directory that exists and has a `.git/`:
   - Show current branch: `git -C <dir> branch --show-current`
   - Show short status: `git -C <dir> status --short`
   - Show commits ahead of main: `git -C <dir> log origin/main..HEAD --oneline 2>/dev/null`

3. Skip repos with no changes and no commits ahead of main.

4. Present results as a summary table:

| Repo | Branch | Uncommitted | Ahead of main |
|------|--------|-------------|---------------|

5. Flag any repos with uncommitted `.DS_Store` or other files that should be gitignored.
