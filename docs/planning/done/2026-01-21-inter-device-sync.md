# Planning: Inter-Device Sync Implementation

**Date**: 2026-01-21
**Status**: Complete
**Severity**: P0 - Required for multi-device MVP
**Related**: [Post-mortem](../post-mortems/2026-01-21-multi-device-sync-postmortem.md)
**Follow-up**: [Polish tasks](../todo/2026-01-23-inter-device-sync-polish.md)

---

## Problem Statement

When a user has multiple linked devices (e.g., phone + tablet + desktop), changes made on one device do not propagate to others. This includes:
- Contacts added via exchange
- Contact card field updates
- Visibility rule changes
- Contact removals

**Current state**: Core library has sync infrastructure, but CLI/apps don't use it.

---

## What Already Exists (vauchi-core)

| Component | Location | Status |
|-----------|----------|--------|
| SyncItem types | `sync/device_sync.rs` | ✅ Implemented |
| InterDeviceSyncState | `sync/device_sync.rs` | ✅ Implemented |
| DeviceSyncOrchestrator | `sync/device_orchestrator.rs` | ✅ Implemented |
| Version vectors | `sync/device_sync.rs` | ✅ Implemented |
| Device-to-device encryption | `sync/device_orchestrator.rs` | ✅ Implemented |
| Storage persistence | `storage/device.rs` | ✅ Implemented |
| CardDelta encoding | `sync/delta.rs` | ✅ Implemented |

**Key APIs available:**
```rust
// Record a local change (queues to all other devices)
orchestrator.record_local_change(SyncItem::ContactAdded { ... })?;

// Get pending items for a device
let items = orchestrator.pending_for_device(&device_id);

// Encrypt for transmission
let ciphertext = orchestrator.encrypt_for_device(&target_public_key, &plaintext)?;

// Process incoming items (with conflict resolution)
orchestrator.process_incoming(items)?;

// Mark as synced after successful delivery
orchestrator.mark_synced(&device_id, version)?;
```

---

## What's Missing

### 1. Relay Protocol Enhancement
- No `DeviceSyncMessage` type in relay protocol
- Relay routes by user public key, not device ID
- No device-level blob storage

### 2. Application Integration (CLI)
- Contact mutations don't trigger `record_local_change()`
- `vauchi sync` doesn't check for inter-device pending items
- No background sync mechanism

### 3. Automatic Triggers
- No hooks when contacts are added/modified
- Manual API calls required for everything

---

## Proposed Solution

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User's Identity                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                       │
│  │ Device A │    │ Device B │    │ Device C │                       │
│  │ (Phone)  │    │ (Tablet) │    │ (Desktop)│                       │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘                       │
│       │               │               │                             │
│       └───────────────┼───────────────┘                             │
│                       │                                             │
│              DeviceSyncOrchestrator                                 │
│              (per-device instance)                                  │
└───────────────────────┼─────────────────────────────────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │  Relay Server   │
              │  (message hub)  │
              └─────────────────┘
