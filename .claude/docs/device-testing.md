<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Device Testing Quick Reference

## Documentation

Full device testing guide: `_private/docs/testing/manual-testing.md`

## Recipes

| Recipe | Purpose |
|--------|---------|
| `just prepare-device-test [core_dir]` | Full build + install pipeline (both platforms) |
| `just rebuild-ios [core_dir]` | iOS-only rebuild + install |
| `just rebuild-android [core_dir]` | Android-only rebuild + install |
| `just dt-verify-builds` | Check installed versions match on devices |
| `just dt-logs-android` | Dump Android logcat (Vauchi tags) |
| `just dt-logs-android-stream` | Clear + stream Android logs |
| `just dt-logs-ios` | iOS log capture instructions |
| `just dt-screenshot-android [file]` | Screenshot from Android device |
| `just dt-screenshot-ios [file]` | Screenshot from iOS device |

## Build Verification

After installing, both apps log their version at startup:
```
[Vauchi] Build: v1.0 (1) core=0.3.0-dev0
```

Run `just dt-verify-builds` to check that Android and iOS have matching core versions.

## Critical Reminders

### Info.plist Generation

The `_dt-package-ios` recipe generates 3 Info.plist files:
- Device framework slice: `ios-arm64/VauchiMobileFFI.framework/Info.plist`
- Simulator framework slice: `ios-arm64_x86_64-simulator/VauchiMobileFFI.framework/Info.plist`
- Root xcframework: `VauchiMobileFFI.xcframework/Info.plist`

SPM silently fails without these files.

### Worktree Binding Builds

When working in a git worktree (`.worktrees/feature-xyz/`), pass the worktree path:
```bash
just prepare-device-test core/.worktrees/feature-xyz
```

The recipe auto-detects worktrees from the SPM symlink target, but explicit paths are safer.

**Quick check**: After copying bindings, verify new APIs are present:
```bash
grep "peerDisplayName\|coreVersion\|your_new_function" vauchi-platform-swift/Sources/VauchiMobile/vauchi_mobile.swift
```

### Clock Drift

The exchange protocol rejects QR codes with clock drift > 120 seconds (`MAX_CLOCK_DRIFT_SECONDS`). Devices without SIM cards (no carrier time sync) may drift. Fix: Settings > General > Date & Time > Set Automatically.

### Device Reset

- **iOS**: Delete app from home screen (clears Keychain)
- **Android**: `adb uninstall app.vauchi` (NOT `pm clear` — stale Keystore keys can cause `KeyStoreException: 112`)

### Screenshot Commands

```bash
# Android
just dt-screenshot-android failure.png

# iOS (requires tunneld running)
just dt-screenshot-ios failure.png
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Invalid QR code" | QR data too short / capacity issue | Check logcat for QR data length |
| "Missing display name" | Binding mismatch (`String` vs `String?`) | Rebuild bindings from correct branch |
| Exchange hangs | State machine divergence | Check both devices' logs |
| SPM build fails | Missing Info.plist in xcframework | Run `just rebuild-ios` |
| "clock drift" error | Device time out of sync | Fix device Date & Time settings |
| `KeyStoreException: 112` | Stale Android Keystore | `adb uninstall app.vauchi` and reinstall |
