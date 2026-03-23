---
apply: always
---

## Visibility Boundary (CRITICAL)

- **Design documents** (`*-design.md`) → go in `_private/docs/designs/`
- **Implementation plans, task DAGs** → go in `_private/docs/planning/todo/` (or inside a problem record)
- **Planning workflow docs (todo/done/roadmap)** → always go in `_private/docs/planning/`
- **Never write plans to `docs/`** — the `docs/` repo is public and deployed to docs.vauchi.app
- **Never embed local absolute paths** (`/Users/...`) in any document — use project-relative paths
- **Never reference `_private/` paths from public docs** — contributors can't access them
- When creating a new design doc, default location is `_private/docs/designs/{date}-{slug}-design.md`
- When creating a new plan, default location is `_private/docs/planning/todo/{date}-{slug}-plan.md`
- See `VISIBILITY_POLICY.md` for the full public/private classification
