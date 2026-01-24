# Cross-Platform E2E Test Guide

Manual test procedures for verifying cross-platform compatibility before release.

## Prerequisites

- iOS device/simulator with Vauchi app
- Android device/emulator with Vauchi app
- Desktop app (macOS/Linux/Windows)
- Test relay running (`cargo run -p vauchi-relay`)
- All apps configured to use same relay URL

## Test Matrix

| # | Test | From | To | Priority |
|---|------|------|-----|----------|
| 1 | Contact Exchange | iOS | Android | P0 |
| 2 | Contact Exchange | Android | iOS | P0 |
| 3 | Card Update Sync | iOS | Desktop | P0 |
| 4 | Card Update Sync | Android | Desktop | P0 |
| 5 | Recovery Voucher | iOS | Android | P1 |
| 6 | Recovery Voucher | Android | iOS | P1 |
| 7 | CLI ↔ TUI Exchange | CLI | TUI | P1 |

---

## Test 1: Contact Exchange (iOS → Android)

**Scenario**: Alice (iOS) exchanges contact with Bob (Android)

### Steps

1. **Alice (iOS)**
   - [ ] Open Vauchi app
   - [ ] Tap "Exchange" tab
   - [ ] QR code displays
   - [ ] Note: QR has expiry timer (60s default)

2. **Bob (Android)**
   - [ ] Open Vauchi app
   - [ ] Tap "Scan QR" button
   - [ ] Scan Alice's QR code
   - [ ] Confirmation shows "Added Alice"

3. **Verify on Alice (iOS)**
   - [ ] Alice receives notification "Bob added you"
   - [ ] Bob appears in Contacts list
   - [ ] Bob's card shows his fields

4. **Verify on Bob (Android)**
   - [ ] Alice appears in Contacts list
   - [ ] Alice's card shows her fields

### Expected Result
- Both users have each other as verified contacts
- Cards display correctly on both platforms

---

## Test 2: Contact Exchange (Android → iOS)

**Scenario**: Bob (Android) exchanges contact with Alice (iOS)

### Steps

1. **Bob (Android)**
   - [ ] Open Vauchi app
   - [ ] Tap "Show my QR"
   - [ ] QR code displays

2. **Alice (iOS)**
   - [ ] Tap "Scan" in Exchange view
   - [ ] Scan Bob's QR code
   - [ ] Confirmation shows "Added Bob"

3. **Verify Bidirectional**
   - [ ] Both have each other in contacts
   - [ ] Cards display correctly

---

## Test 3: Card Update Sync (iOS → Desktop)

**Scenario**: User updates card on iOS, Desktop receives update

### Prerequisites
- Same identity on both devices (via backup/restore)
- Both connected to relay

### Steps

1. **iOS**
   - [ ] Edit card: Add new field (e.g., "Work Email")
   - [ ] Save changes
   - [ ] Force sync (pull down to refresh)

2. **Desktop**
   - [ ] Wait for sync (up to 30s)
   - [ ] Or manually trigger sync
   - [ ] Verify new field appears

### Expected Result
- Desktop shows new field within 30 seconds
- Field value matches iOS

---

## Test 4: Card Update Sync (Android → Desktop)

Same as Test 3, but initiated from Android.

### Steps

1. **Android**
   - [ ] Edit card: Modify existing field
   - [ ] Save and sync

2. **Desktop**
   - [ ] Verify update appears
   - [ ] Field value matches Android

---

## Test 5: Recovery Voucher Exchange (iOS → Android)

**Scenario**: Alice (iOS) helps Bob (Android) recover lost identity

### Prerequisites
- Alice and Bob were previously contacts
- Bob has new Android device with fresh Vauchi install

### Steps

1. **Bob (Android - New Device)**
   - [ ] Create new identity (or restore from backup)
   - [ ] Go to Settings → Recovery
   - [ ] Create recovery claim for old public key
   - [ ] Show claim QR or share claim string

2. **Alice (iOS)**
   - [ ] Receive Bob's recovery claim (scan QR or paste)
   - [ ] Verify claim shows Bob's old public key
   - [ ] Tap "Create Voucher"
   - [ ] Share voucher with Bob

3. **Bob (Android)**
   - [ ] Add Alice's voucher
   - [ ] Check recovery progress (need 3+ vouchers typically)

### Expected Result
- Voucher creation succeeds
- Bob's recovery progress shows 1 voucher from Alice

---

## Test 6: Recovery Voucher Exchange (Android → iOS)

Same as Test 5, but Alice is on Android and Bob is on iOS.

---

## Test 7: CLI ↔ TUI Exchange

**Scenario**: Test exchange between command-line tools

### Setup
```bash
# Terminal 1 - TUI
cargo run -p vauchi-tui

# Terminal 2 - CLI
cargo run -p vauchi-cli
```

### Steps

1. **TUI**
   - [ ] Create identity if needed
   - [ ] Navigate to Exchange screen
   - [ ] Generate QR (displays as ASCII)

2. **CLI**
   - [ ] Run: `vauchi exchange scan <QR_DATA>`
   - [ ] Or use: `vauchi exchange complete <QR_STRING>`

3. **Verify**
   - [ ] Both show each other in contacts
   - [ ] `vauchi contacts list` shows new contact

---

## Checklist Summary

### P0 (Must Pass for Launch)
- [ ] Test 1: iOS → Android exchange
- [ ] Test 2: Android → iOS exchange
- [ ] Test 3: iOS → Desktop sync
- [ ] Test 4: Android → Desktop sync

### P1 (Should Pass)
- [ ] Test 5: iOS → Android recovery
- [ ] Test 6: Android → iOS recovery
- [ ] Test 7: CLI ↔ TUI exchange

---

## Troubleshooting

### QR Code Won't Scan
- Ensure camera permissions granted
- Check QR isn't expired (60s default)
- Try adjusting distance/lighting

### Contacts Not Syncing
- Check network connectivity
- Verify relay URL matches on both devices
- Force sync manually
- Check relay server logs for errors

### Recovery Voucher Fails
- Ensure claim hasn't expired
- Verify public keys match expected values
- Check that voucher hasn't already been used

---

## Test Environment

Document test environment for each run:

```
Date: ___________
Tester: ___________

iOS Device: __________ (iOS version: ______)
Android Device: __________ (Android version: ______)
Desktop: __________ (OS: ______)

Relay URL: __________
App Versions:
  - iOS: __________
  - Android: __________
  - Desktop: __________
  - CLI/TUI: __________

Notes:
```

---

## Sign-Off

| Test | Result | Tester | Date | Notes |
|------|--------|--------|------|-------|
| 1    |        |        |      |       |
| 2    |        |        |      |       |
| 3    |        |        |      |       |
| 4    |        |        |      |       |
| 5    |        |        |      |       |
| 6    |        |        |      |       |
| 7    |        |        |      |       |

**Release Approved**: [ ] Yes / [ ] No

**Signed**: _________________ **Date**: _________
