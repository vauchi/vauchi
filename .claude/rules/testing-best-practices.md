---
apply: always
---

## Testing Best Practices

### Test Design Principles
- **One assertion per concept**: Each test should verify one logical behavior
- **Descriptive names**: Test names should describe the scenario and expected outcome (e.g., `test_user_login_with_invalid_password_returns_error`)
- **AAA Pattern**: Arrange, Act, Assert - structure tests clearly
- **Independent tests**: Tests must not depend on execution order or shared mutable state
- **Fast tests**: Unit tests should complete in milliseconds; slow tests go in integration suites

### Test Coverage
- **Coverage target**: Aim for 90%+ line coverage on core business logic
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
- **Update tests with code**: When changing behavior, update tests first (TDD)
- **Flaky test policy**: Fix or quarantine flaky tests immediately
