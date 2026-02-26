## Markdown Plan Format (MANDATORY)

- **Task tracking** uses markdown-plan syntax in `.plan.md` companion files
- Never embed task-tracking checklists in narrative docs — use the companion file
- Every `implementation-plan.md` and every `planning/todo/*.md` doc MUST have a companion `.plan.md`
- `.plan.md` files contain ONLY the task DAG — no prose, no tables, no `<details>` blocks

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

### Lifecycle
- Create `.plan.md` when a problem or plan enters the **planning** phase
- Update task status (`[x]`) as work is completed
- Validate with `just plan-validate <file>` before committing
- View progress with `just plan-list` or `just plan-plot <file>`
