---
apply: always
---

<!-- CONDENSED: Quick reference for AI assistants. Full version: /docs/2026-01-22-TDD_RULES.md -->

## MANDATORY

- **TDD**: Red→Green→Commit→Refactor→Commit. Test FIRST. Tests trace to `features/*.feature`
  - Commit immediately when tests go green
  - Commit after each refactor if tests still green
- **Structure**: `src/` = prod, `tests/` = tests (siblings)
- **Crypto**: `ring` only. Never mock crypto
- **Coverage**: 90%+ for vauchi-core
- **Planning**: Feature done → move `_private/docs/planning/todo/` doc to `done/`
