<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

## Markdown Plan Format — Full Reference

### Syntax rules
- Headers and list items = tasks (everything else is ignored by the parser)
- `[x]` = done, `[ ]` or unmarked = todo
- Ordered lists = sequential tasks (2 depends on 1)
- Unordered lists = parallel tasks (siblings run concurrently)
- `@(substring)` = explicit dependency on another task by substring match
- Cyclic dependencies are invalid — run `just plan-validate` before committing

### File naming
- `planning/todo/<basename>.plan.md` — matches the narrative doc's basename
- `plans/<basename>.plan.md` — matches the narrative doc's basename
- `problems/<slug>/plan.md` — fixed name, one per problem record directory
- `planning/master-plan.plan.md` — portfolio-level SP tracking

### Plan-Code Sync (MANDATORY)
- **Never mark a plan item `[x]` on `main` unless the implementing code is also on `main`**
- When working on a feature branch, keep plan items as `[ ]` — only mark `[x]` in the same MR that merges the code, so plan and code land atomically
- If a plan item was completed in a previous MR already on `main`, it may be marked `[x]` in a plan-only MR
- After merge: verify that plan status matches what is actually on `main` — catch stale `[ ]` (code landed but plan not updated) and false `[x]` (plan updated but code missing or incomplete)
- Periodically reconcile plans against code (e.g., before SP milestones) to catch drift

### Lifecycle
- Create `.plan.md` when a problem or plan enters the **planning** phase
- Update task status (`[x]`) as work is completed
- Validate with `just plan-validate <file>` before committing
- View progress with `just plan-list` or `just plan-plot <file>`
