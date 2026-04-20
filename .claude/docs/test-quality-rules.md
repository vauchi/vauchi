<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

## Test Quality Rules — Full Reference

These rules constrain AI code generation to produce verifiable, high-quality output.

- **CC-01 Test Is the Specification**: Never generate production code without a failing test first. Test commit (`test:`) before implementation commit (`feat:`/`fix:`/`refactor:`). Push back if asked to skip.
- **CC-02 Small Atomic Commits**: One behavior per commit. If a feature requires N behaviors, that's N red-green cycles. Flag if a change would touch > 5 production files in one commit.
- **CC-03 Assertions Must Be Specific**: Every test must verify a specific behavioral property, in every language.
  - **Forbidden (all languages)**: Success-only checks without value verification, silently-passing error paths, zero-assertion tests, tautological asserts.
  - **Forbidden examples by language**:
    - Rust: `assert!(result.is_ok())` without value check, `if let Ok(x) = result { assert!(...) }` (silently skips Err)
    - Swift: `XCTAssertNotNil(x)` alone without checking the value, `XCTAssertTrue(result)` without specificity
    - Kotlin: `assertTrue(result.isSuccess)` alone, `assertNotNull(x)` without value check
    - C#: `Assert.True(result.IsSuccess)` alone, `Assert.NotNull(x)` without value check
    - C++: `ASSERT_TRUE(result)` alone, `ASSERT_NE(ptr, nullptr)` without value check
    - Python: `assert result is not None` alone, `assert len(items) > 0` without checking content
    - TypeScript: `expect(result).toBeTruthy()` alone, `expect(items.length).toBeGreaterThan(0)` without content check
  - **Required**: Assert the specific value, assert error conditions explicitly, assert both positive and negative cases in security code, assert specific absence (not just container size).
- **CC-04 Property-Based Tests for Complex Functions**: Include `proptest` tests for crypto operations, serialization roundtrips, data transformations, parsers, and any function with non-trivial input spaces. Tools: Rust=`proptest`, TS=`fast-check`, Kotlin=`kotest-property`.
- **CC-05 Cross-Boundary Contract Consideration**: When modifying core API, vauchi-protocol types, or UniFFI exports, run `just consumers <pattern>` to list all consumers and document contract impact.
- **CC-06 No Real-Time Waits in Tests**: Never use `sleep()` or equivalent for synchronization. Use mockable time, polling with short timeouts, or explicit event synchronization. Exception: load tests simulating real-world timing.
- **CC-07 Behavior-Describing Test Names**: Names must accurately describe what is verified. Conventions by language:
  - Rust/Python: `test_<subject>_<scenario>_<expected_outcome>`
  - Swift: `test<Subject><Scenario><ExpectedOutcome>()` (camelCase)
  - Kotlin: `` `subject scenario returns expected outcome`() `` (backtick-enclosed)
  - C#: `<Subject>_<Scenario>_<ExpectedOutcome>()` (PascalCase segments)
  - C++: `TEST(<Suite>, <Subject>_<Scenario>_<ExpectedOutcome>)`
  - TypeScript: `it("should <expected outcome> when <scenario>")`
- **CC-08 Plans Must Include Test Strategy**: Every implementation plan must address: unit tests, property-based tests, contract tests, affected existing tests, and mutation testing impact.
- **CC-09 Counterexamples Become Regression Tests**: When a property-based test finds a counterexample, capture the exact input as a permanent `test_<fn>_regression_<description>` test.
- **CC-10 Snapshot Updates Require Review**: Never bulk-update snapshots without reviewing each with `cargo insta review`. Flag if > 10 snapshots change from one code change. Snapshot updates go in a separate commit.
- **CC-11 Test Failure Paths**: For every function, test at least one failure path: invalid input, missing dependency, boundary conditions, and network errors for network code.
- **CC-12 Beware Test-Code Correlation Trap**: Write the test FIRST, commit it, verify it fails, THEN write code. Never "write tests for this function" after the function exists. Mutation testing is the automated defense.
- **CC-13 Stateful Property Tests for Lifecycles**: For domain objects with state machines (identity, contacts, exchange, sync, backup), write stateful property tests that verify invariants across random operation sequences.
- **CC-14 Adversarial Test Data for Security Boundaries**: For functions processing user input or external data, include parameterized tests with adversarial payloads (empty, max-length, unicode, RTL, null bytes, injection payloads, corrupted data, tampered signatures).
- **CC-20 No Tautological Accessibility Tests**: Accessibility tests must query the **live view hierarchy** — XCUITest (iOS), Espresso/Compose semantics (Android), AT-SPI (Linux), UI Automation (Windows). Forbidden patterns:
  - Asserting compile-time string constants: `XCTAssertTrue(Identifiers.X.count > 0)` — can never fail
  - Asserting minimum clickable counts: `assert(clickableNodes >= 1)` — vacuously true for any UI
  - Any assertion whose outcome is determined at compile time, not runtime
  - **Required**: Tests must render the actual UI and query elements by accessibility identifier, then assert existence, labels, hints, or traits. If a screen reader label were deleted from production code, the test must fail.

