---
apply: always
---

## Markdown Plan Format (MANDATORY)

- Use `.plan.md` companion files for task DAGs — never embed checklists in narrative docs
- Every `implementation-plan.md` and `planning/todo/*.md` MUST have a companion `.plan.md`
- **Plan-Code Sync**: Never mark `[x]` on `main` unless implementing code is also on `main`
- Validate with `just plan-validate <file>` before committing

Full syntax, file naming, and lifecycle: `.claude/docs/markdown-plan.md`
