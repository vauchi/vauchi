---
paths:
  - "locales/**"
  - "themes/**"
---

## Locales

- `en.json` is source of truth — all keys must exist here first
- All locales must have same keys (CI validates parity). No empty values.
- JSON sorted alphabetically. Keys use dot notation: `section.subsection.name`
- **Cross-locale parity** (every locale has the same keys as `en.json`):
  `python3 scripts/validate.py --strict` (CI:
  `validate:locales-strict` in `locales/.gitlab-ci.yml`).
- **Source-side coverage** (every literal key passed to
  `get_string()` / `t()` / `NSLocalizedString` exists in
  `en.json`): `just lint-locale-keys` (CI:
  `lint:locale-key-coverage` in `core/.gitlab-ci.yml`). Catches
  typos and stale call sites at MR time instead of the runtime
  fallback `Missing: <key>` at `core/vauchi-app/src/i18n.rs:134`.
  Variable-key sites (`get_string(locale, &computed_key)`) are
  statically unreachable — covered by test discipline + runtime
  fallback.

## Themes

- 11 required color tokens: `bg-primary`, `bg-secondary`, `bg-tertiary`, `text-primary`, `text-secondary`, `accent`, `accent-dark`, `success`, `error`, `warning`, `border`
- All colors 6-digit hex (`#rrggbb`), mode `"dark"` or `"light"`, IDs lowercase kebab-case
- WCAG AA contrast: `text-primary` on `bg-primary` >= 4.5:1
- Validate: `python3 scripts/validate.py --strict`