- **CC-21 Chesterton's Fence for Failures**: When a test, lint rule, CI check, or setting flags an issue, the default assumption is the **source code** is wrong — not the check. Before suppressing, ignoring, filtering, excluding, disabling, or modifying a check to make a failure go away, pass this gate:
  1. **Find the root cause** in the source code first — diagnose what the check is actually catching.
  2. **Ask: is the check really wrong?** Or is it catching a real issue that should be fixed in the source?
  3. **Understand why the check exists** — what was it written to prevent? What regresses if it's removed or weakened?
  - If after all three checks you are confident the rule/test/setting itself is incorrect (outdated contract, wrong threshold, removed feature), you may change it. Otherwise, fix the source code.

## Tidy First (Kent Beck)

- **CC-19 Tidy Before Behavior Change**: Before starting a Red-Green cycle, assess whether a small structural improvement (tidying) would make the change easier. Tidyings are structure-only, never change behavior, and get their own `tidy:` commit. Common tidyings: guard clauses, extract helper, explaining variables, delete dead code, normalize symmetries. If the code is already clean, skip straight to RED.

## Pre-Push Rules (MANDATORY)

Derived from post-mortem analysis of pipeline history (2026-02-20).

- **CC-15 Run Checks Before Pushing**: Before every `git push`, run `just check [repo]` and fix all failures. Never push code that hasn't passed local linting and formatting.
- **CC-16 Cross-Repo Push Order**: Use `just git push-all` to push repos with commits ahead (runs checks automatically). When a feature spans multiple repos, only push the **upstream** repo first (e.g., `core/` before `cli/`, `android/`, `ios/`). Mark downstream MRs as **Draft** and note in the description that they depend on the upstream MR being merged and bindings published. Do not push consumer branches that call APIs not yet on `main`.
- **CC-17 Verify Assertions in Every Test**: Before committing a test file, verify every test function contains language-appropriate assertions. Zero-assertion tests are rejected by CI.
  - Rust: `assert*!`, `prop_assert*!`, `.expect()`, or `#[should_panic]`
  - Swift: `XCTAssert*`, `XCTFail`, or `#expect` (Swift Testing)
  - Kotlin: `assert*()`, `assertThrows`, or Compose `assert*()` semantics
  - C#: `Assert.*()` (xUnit)
  - C++: `ASSERT_*`, `EXPECT_*` (Google Test)
  - Python: `assert` statements or `pytest.raises`
  - TypeScript: `expect()` chains (Vitest/Jest/Playwright)
- **CC-18 Never Retry Without Fixing**: If a pipeline fails, read the job log and fix the root cause before re-running. Never retry the same commit expecting a different result.

## Testing Best Practices

### Test Design Principles

- **One assertion per concept**: Each test should verify one logical behavior
- **Descriptive names**: Test names should describe the scenario and expected outcome (e.g., `test_user_login_with_invalid_password_returns_error`)
- **AAA Pattern**: Arrange, Act, Assert - structure tests clearly
- **Independent tests**: Tests must not depend on execution order or shared mutable state
- **Fast tests**: Unit tests should complete in milliseconds; slow tests go in integration suites

### Test Coverage

