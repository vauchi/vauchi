---
name: markdown-plan
description:
  Create, update, and validate markdown-plan companion files for task tracking
disable-model-invocation: true
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

Create, update, or validate a `.plan.md` companion file. $ARGUMENTS describes
the target (a problem slug, plan name, or file path).

See also: `.claude/docs/markdown-plan.md` for format rules.

## Creating a new plan.md

When a problem record has an `implementation-plan.md` or a planning doc exists
in `planning/todo/`:

1. **Read the implementation plan** to extract the task structure
2. **Create the companion `.plan.md`** using markdown-plan syntax:
   - Top-level header = plan name
   - Ordered lists for sequential tasks (phases, steps)
   - Unordered lists for parallel tasks (independent subtasks)
   - `@(substring)` for cross-task dependencies
   - `[x]` for already-completed tasks
3. **Validate** the file:

   ```bash
   just plan-validate <file>
   ```

4. **Commit** the new file:

   ```bash
   git add <file>
   git commit -m "feat: add markdown-plan task tracking for <name>"
   ```

## Updating task status

When implementation work is completed:

1. **Read the current `.plan.md`**
2. **Mark completed tasks** with `[x]`
3. **Validate**: `just plan-validate <file>`
4. **Commit**:

   ```bash
   git add <file>
   git commit -m "chore: update plan progress for <name>"
   ```

## Querying progress

```bash
just plan-list                    # All plans with task counts
just plan-validate <file>         # Validate a specific plan
just plan-history <file>          # Task history as JSON
just plan-plot <file>             # Burn-up chart in browser
just plan-stale                   # Plans with no recent changes
```

## File naming

| Location                  | Naming                         |
| ------------------------- | ------------------------------ |
| `planning/todo/<name>.md` | `planning/todo/<name>.plan.md` |
| `plans/<name>.md`         | `plans/<name>.plan.md`         |
| `problems/<slug>/`        | `problems/<slug>/plan.md`      |
| Portfolio level           | `planning/master-plan.plan.md` |

## Example plan.md

```markdown
# SP-6: Resistance Features

1. [x] ShredManager implementation
2. [x] Duress PIN core + storage + CLI
3. Emergency broadcast
   - [x] Core + storage + CLI
   - [x] Desktop UI
   - [x] Android UI
   - TUI emergency UI
   - Panic widget Android
4. [x] Hidden contacts
5. Mobile duress auth flow @(Duress PIN)
6. Locale keys for all resistance features
```
