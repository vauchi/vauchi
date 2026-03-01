---
apply: always
---

<!-- CONDENSED: Quick reference for AI assistants. SSOT: docs/developers/tdd-rules.md (public docs site) -->

## MANDATORY

- **TDD**: Red→Green→Commit→Refactor→Commit. Test FIRST. Tests trace to `features/*.feature`
  - Commit immediately when tests go green
  - Commit after each refactor if tests still green
- **Structure**: `src/` = prod, `tests/` = tests (siblings)
- **Crypto**: `ring` only. Never mock crypto
- **Coverage**: 90%+ for vauchi-core
- **Planning**: Feature done → move `_private/docs/planning/todo/` doc to `done/`
