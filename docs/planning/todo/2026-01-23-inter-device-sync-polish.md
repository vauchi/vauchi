# Planning: Inter-Device Sync Polish

**Date**: 2026-01-23
**Status**: Todo
**Severity**: P2 - Enhancement
**Parent**: [Inter-Device Sync Implementation](../done/2026-01-21-inter-device-sync.md)

---

## Overview

Follow-up work from the inter-device sync implementation. Core sync functionality is complete and working. This covers remaining hooks and testing polish.

---

## Remaining Work

### Automatic Trigger Hooks (Sprint 3 Continuation)

These hooks auto-record sync items when data changes locally:

| Hook | File | Priority |
|------|------|----------|
| Card field updates | `cli/src/commands/card.rs` | Medium |
| Visibility changes | `cli/src/commands/labels.rs` | Medium |
| Contact removal | `cli/src/commands/contacts.rs` | Medium |

**Implementation pattern:**
```rust
// After mutation succeeds:
let sync_item = SyncItem::CardUpdated { ... };
record_sync_item(&wb, sync_item)?;
```

### Testing & Documentation (Sprint 5 Continuation)

| Task | Priority |
|------|----------|
| Add conflict resolution tests | High |
| Performance testing with many devices (5+) | Medium |
| Update user documentation | Low |

---

## Success Criteria

1. All mutation commands automatically queue sync items
2. Conflict resolution has test coverage for edge cases
3. Sync performs acceptably with 5+ linked devices

---

## Dependencies

- Core inter-device sync complete (done)
- No blocking dependencies

---

## References

- Parent implementation: `_docs/planning/done/2026-01-21-inter-device-sync.md`
- Core sync code: `core/vauchi-core/src/sync/`
- CLI commands: `cli/src/commands/`
