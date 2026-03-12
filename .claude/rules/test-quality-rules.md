---
apply: always
---

## Test Quality Rules (MANDATORY)

CC rules constrain AI code generation. Full details: `.claude/docs/test-quality-rules.md`

### Critical (project-specific)
- **CC-03 Specific Assertions**: Assert exact values. Forbidden: `assert!(result.is_ok())` without value check, `if let Ok(x)` (silently skips Err), zero-assertion tests, tautological asserts. Assert both positive and negative cases in security code.
- **CC-04 Property-Based Tests**: `proptest` for crypto, serialization roundtrips, parsers, non-trivial input spaces.
- **CC-05 Cross-Boundary Contracts**: When modifying core API / vauchi-protocol / UniFFI exports, run `just consumers <pattern>` to list all consumers and document contract impact.
- **CC-06 No Real-Time Waits**: Never `sleep()` in tests. Use mockable time or event sync.
- **CC-13 Stateful Property Tests**: For state machines (identity, contacts, exchange, sync, backup), verify invariants across random operation sequences.
- **CC-14 Adversarial Test Data**: Security boundaries need parameterized tests with adversarial payloads (empty, max-length, unicode, null bytes, injection, tampered signatures).

### Standard (condensed)
- **CC-08**: Plans must include test strategy (unit, property, contract, mutation impact).
- **CC-09**: Counterexamples from proptest become permanent regression tests.
- **CC-10**: Never bulk-update snapshots. Review each with `cargo insta review`. Separate commit.
- **CC-11**: Test at least one failure path per function.
- **CC-15**: Run `just check [repo]` before every push.
- **CC-17**: Every `#[test]` must contain `assert*!`, `prop_assert*!`, `.expect()`, or `#[should_panic]`.
- **CC-18**: Never retry a failed pipeline without fixing the root cause.
- **CC-19**: Tidy before behavior change — small structural-only improvement in its own `tidy:` commit before starting RED. Skip if code is already clean.

Full test design guidelines (AAA, coverage, mocking, organization): `.claude/docs/test-quality-rules.md`
