---
apply: always
---

## Code Structure Rules

- **Production code**: `src/` directory only
- **Test code**: `tests/` directory only (sibling to `src/`)
- **Never mix**: No test code in production, no production code in test directories
- **Test utilities**: Place shared test helpers in `tests/common/` or `tests/helpers/`
