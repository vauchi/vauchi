---
name: multi-repo-commit
description: Commit changes across multiple vauchi sub-repositories with consistent messages and co-author lines
disable-model-invocation: true
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

Commit staged and unstaged changes across multiple vauchi sub-repositories. $ARGUMENTS may specify which repos to commit, or leave blank to auto-detect all repos with changes.

## Steps

1. **Detect changes** — Run `git -C <dir> status --short` for all sub-repos:
   `android core relay cli tui e2e features ios macos windows linux-gtk linux-qt web-demo docs website scripts assets themes locales _private vauchi-platform-swift`
   Include the root repo (current directory) as well.

2. **Show summary** — Present what will be committed per repo. Ask the user to confirm before proceeding.

3. **For each repo with changes:**
   - Review the diff to understand what changed
   - Stage appropriate files (prefer specific files over `git add -A`)
   - Never stage files that contain secrets (`.env`, tokens, credentials)
   - Write a commit message following the project convention:
     ```
     {type}: {Short description}

     {Longer description if needed}

     Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
     ```
   - Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

4. **Atomic commits** — Each repo gets its own commit. Each commit should be a single logical change.

5. **Report results** — Show a table of what was committed where.
