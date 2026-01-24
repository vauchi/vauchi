# P6: Recovery UI for Mobile

**Status**: ✅ COMPLETE
**Priority**: HIGH
**Completed**: 2026-01-22
**Feature File**: `features/contact_recovery.feature`

## Summary

Recovery workflow is fully implemented across all layers:
- ✅ Core library (vauchi-core)
- ✅ Mobile bindings (vauchi-mobile)
- ✅ Android UI (RecoveryScreen.kt with full functionality)
- ✅ iOS UI (RecoveryView.swift with full functionality)
- ✅ Tests (unit + integration)

## Current Implementation Status

### Core (`vauchi-core/src/recovery/mod.rs`) ✅ COMPLETE
| Type | Status | Description |
|------|--------|-------------|
| `RecoveryClaim` | ✅ | QR data for claiming old identity |
| `RecoveryVoucher` | ✅ | Signed voucher from contact |
| `RecoveryProof` | ✅ | Collection of vouchers (threshold-based) |
| `RecoverySettings` | ✅ | User preferences (thresholds) |
| `RecoveryReminder` | ✅ | "Remind me later" tracking |
| `RecoveryConflict` | ✅ | Conflicting claims detection |
| `RecoveryRevocation` | ✅ | Revoke proof with old key |
| `VerificationResult` | ✅ | High/Medium/Low confidence |

### Mobile Bindings (`vauchi-mobile/src/lib.rs`) ✅ COMPLETE
| Method | Status | Returns |
|--------|--------|---------|
| `create_recovery_claim(old_pk_hex)` | ✅ | `MobileRecoveryClaim` |
| `parse_recovery_claim(claim_b64)` | ✅ | `MobileRecoveryClaim` |
| `create_recovery_voucher(claim_b64)` | ✅ | `MobileRecoveryVoucher` |
| `add_recovery_voucher(voucher_b64)` | ✅ | `MobileRecoveryProgress` |
| `get_recovery_status()` | ✅ | `Option<MobileRecoveryProgress>` |
| `get_recovery_proof()` | ✅ | `Option<String>` |
| `verify_recovery_proof(proof_b64)` | ✅ | `MobileRecoveryVerification` |

### Types (`vauchi-mobile/src/types.rs`) ✅ COMPLETE
- `MobileRecoveryClaim` - old_pk, new_pk, claim_data, is_expired
- `MobileRecoveryVoucher` - voucher_pk, voucher_data
- `MobileRecoveryProgress` - vouchers_collected, vouchers_needed, is_complete
- `MobileRecoveryVerification` - confidence, known_vouchers, recommendation

### CLI (`vauchi-cli/src/commands/recovery.rs`) ✅ COMPLETE
All commands working: `claim`, `vouch`, `add-voucher`, `status`, `proof`, `verify`

### Desktop (`vauchi-desktop/src-tauri/src/commands/recovery.rs`) ✅ COMPLETE
All Tauri commands working.

---

## Implementation Status: ✅ COMPLETE

### Android (`android/app/.../ui/RecoveryScreen.kt`) ✅ COMPLETE

Fully implemented with:
- Two tabs: "Recover Identity" and "Help Others"
- Recovery progress display with progress bar
- Add Voucher dialog for paste-in voucher data
- Create Recovery Claim dialog with old public key input
- Help Others flow with claim verification and voucher creation
- MainViewModel.kt has all 6 recovery suspend functions
- VauchiRepository.kt wraps UniFFI bindings
- Unit tests in RecoveryScreenTest.kt (12 test cases)

### iOS (`ios/Vauchi/Views/RecoveryView.swift`) ✅ COMPLETE

Fully implemented with:
- Two tabs: "Recover" and "Help Others"
- RecoverIdentityTab with info cards, settings display, action buttons
- HelpOthersTab with vouch workflow
- Sheets: CreateClaimSheet, CreateVoucherSheet, AddVoucherSheet, RecoveryStatusSheet
- VauchiViewModel.swift has all recovery async methods
- VauchiRepository.swift wraps bindings with proper error handling
- Recovery tab integrated into ContentView.swift TabView
- Tests in RecoveryTests.swift

---

## Implementation Tasks

## Implementation Reference

The implementation follows the patterns established in the codebase:

**Android Architecture:**
- UI: Jetpack Compose with Material 3
- State: ViewModel with StateFlow
- Data: Repository pattern wrapping UniFFI bindings

**iOS Architecture:**
- UI: SwiftUI with sheets for modals
- State: ObservableObject ViewModel
- Data: Repository pattern with async/await

See actual implementation files for reference.

---

## Verification (per contact_recovery.feature)

Test scenarios from feature file:
1. ✅ Create recovery claim (Scenario: Generate recovery claim QR code)
2. ✅ Voucher recognizes contact (Scenario: Voucher recognizes old contact)
3. ✅ Create voucher (Scenario: Create voucher after in-person verification)
4. ✅ Collect multiple vouchers (Scenario: Collect multiple vouchers)
5. ✅ Threshold met creates proof (Scenario: Create recovery proof when threshold met)
6. ✅ Verify proof with mutual contacts (Scenario: Verify recovery with mutual contacts)
7. ✅ Low confidence warning (Scenario: Isolated contact receives recovery proof)

---

## Files Implemented

| Platform | File | Status |
|----------|------|--------|
| Android | `android/app/.../ui/RecoveryScreen.kt` | ✅ Full UI with two tabs |
| Android | `android/app/.../MainViewModel.kt` | ✅ 6 recovery methods |
| Android | `android/app/.../data/VauchiRepository.kt` | ✅ Bindings wrapper |
| iOS | `ios/Vauchi/Views/RecoveryView.swift` | ✅ Full UI with sheets |
| iOS | `ios/Vauchi/ViewModels/VauchiViewModel.swift` | ✅ 6 recovery methods |
| iOS | `ios/Vauchi/Services/VauchiRepository.swift` | ✅ Bindings wrapper |
| iOS | `ios/Vauchi/ContentView.swift` | ✅ Recovery tab added |

---

## Success Criteria

- [x] Android: Can create recovery claim from UI
- [x] Android: Can add vouchers and see progress
- [x] Android: Can copy completed proof
- [x] Android: Can vouch for others' recovery
- [x] iOS: Recovery tab exists in navigation
- [x] iOS: Can create recovery claim from UI
- [x] iOS: Can add vouchers and see progress
- [x] iOS: Can copy completed proof
- [x] iOS: Can vouch for others' recovery
- [ ] Cross-platform: Android user can vouch for iOS user's recovery (requires E2E test)
