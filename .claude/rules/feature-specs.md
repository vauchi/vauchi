---
paths:
  - "features/**"
  - "_private/features/**"
---

## Feature Specifications

- Gherkin `.feature` files: one feature per file, `snake_case.feature`
- **Lifecycle tags** (MANDATORY on every Scenario): `@implemented`, `@planned`, `@wip`
- `@wip` must resolve before merge. New scenarios default to `@planned`.
- Domain tags alongside lifecycle: `@security @implemented`
- Draft scenarios live in problem records (`_private/docs/problems/`) until promoted to `features/`

### `_private/features/` — Ideas Only

- **No `.feature` files here** — CI enforces this (`check:no-stale-features` job)
- Ideas are **prose** markdown in `ideas/`, not Gherkin
- When ready to implement, create a problem record first

| Stage | Location |
|-------|----------|
| Brainstorming | `_private/features/ideas/*.md` (prose) |
| Draft scenarios | `_private/docs/problems/<slug>/*.feature` |
| Active / Done | `features/*.feature` (tagged `@implemented` or `@planned`) |