```

### Phase 1: Relay Protocol Enhancement

**New message type in relay:**
```rust
DeviceSyncMessage {
    identity_id: String,        // User's public ID (for routing)
    target_device_id: [u8; 32], // Specific device to deliver to
    sender_device_id: [u8; 32], // Sending device
    encrypted_payload: Vec<u8>, // ECDH-encrypted SyncItems
    version: u64,               // For ordering/dedup
}
```

**Relay changes:**
1. Add `device_sync_messages` table to storage
2. Index by `(identity_id, target_device_id)`
3. Deliver pending device messages after handshake
4. Support acknowledgment to delete delivered messages

**Files to modify:**
- `relay/src/handler.rs` - Add message handling
- `relay/src/storage.rs` - Add device-level storage
- `relay/src/protocol.rs` - Add message type (if exists)

### Phase 2: CLI Integration

**2a. Record changes when contacts mutate**

In `cli/src/commands/exchange.rs`, after adding a contact:
```rust
// After: wb.add_contact(contact)?;
let sync_item = SyncItem::ContactAdded {
    contact: contact.clone(),
    timestamp: current_timestamp(),
};
if let Some(registry) = wb.storage().load_device_registry()? {
    let mut orchestrator = DeviceSyncOrchestrator::new(
        wb.storage(),
        identity.create_device_info(),
        registry,
    );
    orchestrator.record_local_change(sync_item)?;
}
```

**2b. Send pending items during sync**

In `cli/src/commands/sync.rs`, add new function:
```rust
fn sync_to_other_devices(
    wb: &Vauchi<WebSocketTransport>,
    socket: &mut WebSocket<...>,
) -> Result<usize> {
    let identity = wb.identity().ok_or(...)?;
    let registry = wb.storage().load_device_registry()?.ok_or(...)?;

    let orchestrator = DeviceSyncOrchestrator::new(
        wb.storage(),
        identity.create_device_info(),
        registry.clone(),
    );

    let mut sent = 0;
    for device in registry.active_devices() {
        if device.device_id == *identity.device_id() {
            continue; // Skip self
        }

        let pending = orchestrator.pending_for_device(&device.device_id);
        if pending.is_empty() {
            continue;
        }

        // Serialize and encrypt
        let payload = serde_json::to_vec(&pending)?;
        let encrypted = orchestrator.encrypt_for_device(
            device.exchange_public_key(),
            &payload,
        )?;

        // Send to relay
        let msg = DeviceSyncMessage {
            identity_id: identity.public_id(),
            target_device_id: device.device_id,
            sender_device_id: *identity.device_id(),
            encrypted_payload: encrypted,
            version: orchestrator.version_vector().get(identity.device_id()),
        };

        // ... send via socket ...
        sent += 1;
    }

    Ok(sent)
}
```

**2c. Receive items from other devices**

```rust
fn receive_device_sync_messages(
    wb: &Vauchi<WebSocketTransport>,
    messages: Vec<DeviceSyncMessage>,
) -> Result<usize> {
    let identity = wb.identity().ok_or(...)?;
    let registry = wb.storage().load_device_registry()?.ok_or(...)?;

    let mut orchestrator = DeviceSyncOrchestrator::new(
        wb.storage(),
        identity.create_device_info(),
        registry.clone(),
    );

    let mut processed = 0;
    for msg in messages {
        // Find sender device in registry
        let sender = registry.find_device(&msg.sender_device_id).ok_or(...)?;

        // Decrypt
        let payload = orchestrator.decrypt_from_device(
            sender.exchange_public_key(),
            &msg.encrypted_payload,
        )?;

        // Parse SyncItems
        let items: Vec<SyncItem> = serde_json::from_slice(&payload)?;

        // Apply with conflict resolution
        orchestrator.process_incoming(items)?;
        processed += 1;
    }

    Ok(processed)
}
```

### Phase 3: Card Update Triggers

When a card field is updated, record the change:

In `cli/src/commands/card.rs`:
```rust
pub fn add_field(config: &CliConfig, field_type: &str, label: &str, value: &str) -> Result<()> {
    let wb = open_vauchi(config)?;

    // ... existing add logic ...

    // Record sync item
    let sync_item = SyncItem::CardUpdated {
        field_label: label.to_string(),
        new_value: value.to_string(),
        timestamp: current_timestamp(),
    };
    record_sync_item(&wb, sync_item)?;

    Ok(())
}
```

---

## Implementation Order

### Sprint 1: Relay Enhancement ✅ COMPLETE
1. [x] Add `DeviceSyncMessage` to relay protocol
2. [x] Add `device_sync_messages` table to relay storage
3. [x] Update handler to store/deliver device sync messages
4. [x] Add tests for relay device routing

### Sprint 2: CLI Send/Receive ✅ COMPLETE
5. [x] Add `sync_to_other_devices()` to sync command
6. [x] Add `receive_device_sync_messages()` to sync command
7. [x] Integrate with existing sync flow
8. [x] Add E2E test for basic device sync (test_contact_sync_across_devices passes)

### Sprint 3: Automatic Triggers (Partial)
9. [x] Add `record_sync_item()` helper
10. [x] Hook contact addition in exchange.rs
11. [ ] Hook card field updates in card.rs
12. [ ] Hook visibility changes in labels.rs
13. [ ] Hook contact removal

### Sprint 4: GUI Updates ✅ COMPLETE
14. [x] Update Android app sync command (via vauchi-mobile)
15. [x] Update iOS app sync command (via vauchi-mobile)
16. [x] Update TUI sync command
17. [x] Update Desktop app sync command

### Sprint 5: Testing & Polish
18. [x] Update E2E tests to verify sync (test_contact_sync_across_devices passing)
19. [ ] Add conflict resolution tests
20. [ ] Performance testing with many devices
21. [ ] Documentation

---

## Testing Strategy

### Unit Tests (Core)
- Already exist for DeviceSyncOrchestrator
- Add tests for new relay message types

### Integration Tests (CLI)
```rust
#[test]
fn test_contact_added_creates_sync_item() {
    // 1. Initialize identity with 2 devices
    // 2. Add contact on device 1
    // 3. Verify SyncItem::ContactAdded queued for device 2
}

