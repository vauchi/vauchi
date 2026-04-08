---
paths:
  - "locales/**"
  - "themes/**"
---

## Locales

- `en.json` is source of truth — all keys must exist here first
- All locales must have same keys (CI validates parity). No empty values.
- JSON sorted alphabetically. Keys use dot notation: `section.subsection.name`
- Validate: `python3 scripts/validate.py --strict`

## Themes

- 11 required color tokens: `bg-primary`, `bg-secondary`, `bg-tertiary`, `text-primary`, `text-secondary`, `accent`, `accent-dark`, `success`, `error`, `warning`, `border`
- All colors 6-digit hex (`#rrggbb`), mode `"dark"` or `"light"`, IDs lowercase kebab-case
- WCAG AA contrast: `text-primary` on `bg-primary` >= 4.5:1
- Validate: `python3 scripts/validate.py --strict`
