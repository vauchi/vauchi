<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

## Test Quality Rules — Full Reference

These rules constrain AI code generation to produce verifiable, high-quality output.

- **CC-01 Test Is the Specification**: Never generate production code without a failing test first. Test commit (`test:`) before implementation commit (`feat:`/`fix:`/`refactor:`). Push back if asked to skip.
- **CC-02 Small Atomic Commits**: One behavior per commit. If a feature requires N behaviors, that's N red-green cycles. Flag if a change would touch > 5 production files in one commit.
- **CC-03 Assertions Must Be Specific**: Every test must verify a specific behavioral property.
  - **Forbidden**: `assert!(result.is_ok())` without value check, `assert!(output.contains("generic"))`, `assert!(collection.len() > 0)`, tautological asserts on unsigned types, `if let Ok(x) = result { assert!(...) }` (silently skips Err), zero-assertion tests.
  - **Required**: Assert the specific value, assert error conditions explicitly, assert both positive and negative cases in security code, assert specific absence (not just container size).
- **CC-04 Property-Based Tests for Complex Functions**: Include `proptest` tests for crypto operations, serialization roundtrips, data transformations, parsers, and any function with non-trivial input spaces. Tools: Rust=`proptest`, TS=`fast-check`, Kotlin=`kotest-property`.
- **CC-05 Cross-Boundary Contract Consideration**: When modifying core API, vauchi-protocol types, or UniFFI exports, run `just consumers <pattern>` to list all consumers and document contract impact.
- **CC-06 No Real-Time Waits in Tests**: Never use `sleep()` or equivalent for synchronization. Use mockable time, polling with short timeouts, or explicit event synchronization. Exception: load tests simulating real-world timing.
- **CC-07 Behavior-Describing Test Names**: Follow `test_<subject>_<scenario>_<expected_outcome>`. Name must accurately describe what is verified.
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

## Tidy First (Kent Beck)

- **CC-19 Tidy Before Behavior Change**: Before starting a Red-Green cycle, assess whether a small structural improvement (tidying) would make the change easier. Tidyings are structure-only, never change behavior, and get their own `tidy:` commit. Common tidyings: guard clauses, extract helper, explaining variables, delete dead code, normalize symmetries. If the code is already clean, skip straight to RED.

## Pre-Push Rules (MANDATORY)

Derived from post-mortem analysis of pipeline history (2026-02-20).

- **CC-15 Run Checks Before Pushing**: Before every `git push`, run `just check [repo]` and fix all failures. Never push code that hasn't passed local linting and formatting.
- **CC-16 Cross-Repo Push Order**: Use `just git push-all` to push repos with commits ahead (runs checks automatically). When a feature spans multiple repos, only push the **upstream** repo first (e.g., `core/` before `cli/`, `android/`, `ios/`). Mark downstream MRs as **Draft** and note in the description that they depend on the upstream MR being merged and bindings published. Do not push consumer branches that call APIs not yet on `main`.
- **CC-17 Verify Assertions in Every Test**: Before committing a test file, verify every `#[test]` function contains at least one `assert*!`, `prop_assert*!`, `.expect()`, or `#[should_panic]`. Zero-assertion tests are rejected by CI.
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
- **Naming convention**: `*_test.rs`, `test_*.py`, `*.test.ts`, `*.spec.ts` based on language
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
