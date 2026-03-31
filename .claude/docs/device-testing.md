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

```text
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

## Exchange Testing: WDA Banner Workaround

WebDriverAgent's "Automation Running" banner covers the iPhone QR
code during exchange. This causes slow or failed exchanges in
automated tests.

**Pattern: Navigate-then-kill**

1. Use WDA to navigate both devices to the Exchange screen
2. Kill WDA on iPhone (`xcodebuild -stop` or kill the process)
   — the banner disappears, the QR is fully visible
3. Let the exchange complete (camera-to-camera, no automation needed)
4. Restart WDA to verify results (check contact list, take screenshots)

**Why not just skip WDA?** You need WDA to navigate to the exchange
screen and to verify results afterward. The kill window is only
during the camera-to-camera scanning phase.

**Brightness**: Both iOS and Android use 65% screen brightness during
exchange. Higher brightness causes front camera overexposure on the
scanning device, reducing QR decode reliability.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Invalid QR code" | QR data too short / capacity issue | Check logcat for QR data length |
| "Missing display name" | Binding mismatch (`String` vs `String?`) | Rebuild bindings from correct branch |
| Exchange hangs | State machine divergence | Check both devices' logs |
| Exchange slow (~15s+) on iPhone | WDA banner covering QR | Kill WDA during exchange (see above) |
| Exchange slow after `pm clear` | Stale Android Keystore state | `adb uninstall app.vauchi` and reinstall |
| SPM build fails | Missing Info.plist in xcframework | Run `just rebuild-ios` |
| "clock drift" error | Device time out of sync | Fix device Date & Time settings |
| `KeyStoreException: 112` | Stale Android Keystore | `adb uninstall app.vauchi` and reinstall |