- **Branch coverage**: Test both branches of conditionals
- **Edge cases**: Test boundary conditions, empty inputs, nulls, and error paths
- **Happy path + sad path**: Test both successful and failure scenarios

### Test Organization

- **Mirror source structure**: Test file structure should mirror production code structure
- **Naming convention**: `*_test.rs`, `test_*.py`, `*.test.ts`, `*Tests.swift`, `*Test.kt`, `*Tests.cs`, `*.test.cpp` based on language
- **Group related tests**: Use describe/context blocks or test modules to group related tests
- **Fixtures and factories**: Use fixtures for test data setup, factories for complex objects

### Mocking Guidelines

- **Mock external dependencies only**: Database, network, file system, time
- **Never mock the unit under test**: Test real implementations
- **Prefer fakes over mocks**: Use in-memory implementations when possible
- **Verify mock interactions sparingly**: Over-mocking leads to brittle tests

### Test Maintenance

- **DRY in tests (carefully)**: Extract common setup, but keep tests readable
- **Delete obsolete tests**: Remove tests for deleted features
- **Flaky test policy**: Fix or quarantine flaky tests immediately

## Frontend Correctness Strategy — Four Layers

Source: `_private/docs/planning/todo/2026-04-20-frontend-correctness-strategy-plan.md`.
Catches bugs that unit/integration/snapshot tests miss at the
`core ↔ binding ↔ frontend ↔ device` seam. Each layer catches a
bug class the layer above cannot see.

### Layer 1 — ScreenModel reachability (`just reachability`)

**Catches**: orphan handler arms (declared but no affordance
emits them) and orphan affordances (ScreenActions nothing
consumes). Single-file smoking gun: an onboarding handler arm
the UI cannot reach yet the app ships, leaving a silently-dead
code path users can never hit.

**When it fires**: `cargo nextest run -p vauchi-app
--features vauchi-app/test-support --test reachability`. Required
by `just check core` and the CI `test:reachability` job.

**When you must update it (rule CC-22)**: any MR adding a new
`WorkflowEngine` impl or a new `UserAction` / `ScreenAction` id
ships or updates a `core/vauchi-app/tests/reachability/<engine>.rs`
declaring the engine's handler `action_id` set. `walk_actions`
emits one `UserAction` per affordance; the harness diffs the
walker set against the declared set.

### Layer 2 — UniFFI ABI parity (`just check-binding-abi`)

**Catches**: stale bindings or stale artifact — symbols the
Kotlin/Swift bindings reference but the packaged `.so` / `.a`
does not export (or vice versa). Shifts the failure from
`UnsatisfiedLinkError` on first-touch device call to an
exit-1 before the artifact leaves the build host. Triggered by
the 2026-04-20 Android startup crash.

**When it fires**: `scripts/check-binding-abi.sh
--platform {android|ios|macos} --artifact <path> --bindings <path>`.
Invoked automatically inside `_dt-package-android` /
`_dt-package-ios`; top-level `just check-binding-abi {android|ios}`
for ad-hoc debugging.

### Layer 3 — Device-level E2E per critical flow (Maestro)

**Catches**: rendering divergence across frontends, missing
affordances, platform-specific input focus bugs, navigation
regressions — things the Humble-UI invariant says can't
happen but historically do, per-platform.

**Status**: Phase 3 in the plan; not yet fully gated on
MRs. The repo already ships ~20 Maestro flows under
`e2e/maestro/{ios,android}/`; Phase 3 extends five of them
with post-state assertions and adds an `add_custom_group`
flow.

### Layer 4 — Two-device protocol harness

**Catches**: protocol invariants that require two participants
— unilateral exchange completion, sync convergence, device-link
pairing, duress-alert propagation. The invariant the
`2026-03-31-unilateral-exchange-race` record calls out.

**Status**: Phase 4 in the plan. Highest CI cost; starts
hand-run, promotes to nightly.

---

Each layer has its own regression test to prove it catches its
bug class. Layer 1's proof is the `ToyEngine` meta-tests in
`core/vauchi-app/src/ui/testing/reachability.rs`. Layer 2's
proof: running it against the current iOS artifact pair
exposes two real orphan symbols (`diagnostic_scan_qr`) — a
naturally-occurring deliberately-stale case.
