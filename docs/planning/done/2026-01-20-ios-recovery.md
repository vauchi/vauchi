# P02: iOS Recovery - Wire the UI

**Priority**: CRITICAL
**Status**: ✅ COMPLETE
**Completed**: 2026-01-21

## Summary

iOS Recovery UI was already fully wired. Verified implementation and added tests.

## Implementation

### RecoveryView.swift (fully wired)
- `CreateClaimSheet` calls `viewModel.createRecoveryClaim(oldPkHex:)`
- `CreateVoucherSheet` calls `viewModel.parseRecoveryClaim()` and `viewModel.createRecoveryVoucher()`
- `AddVoucherSheet` calls `viewModel.addRecoveryVoucher()`
- `RecoveryStatusSheet` calls `viewModel.getRecoveryStatus()` and `viewModel.getRecoveryProof()`

### VauchiViewModel.swift (lines 558-612)
- `createRecoveryClaim(oldPkHex:)` → delegates to repository
- `parseRecoveryClaim(claimB64:)` → delegates to repository
- `createRecoveryVoucher(claimB64:)` → delegates to repository
- `addRecoveryVoucher(voucherB64:)` → delegates to repository
- `getRecoveryStatus()` → delegates to repository
- `getRecoveryProof()` → delegates to repository

### VauchiRepository.swift (lines 595-704)
- All FFI bindings implemented with proper error handling
- Type wrappers: `RecoveryClaimInfo`, `RecoveryVoucherInfo`, `RecoveryProgressInfo`

## Tests Added

10 new recovery tests in `VauchiRepositoryTests.swift`:
- `testCreateRecoveryClaim`
- `testRecoveryClaimContainsRequiredFields`
- `testParseRecoveryClaim`
- `testNoActiveRecoveryStatus`
- `testRecoveryStatusAfterClaimCreation`
- `testDefaultRecoveryThreshold`
- `testNoRecoveryProofWhenIncomplete`
- `testCreateVoucherForClaim`
- `testParseClaimBeforeVouching`

All tests trace to `features/contact_recovery.feature` Gherkin scenarios.

## Acceptance Criteria

- [x] "Create Recovery Claim" button calls `createRecoveryClaim()`
- [x] Claim data displayed and copyable
- [x] "Add Voucher" accepts pasted voucher data
- [x] Status screen shows voucher count and threshold
- [x] Error states handled gracefully
- [x] Tests added for recovery functionality
- [ ] Manual test: complete recovery flow on iOS (requires device)