#[test]
fn test_sync_delivers_to_other_device() {
    // 1. Device 1 adds contact, queues sync item
    // 2. Device 1 syncs (sends to relay)
    // 3. Device 2 syncs (receives from relay)
    // 4. Verify device 2 has contact
}
```

### E2E Tests
Update existing failing tests:
- `test_contact_sync_across_devices`
- `test_five_user_full_exchange`
- `test_mixed_device_count_exchange`

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Conflict resolution edge cases | Medium | Medium | Extensive testing, fallback to manual merge |
| Relay storage growth | Medium | Low | TTL expiry, configurable limits |
| Message ordering issues | Low | High | Version vectors, idempotent operations |
| Encryption key mismatch | Low | High | Validate device registry consistency |

---

## Success Criteria

1. **Basic sync**: Contact added on device A appears on device B after sync
2. **Conflict handling**: Concurrent edits resolve deterministically
3. **Offline support**: Changes queue and sync when back online
4. **E2E tests pass**: All multi-device E2E tests green

---

## Estimated Effort

| Phase | Effort |
|-------|--------|
| Phase 1: Relay | 2-3 days |
| Phase 2: CLI | 2-3 days |
| Phase 3: Triggers | 1-2 days |
| Phase 4: Testing | 2-3 days |
| **Total** | **7-11 days** |

---

## Dependencies

- Relay must be updated before CLI changes
- Core library already has all needed infrastructure
- No external dependencies needed

---

## References

- Core sync implementation: `core/vauchi-core/src/sync/`
- Device orchestrator tests: `core/vauchi-core/tests/sync_device_orchestrator_tests.rs`
- Relay handler: `relay/src/handler.rs`

---

## Appendix: Device Linking Sync Fix

*Merged from: 2026-01-21-multi-device-sync-fix.md*

### Problem

When a new device links to an existing identity, it doesn't receive the contacts that were exchanged on the primary device.

### Root Causes

**Bug 1**: `device complete` doesn't send contacts
- File: `cli/src/commands/device.rs:250`
- Fix: Use `process_request_with_sync()` instead of `process_request()`

**Bug 2**: `device finish` doesn't apply received contacts
- File: `cli/src/commands/device.rs:330-338`
- Fix: Call `orchestrator.apply_full_sync(payload)` after receiving

### Fix Steps

**Step 1: Update `complete()` function**

```rust
use vauchi_core::sync::{DeviceSyncOrchestrator, DeviceSyncPayload};

// Create sync payload with all existing contacts
let sync_orchestrator = DeviceSyncOrchestrator::new(
    wb.storage(),
    identity.current_device().clone(),
    registry.clone(),
);
let sync_payload = sync_orchestrator.create_full_sync_payload()?;
let sync_json = serde_json::to_string(&sync_payload)?;

let (encrypted_response, updated_registry, new_device) =
    initiator.process_request_with_sync(&encrypted_request, &sync_json)?;
```

**Step 2: Update `finish()` function**

```rust
if !response.sync_payload_json().is_empty() {
    if let Ok(payload) = DeviceSyncPayload::from_json(response.sync_payload_json()) {
        let mut orchestrator = DeviceSyncOrchestrator::new(
            wb.storage(),
            identity.current_device().clone(),
            response.registry().clone(),
        );
        orchestrator.apply_full_sync(payload)?;
        display::info(&format!(
            "Synced {} contacts from existing device.",
            orchestrator.contact_count()
        ));
    }
}
```

### Verification

```bash
just e2e-run test_contact_sync_across_devices
just e2e-run test_five_user_full_exchange
just e2e-run test_mixed_device_count_exchange
```
