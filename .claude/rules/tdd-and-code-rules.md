---
apply: always
---

<!-- SSOT: docs/developers/tdd-rules.md (public docs site) -->

## TDD, Code Structure & Crypto (MANDATORY)

- **TDD**: Tidy→Commit→Red→Green→Commit→Refactor→Commit. Test FIRST. Tests trace to `features/*.feature`
  - **Tidy First** (optional): small structural-only improvement before starting a cycle — guard clauses, extract helper, rename, delete dead code. Own `tidy:` commit. No behavior change.
  - **Tidy Phase for large changes**: Before significant refactors, extractions, or architectural changes, plan a dedicated Phase 0 of `tidy:` commits that create clean seams — move types to shared locations, break circular deps, merge small modules, tighten visibility. Make the change easy, then make the easy change. Each tidy step is independently verifiable (`just check`).
  - Commit immediately when tests go green
  - Commit after each refactor if tests still green
- **Structure**: `src/` = prod, `tests/` = tests (siblings). Never mix. Test helpers in `tests/common/` or `tests/helpers/`
- **Crypto**: See `adr-constraints.md` §Crypto — approved crates, no mocking, zeroize rules
- **Coverage**: 90%+ for vauchi-core. Measure with `just coverage`.
- **Planning**: Feature done → move `_private/docs/planning/todo/` doc to `done/`
