---
name: tdd-workflow
description: TDD rules, test-to-feature mapping, coverage commands, test naming conventions, and test helper patterns. Use when writing tests or implementing features with TDD.
model: haiku
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi TDD Workflow

## The Three Laws

1. **No production code without a failing test** (Red first)
2. **Write only enough test to fail** (Minimal test)
3. **Write only enough code to pass** (Minimal implementation)

## Red-Green-Refactor-Commit Cycle

```
RED     → Write failing test
GREEN   → Minimal code to pass  → COMMIT
REFACTOR → Improve design       → COMMIT (tests still green)
```

## Test Pyramid

```
         ┌─────┐
         │ E2E │     < 5%
        ┌┴─────┴┐
        │ Integ │    15%
       ┌┴───────┴┐
       │Property │   5%
      ┌┴─────────┴┐
      │   Unit    │  75%
     └─────────────┘
```

## Test Naming Convention

```
test_<function>_<scenario>_<expected>
```

Examples:
- `test_encrypt_valid_key_returns_ciphertext`
- `test_decrypt_wrong_key_fails`
- `prop_encryption_roundtrip` (property-based)

## Feature-to-Test Mapping

Tests reference Gherkin specs in comments:

```rust
/// Feature: contact_exchange.feature @ble @advertisement
#[test]
fn test_ble_advertisement_discovery() { ... }
```

### Feature Files (`features/`)

| Feature File | Tags |
|---|---|
| `contacts_management.feature` | `@contacts @view @search @filter @groups @block @favorites` |
| `security.feature` | `@e2e @keys @auth @attacks @crypto` |
| `contact_exchange.feature` | `@exchange @ble @nfc @proximity @relay` |
| `relay_network.feature` | `@relay @multi-relay @failover @load-balancing` |
| `contact_recovery.feature` | `@recovery @trust @device-link` |
| `sync_updates.feature` | `@sync @offline-queue @delivery` |
| `field_validation.feature` | `@validation @unicode` |
| `identity_management.feature` | `@identity @backup` |
| `aha_moments.feature` | `@aha-moments @card-creation @first-edit` |

**Every Gherkin scenario must have a corresponding test.**

## Test Locations Per Repo

### Core (`core/vauchi-core/tests/`)

```
tests/
├── common/
│   ├── helpers.rs      # Reusable setup functions
│   ├── fixtures.rs     # Test data
│   └── strategies.rs   # Proptest strategies
├── integration/        # Cross-module workflows
│   ├── contact_workflow_test.rs
│   ├── identity_workflow_test.rs
│   └── sync_workflow_test.rs
├── e2e/                # Full scenarios
├── crypto_encryption_tests.rs
├── crypto_signing_tests.rs
├── contact_tests.rs
├── exchange_ble_tests.rs
├── property_tests.rs   # proptest + quickcheck
├── snapshot_tests.rs   # Wire format stability
└── fuzz_tests.rs
```

### Other Repos

| Repo | Test Location | Pattern |
|------|--------------|---------|
| `relay/` | `tests/` | `relay_integration_test.rs`, `handler_websocket_test.rs` |
| `cli/` | `tests/` | `cli_integration_tests.rs` with `CliTestContext` helper |
| `tui/` | `tests/` | `ui_interaction_tests.rs`, `snapshot_tests.rs` |
| `e2e/` | `tests/` | Async tokio tests with `Orchestrator` |

## Test Helpers (core)

```rust
// common/helpers.rs
create_vauchi_with_identity(name: &str) -> Vauchi<MockTransport>  // In-memory
create_vauchi_with_card(name, fields) -> Vauchi<MockTransport>
setup_alice_bob_exchange() -> (Vauchi, Vauchi, SymmetricKey, String, String)
setup_ratchets(shared_secret) -> (DoubleRatchetState, DoubleRatchetState)
setup_three_users() -> (Vauchi, Vauchi, Vauchi, HashMap<...>)
```

## Test Fixtures (core)

```rust
// common/fixtures.rs
pub const TEST_PASSWORD: &str = "SecureP@ssw0rd123!";
pub fn sample_contact_card(name: &str) -> ContactCard { ... }
pub fn diverse_fields_card(name: &str) -> ContactCard { ... }

pub mod unicode { JAPANESE, ARABIC, EMOJI, MIXED, LONG_UNICODE }
pub mod edge_cases { EMPTY, SINGLE_CHAR, SPECIAL_CHARS, WITH_NEWLINES }
pub mod keys { ZERO_KEY_HEX, ONES_KEY_HEX, SAMPLE_KEY }
```

## Proptest Strategies

```rust
// common/strategies.rs
display_name_strategy()  // Non-empty, < 50 chars
field_label_strategy()   // Alphanumeric + underscore
bytes32_strategy()       // 32-byte arrays for keys
timestamp_strategy()     // Unix timestamps
```

## Mocking Rules

| Component | Approach |
|-----------|----------|
| **Crypto** | **REAL (never mock)** — roundtrip tests, wrong key rejection |
| Network | `MockTransport` |
| Storage | `Storage::in_memory(SymmetricKey::generate())` |
| Time | Mockable clock |

## Coverage

**Tool**: `cargo-llvm-cov` (LLVM-based)

**Minimum**: 90% line coverage for vauchi-core, 80% branch coverage

```bash
# Local
just coverage                     # HTML report → core/target/llvm-cov/html/
cargo llvm-cov --workspace --html

# Specific crate
cargo llvm-cov -p vauchi-core --lcov --output-path lcov.info

# CI extracts coverage via regex: /Total:\s+(\d+(?:\.\d+)?%)/
```

## Running Tests

```bash
# All tests
just test                          # All tests (in core/)
just test core                     # Explicit repo target
just check                         # fmt + lint + test

# Specific crate
just test-crate vauchi-core        # Single crate
just test-crate vauchi-platform      # Mobile bindings

# Watch mode
just watch                         # Watch + auto-test (core)

# Coverage
just coverage                      # HTML report → core/target/llvm-cov/html/
```

> **Note**: For running a single test file or with flags like `--nocapture` or `--ignored`, raw `cargo test` is acceptable since `just` has no equivalent recipe for these granular operations.

## Cargo.toml Test Entries

```toml
[[test]]
name = "content"
path = "tests/content/mod.rs"

[[test]]
name = "e2e"
path = "tests/e2e/mod.rs"

[[test]]
name = "integration"
path = "tests/integration/mod.rs"
```

## Forbidden Practices

- Writing code before tests
- `#[ignore]` without tracking issue
- Flaky tests
- Hardcoded secrets in test code
- Mocking crypto primitives
- Skipping coverage checks
