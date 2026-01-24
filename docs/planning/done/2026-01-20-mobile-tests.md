# P05: Mobile Test Coverage

**Priority**: HIGH
**Status**: IMPLEMENTED - 2026-01-22
**Effort**: 3 days (estimated) → 1 day (actual)

## Blocker Resolution (2026-01-21)

**Root cause identified**: Symbol stripping removed UniFFI metadata from release builds.

**Fix applied**:
1. Updated `build-bindings.sh` to use `RUSTFLAGS="-Cstrip=none"`
2. Changed Android generation to use `--library` mode (matching iOS)
3. Regenerated Android bindings: 2,184 → 5,393 lines (19 missing types restored)
4. Fixed Android code for new API (constructor syntax, ByteArray params)

**Post-mortem**: See `docs/planning/done/POSTMORTEM-ANDROID-BINDINGS-DRIFT.md`

---

## Implementation Summary (2026-01-22)

### iOS Tests Added

**File**: `ios/VauchiTests/VauchiRepositoryTests.swift`

Added 4 new tests to complement 32 existing tests:
- `testAddRecoveryVoucher()` - Full voucher addition flow
- `testCompleteContactExchange()` - Two-way QR exchange between users
- `testExchangeWithInvalidQrFails()` - Error handling for invalid QR
- `testCannotExchangeWithSelf()` - Self-exchange prevention

**Total iOS FFI tests**: 36+

### Android Instrumented Tests Added

**File**: `android/app/src/androidTest/kotlin/com/vauchi/data/VauchiRepositoryFfiTest.kt`

Created comprehensive instrumented tests that run on device/emulator:
- `testNoIdentityOnFirstLaunch()`
- `testCreateIdentity()`
- `testIdentityHasPublicId()`
- `testIdentityPersistsAcrossSessions()`
- `testInitialCardHasDisplayName()`
- `testAddEmailField()`
- `testAddPhoneField()`
- `testUpdateFieldValue()`
- `testRemoveField()`
- `testGenerateExchangeQr()`
- `testCompleteContactExchange()`
- `testEmptyContactsList()`
- `testExportBackup()`
- `testImportBackup()`
- `testCreateRecoveryClaim()`
- `testRecoveryStatusAfterClaimCreation()`
- `testAddRecoveryVoucher()`
- `testCreateVoucherForClaim()`
- `testListSocialNetworks()`
- `testGetProfileUrl()`

**Total Android FFI tests**: 20+

### Helper Classes

**File**: `android/app/src/androidTest/kotlin/com/vauchi/data/TestContextWrapper.kt`

Context wrapper for isolated test directories.

---

## Acceptance Criteria Status

- [x] iOS: 10+ test cases covering FFI calls (36+ tests)
- [x] Android: 10+ test cases covering FFI calls (20+ instrumented tests)
- [x] Recovery flow tested end-to-end on both platforms
- [ ] CI runs mobile tests (pending infrastructure - see note below)
- [x] Coverage > 20% on critical paths

### CI Note

The current CI pipeline (`.gitlab-ci.yml`) runs Rust tests only. Adding mobile test CI requires:
- **iOS**: macOS runner with Xcode
- **Android**: Runner with Android SDK and emulator for instrumented tests

This is an infrastructure task and should be tracked separately.

---

## Feature Traces

| Test | Feature File | Scenario |
|------|--------------|----------|
| `testCreateIdentity` | `features/identity_management.feature` | Create new identity |
| `testAddRecoveryVoucher` | `features/account_recovery.feature` | Collect vouchers |
| `testCompleteContactExchange` | `features/contact_exchange.feature` | Exchange cards |
| `testExportBackup` | `features/identity_management.feature` | Export backup |

---

## Running Tests

### iOS
```bash
cd ios && xcodebuild -scheme Vauchi test -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Android (Instrumented)
```bash
cd android && ./gradlew connectedAndroidTest
```

---

## Original Problem

- iOS: 2 test files for 25+ Swift files (<4% coverage)
- Android: 1 test file for 20+ Kotlin files (<3% coverage)

FFI integration was completely untested.

## Resolution

- iOS now has 36+ FFI integration tests in `VauchiRepositoryTests.swift`
- Android now has 20+ instrumented FFI tests in `VauchiRepositoryFfiTest.kt`
- Both platforms test identity, cards, exchange, recovery, and backup flows
