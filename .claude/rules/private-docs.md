---
paths:
  - "_private/docs/**"
apply: always
---

## Internal Documentation

| Path | Content |
|------|---------|
| `problems/` | Active problem records |
| `problems/done/` | Completed/archived records |
| `planning/` | Todo, done, archived, post-mortems |
| `specs/` | Internal protocol specifications |
| `reference/` | Security audit, threat model, CI/CD |
| `testing/` | QA strategy, manual testing |

### Problem Records

Each record: `YYYY-MM-DD-problem-slug/` containing:
`README.md`, `investigation.md`, `implementation-plan.md` (with `### Rejected Approaches` + `### Test Strategy`), `plan.md` (task DAG), `*.feature` (drafts), `retrospective.md`

- Every record needs: **status**, **priority**, **owner**, **goals** (measurable)
- Critical/high: **containment** required before investigation
- Draft Gherkin lives here until promoted → add `promoted_to:` link in README
