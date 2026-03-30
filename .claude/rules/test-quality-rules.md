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
- **CC-20 No Tautological Accessibility Tests**: Accessibility tests must query the live view hierarchy (XCUITest, Espresso, AT-SPI). Forbidden: asserting compile-time constants (`Identifiers.X.count > 0`), asserting minimum clickable node counts (`>= 1 clickable`), any assertion that cannot fail. A11y tests must verify that labeled elements exist in the rendered UI, not that string constants are non-empty.
- **CC-21 Chesterton's Fence for Failures**: When a test, lint rule, CI check, or setting flags an issue, the default assumption is the **source code** is wrong — not the check. Before suppressing a lint warning, adding an exclusion, disabling a CI job, loosening a config, or modifying a test to make a failure go away, pass this gate: (1) Find the root cause in the source code first. (2) Ask: is the check really wrong, or is it catching a real issue? (3) Understand why the check exists — what was it written to prevent? If after all three checks you are confident the rule/test/setting itself is incorrect, you may change it. Otherwise, fix the source.

Full test design guidelines (AAA, coverage, mocking, organization): `.claude/docs/test-quality-rules.md`
