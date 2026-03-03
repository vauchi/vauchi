---
apply: always
---

## Visibility Boundary (CRITICAL)

- **Implementation plans, design docs** → go in `_private/docs/plans/` (standalone) or `_private/docs/problems/YYYY-MM-DD-slug/` (part of a problem record)
- **Planning workflow docs (todo/done/roadmap)** → always go in `_private/docs/planning/`
- **Never write plans to `docs/`** — the `docs/` repo is public and deployed to docs.vauchi.app
- **Never embed local absolute paths** (`/Users/...`) in any document — use project-relative paths
- **Never reference `_private/` paths from public docs** — contributors can't access them
- When creating a new plan or design doc, default location is `_private/docs/plans/{date}-{slug}-design.md`
- See `VISIBILITY_POLICY.md` for the full public/private classification
