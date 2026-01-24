# P06: End-to-End Testing

**Priority**: HIGH
**Status**: In Progress (Maestro flows created, pending real device testing)
**Effort**: 1 day remaining (manual testing on real devices)

## Goal

Verify cross-platform functionality (iOS ↔ Android ↔ Desktop) before MVP release.

---

## Current State

| Component | Status |
|-----------|--------|
| Rust E2E tests | ✓ All passing (smoke + integration) |
| E2E test infrastructure | ✓ Phase 1 complete (CLI orchestration) |
| Device abstractions | ✓ All stubs created (CLI, TUI, Desktop, Mobile) |
| Relay stability | ✓ Fixed stdout buffer issue for heavy load |
| Manual test guide | ✓ Created |
| Maestro flows | ✓ Created (iOS + Android) |
| Real device testing | ⏳ Pending |

### Device Implementation Status

| Device | File | Status |
|--------|------|--------|
| `CliDevice` | `e2e/src/device/cli.rs` | ✓ Fully implemented |
| `TuiDevice` | `e2e/src/device/tui.rs` | ✓ Implemented with expectrl PTY automation |
| `TauriDevice` | `e2e/src/device/tauri.rs` | ✓ Process management implemented (IPC pending) |
| `MaestroDevice` | `e2e/src/device/maestro.rs` | ✓ Flows created with correct UI assertions |

### Recent Fixes

- Fixed flaky `integration_five_user_exchange` test by redirecting relay stdout/stderr to null
- Fixed card parsing for space-separated CLI output format
- Fixed ratchet responder send chain issue (initiator sends initial card)

---

## Test Matrix

| From | To | Test | Status |
|------|-----|------|--------|
| iOS | Android | Contact exchange via QR | ⏳ |
| Android | iOS | Contact exchange via QR | ⏳ |
| iOS | Desktop | Sync card update | ⏳ |
| Android | Desktop | Sync card update | ⏳ |
| CLI | TUI | Full exchange flow | ⏳ |
| Mobile | Mobile | Recovery voucher exchange | ⏳ |

---

## Infrastructure

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     E2E Test Orchestrator (Rust)                    │
│                  vauchi-e2e-tests crate                             │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │   Relay A    │    │   Relay B    │    │  Test Clock  │          │
│  │  :8080       │    │  :8081       │    │  (simulated) │          │
│  └──────────────┘    └──────────────┘    └──────────────┘          │
└─────────────────────────────────────────────────────────────────────┘
```

### Rust E2E Tests (All Passing)

```
test_relay_update_delivery_happy_path ... ok
test_sync_manager_queue_happy_path ... ok
test_visibility_control_happy_path ... ok
test_sync_update_propagation_happy_path ... ok
test_full_three_user_workflow ... ok
test_contact_exchange_happy_path ... ok
test_multi_device_linking_happy_path ... ok
test_backup_recovery_happy_path ... ok
test_visibility_logic_e2e ... ok
```

---

## Real Device Testing Checklist

### Prerequisites

- [ ] iOS device (iPhone, iOS 16+)
- [ ] Android device (API 26+)
- [ ] Both devices on same network
- [ ] Relay accessible: `curl https://relay.vauchi.app/health`
- [ ] Release builds installed

### Test 1: Contact Exchange (QR Code)

**Goal**: Alice (iOS) exchanges contact with Bob (Android)

1. [ ] Alice: Create identity with name "Alice"
2. [ ] Alice: Generate QR code
3. [ ] Bob: Create identity with name "Bob"
4. [ ] Bob: Scan Alice's QR code
5. [ ] Alice: Confirm exchange
6. [ ] Verify: Both see each other in contacts

**Expected**: Contacts appear within 5 seconds, no errors.

### Test 2: Card Update Sync

1. [ ] Alice: Edit card, add email "alice@example.com"
2. [ ] Wait 10 seconds
3. [ ] Bob: View Alice's card
4. [ ] Verify: Bob sees alice@example.com

### Test 3: Offline → Online Sync

1. [ ] Alice: Enable airplane mode
2. [ ] Alice: Update card
3. [ ] Alice: Disable airplane mode
4. [ ] Wait 30 seconds
5. [ ] Verify: Bob sees update

### Test 4: Recovery Flow

1. [ ] Note recovery phrase during setup
2. [ ] On new device: Select "Recover account"
3. [ ] Enter recovery phrase
4. [ ] Verify: Contacts restored

### Test 5: Visibility Labels

1. [ ] Alice: Create "Work" label with work email
2. [ ] Alice: Assign Bob to "Work" label
3. [ ] Verify: Bob sees work email only

### Test 6: App Lifecycle

1. [ ] Send update while app is backgrounded
2. [ ] Bring app to foreground, verify update
3. [ ] Kill and relaunch app, verify data persists

---

## Sign-Off

| Test | iOS | Android | Notes |
|------|-----|---------|-------|
| QR Exchange | [ ] | [ ] | |
| Card Sync | [ ] | [ ] | |
| Offline Sync | [ ] | [ ] | |
| Recovery | [ ] | [ ] | |
| Visibility | [ ] | [ ] | |
| Lifecycle | [ ] | [ ] | |

**Tester**: _______________
**Date**: _______________
**Build**: _______________

---

## Running Tests

```bash
just e2e-smoke       # Fast smoke tests
just e2e-integration # Full integration tests
just e2e-run all     # All tests including platform stubs
```

---

## Maestro Setup (For Mobile Testing)

Maestro flows are defined in `e2e/maestro/`. See `e2e/maestro/README.md` for details.

### Installation

```bash
curl -Ls "https://get.maestro.mobile.dev" | bash
```

### Required Flows

Each flow maps to a Device trait method:

| Flow | Purpose |
|------|---------|
| `create_identity.yaml` | Create identity with name |
| `generate_qr.yaml` | Generate exchange QR |
| `complete_exchange.yaml` | Complete exchange with QR data |
| `sync.yaml` | Sync with relay |
| `list_contacts.yaml` | List all contacts |
| `add_field.yaml` | Add card field |
| `get_card.yaml` | Get contact card |

---

## Acceptance Criteria

- [x] Manual test guide created
- [x] Rust E2E tests passing (9/9)
- [ ] All matrix combinations tested on real devices
- [ ] Test results documented
- [ ] Sign-off before launch
