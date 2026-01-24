# Problem: Device Sync Orchestrator Overwrites State

**Status**: done
**Created**: 2026-01-23
**Priority**: High

## Problem Description

The `integration_offline_catchup` E2E test was failing because device A2 only had 1 contact instead of 3 after syncing. The test creates 3 exchanges (Alice with Bob, Carol, Dave) and expects all contacts to sync from device A1 to device A2.

## Impact

- Multi-device contact synchronization broken
- Only the last contact added was synced to linked devices
- Device linking feature incomplete

## Root Cause

The `record_contact_for_device_sync()` function in `cli/src/commands/sync.rs` (and `record_contact_added()` in `exchange.rs`) was using `DeviceSyncOrchestrator::new()` which creates fresh empty state for each device. This meant:

1. When Alice adds Bob as contact → orchestrator created (empty) → adds Bob → saves state
2. When Alice adds Carol → NEW orchestrator created (empty again) → adds Carol → OVERWRITES state (Bob lost!)
3. When Alice adds Dave → NEW orchestrator (empty again) → adds Dave → OVERWRITES (Carol lost!)

The result: only the last contact (Dave) was synced to other devices.

## Evidence

From `cli/src/commands/sync.rs`:
```rust
// BUG: Creates fresh orchestrator instead of loading existing state
let mut orchestrator = DeviceSyncOrchestrator::new(
    wb.storage(),
    identity.create_device_info(),
    registry,
);
```

Should use `DeviceSyncOrchestrator::load()` which loads existing sync state from storage.

## Solution Implemented

Changed both `record_contact_for_device_sync()` in `sync.rs` and `record_contact_added()` in `exchange.rs` to use `DeviceSyncOrchestrator::load()` with a fallback to `new()` for first-time use:

```rust
let mut orchestrator = DeviceSyncOrchestrator::load(
    wb.storage(),
    identity.create_device_info(),
    registry,
).unwrap_or_else(|_| DeviceSyncOrchestrator::new(
    wb.storage(),
    identity.create_device_info(),
    identity.initial_device_registry(),
));
```

## Acceptance Criteria

- [x] `integration_offline_catchup` test passes
- [x] `integration_card_catchup` test passes
- [x] `integration_extended_offline` test passes
- [x] All `multi_device_sync` tests pass
- [x] No regressions in other E2E tests

## Files Changed

- `cli/src/commands/sync.rs` - Fixed `record_contact_for_device_sync()`
- `cli/src/commands/exchange.rs` - Fixed `record_contact_added()`

## Related

- Test file: `e2e/tests/offline_catchup.rs`
- Core module: `core/vauchi-core/src/sync/device_orchestrator.rs`
