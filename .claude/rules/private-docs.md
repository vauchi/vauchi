---
paths:
  - "_private/docs/**"
---

## Internal Documentation

| Path | Content |
|------|---------|
| `problems/` | Active problem records (with `done/`) |
| `designs/` | Design documents (`*-design.md`) |
| `planning/` | Lifecycle-tracked plans (`todo/`, `done/`, `deferred/`, `rejected/`, `archived/`) |
| `investigations/` | Research, audits, assessments (with `measurements/` subdir) |
| `post-mortems/` | Incident analysis |
| `decisions/` | ADR decision records (`adr-NNN-slug.md`) |
| `specs/` | Internal protocol specifications |
| `audit-review-frameworks/` | Numbered review templates/checklists |
| `reference/` | Security audit, threat model, CI/CD, guides, workflows, knowledge |
| `testing/` | QA strategy, manual testing, device automation |
| `legal/` | Compliance, licensing |
| `archive/` | Docs from deprecated projects |
| `scripts/` | Documentation tooling (naming validator) |

### Problem Records

Each record: `YYYY-MM-DD-problem-slug/` containing:
`README.md`, `investigation.md`, `implementation-plan.md` (with `### Rejected Approaches` + `### Test Strategy`), `plan.md` (task DAG), `*.feature` (drafts), `retrospective.md`

- Every record needs: **status**, **priority**, **owner**, **goals** (measurable)
- Critical/high: **containment** required before investigation
- Draft Gherkin lives here until promoted → add `promoted_to:` link in README
- `Size: small` records: single README.md, no companion files. For items ≤1 focused day. Same fields, same lifecycle. Promote if scope grows.
