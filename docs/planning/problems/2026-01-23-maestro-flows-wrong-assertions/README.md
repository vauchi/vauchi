# Problem: Maestro Flows Have Incorrect UI Assertions

**Status**: done
**Created**: 2026-01-23
**Priority**: Medium

## Problem Description

The iOS and Android Maestro flows assert UI text that doesn't exist in the actual app:

### Incorrect Assertion
```yaml
- assertVisible: "Identity created"
```

### Actual App UI
- iOS: `"You're all set!"` (ReadyStepView.swift:32)
- Android: `"You're all set!"` (OnboardingScreen.kt:821)

After completing onboarding, both apps show `"Your Card"` on the home screen:
- iOS: HomeView.swift:39
- Android: MainActivity.kt:373

## Impact

- Maestro flows will fail when run against actual app
- E2E tests cannot verify successful identity creation
- CI pipeline cannot automate mobile testing

## Root Cause

Maestro flows were created based on assumed/expected UI rather than verified against actual app implementation.

## Fix

Update all Maestro flows to use correct UI text:
1. Replace `"Identity created"` with `"You're all set!"` or `"Your Card"`
2. Verify all other assertions against actual app UI

## Files to Fix

- `e2e/maestro/ios/create_identity.yaml`
- `e2e/maestro/android/create_identity.yaml`

## Acceptance Criteria

- [ ] All Maestro assertions match actual app UI text
- [ ] Flows verified on real iOS simulator
- [ ] Flows verified on real Android emulator
