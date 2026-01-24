# Problem: E2E Tests Fail When Run In Parallel

**Status**: done (workaround: use --test-threads=1)
**Created**: 2026-01-23
**Priority**: Low

## Problem Description

E2E integration tests fail when run in parallel due to port conflicts on the default relay port (18080). When run sequentially with `--test-threads=1`, all CLI-based tests pass.

## Root Cause

Multiple test suites try to spawn relay servers on the same base port (18080) simultaneously, causing connection failures.

## Solution

Run tests sequentially:
```bash
cargo test --release -- --include-ignored --test-threads=1
```

## Test Results (Sequential Execution)

| Test Suite | Passed | Failed | Notes |
|------------|--------|--------|-------|
| Unit tests | 29/29 | 0 | ✓ All pass |
| cross_platform (CLI) | 3/3 | 0 | ✓ All CLI tests pass |
| cross_platform (Other) | 0/4 | 4 | Expected - missing TUI/Desktop/Maestro |
| five_user_exchange | 3/3 | 0 | ✓ All pass |
| multi_device_sync | 3/3 | 0 | ✓ All pass |
| relay_failover | 3/3 | 0 | ✓ All pass |
| offline_catchup | 2/3 | 1 | `integration_offline_catchup` has assertion issue |

## Remaining Issue

`integration_offline_catchup` fails with an assertion error:
```
assertion `left == right` failed: Device A2 should have 3 contacts
  left: 1
 right: 3
```

This is a test logic or timing issue, not a relay connection problem.

## Future Improvement

For parallel test execution, each test suite should use unique port ranges. This is a nice-to-have optimization, not blocking.
