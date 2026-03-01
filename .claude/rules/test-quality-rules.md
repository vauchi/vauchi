---
apply: always
---

## Test Quality Rules (MANDATORY)

These rules constrain AI code generation to produce verifiable, high-quality output.

- **CC-01 Test Is the Specification**: Never generate production code without a failing test first. Test commit (`test:`) before implementation commit (`feat:`/`fix:`/`refactor:`). Push back if asked to skip.
- **CC-02 Small Atomic Commits**: One behavior per commit. If a feature requires N behaviors, that's N red-green cycles. Flag if a change would touch > 5 production files in one commit.
- **CC-03 Assertions Must Be Specific**: Every test must verify a specific behavioral property.
  - **Forbidden**: `assert!(result.is_ok())` without value check, `assert!(output.contains("generic"))`, `assert!(collection.len() > 0)`, tautological asserts on unsigned types, `if let Ok(x) = result { assert!(...) }` (silently skips Err), zero-assertion tests.
  - **Required**: Assert the specific value, assert error conditions explicitly, assert both positive and negative cases in security code, assert specific absence (not just container size).
- **CC-04 Property-Based Tests for Complex Functions**: Include `proptest` tests for crypto operations, serialization roundtrips, data transformations, parsers, and any function with non-trivial input spaces. Tools: Rust=`proptest`, TS=`fast-check`, Kotlin=`kotest-property`.
- **CC-05 Cross-Boundary Contract Consideration**: When modifying core API, vauchi-protocol types, or UniFFI exports, list all consumers and document contract impact.
- **CC-06 No Real-Time Waits in Tests**: Never use `sleep()` or equivalent for synchronization. Use mockable time, polling with short timeouts, or explicit event synchronization. Exception: load tests simulating real-world timing.
- **CC-07 Behavior-Describing Test Names**: Follow `test_<subject>_<scenario>_<expected_outcome>`. Name must accurately describe what is verified.
- **CC-08 Plans Must Include Test Strategy**: Every implementation plan must address: unit tests, property-based tests, contract tests, affected existing tests, and mutation testing impact.
- **CC-09 Counterexamples Become Regression Tests**: When a property-based test finds a counterexample, capture the exact input as a permanent `test_<fn>_regression_<description>` test.
- **CC-10 Snapshot Updates Require Review**: Never bulk-update snapshots without reviewing each change. Flag if > 10 snapshots change from one code change. Snapshot updates go in a separate commit.
- **CC-11 Test Failure Paths**: For every function, test at least one failure path: invalid input, missing dependency, boundary conditions, and network errors for network code.
- **CC-12 Beware Test-Code Correlation Trap**: Write the test FIRST, commit it, verify it fails, THEN write code. Never "write tests for this function" after the function exists. Mutation testing is the automated defense.
- **CC-13 Stateful Property Tests for Lifecycles**: For domain objects with state machines (identity, contacts, exchange, sync, backup), write stateful property tests that verify invariants across random operation sequences.
- **CC-14 Adversarial Test Data for Security Boundaries**: For functions processing user input or external data, include parameterized tests with adversarial payloads (empty, max-length, unicode, RTL, null bytes, injection payloads, corrupted data, tampered signatures).

## Pre-Push Rules (MANDATORY)

These rules prevent the most common CI failures. Derived from post-mortem analysis of pipeline history (2026-02-20).

- **CC-15 Run Checks Before Pushing**: Before every `git push`, run `just check [repo]` and fix all failures. Never push code that hasn't passed local linting and formatting.
- **CC-16 Cross-Repo Push Order**: When a feature spans multiple repos, only push the **upstream** repo first (e.g., `core/` before `cli/`, `android/`, `ios/`). Mark downstream MRs as **Draft** and note in the description that they depend on the upstream MR being merged and bindings published. Do not push consumer branches that call APIs not yet on `main`.
- **CC-17 Verify Assertions in Every Test**: Before committing a test file, verify every `#[test]` function contains at least one `assert*!`, `prop_assert*!`, `.expect()`, or `#[should_panic]`. Zero-assertion tests are rejected by CI.
- **CC-18 Never Retry Without Fixing**: If a pipeline fails, read the job log and fix the root cause before re-running. Never retry the same commit expecting a different result.
