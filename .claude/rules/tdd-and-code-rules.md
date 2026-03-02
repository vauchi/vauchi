---
apply: always
---

<!-- SSOT: docs/developers/tdd-rules.md (public docs site) -->

## TDD, Code Structure & Crypto (MANDATORY)

- **TDD**: Tidy→Commit→Red→Green→Commit→Refactor→Commit. Test FIRST. Tests trace to `features/*.feature`
  - **Tidy First** (optional): small structural-only improvement before starting a cycle — guard clauses, extract helper, rename, delete dead code. Own `tidy:` commit. No behavior change.
  - Commit immediately when tests go green
  - Commit after each refactor if tests still green
- **Structure**: `src/` = prod, `tests/` = tests (siblings). Never mix. Test helpers in `tests/common/` or `tests/helpers/`
- **Crypto**: `ring` primary. Exceptions (spec-mandated): `chacha20poly1305`, `argon2`, `x25519-dalek`. Never mock crypto. Never introduce new crypto libs without approval. Zeroize key material after use.
- **Coverage**: 90%+ for vauchi-core. Measure with `just coverage`.
- **Checks**: Run `just check [repo]` before pushing (fmt-check + lint + test in one command).
- **Planning**: Feature done → move `_private/docs/planning/todo/` doc to `done/`
