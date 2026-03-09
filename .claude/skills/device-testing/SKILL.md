---
name: device-testing
description: Physical device GUI testing automation for iOS and Android. Use when running test flows on physical devices, debugging device automation, taking screenshots, or testing onboarding/exchange/settings flows.
model: haiku
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Device GUI Testing

## Quick Start

**FIRST**: Read the full context file before doing anything:
```bash
# Read tool on this file — contains device IDs, PINs, known issues, WDA setup, flow steps
Read _private/docs/testing/device-automation/test-run-context.md
```

**Test runner** (full automated flows):
```bash
bash _private/docs/testing/device-automation/vauchi-gui-test.sh preflight
bash _private/docs/testing/device-automation/vauchi-gui-test.sh onboard-all
bash _private/docs/testing/device-automation/vauchi-gui-test.sh exchange pixel samsung
bash _private/docs/testing/device-automation/vauchi-gui-test.sh settings-check all
```

## Devices

| Device | ID | Automation |
|--------|----|------------|
| Pixel 3a | `034AY1UQS9` | ADB + coordinates (Compose, no uiautomator) |
| Samsung S7 | `9886784a544a484938` | ADB + uiautomator (dynamic element finding) |
| iPhone SE | WDA at device WiFi IP | WDA + accessibilityIdentifier + virtual keyboard |

PIN for all devices: `123456`

## Test Runner

**Location**: `_private/docs/testing/device-automation/vauchi-gui-test.sh`

### Key Actions
- `preflight` — verify devices connected + APK exists + WDA running
- `verify-cameras` — pre-flight + check cameras see each other's screens
- `onboard <device> [name]` — run full onboarding flow
- `onboard-all` — onboard all 3 devices
- `exchange <a> <b>` — guided exchange (prompts for physical actions)
- `settings-check [device]` — screenshot all settings sections
- `screenshot <device> <name>` — single screenshot
- `save-baselines` — save current screenshots as comparison baselines
- `install-all` / `clean-all` — APK management

### Key Helpers

To use helpers ad-hoc (outside the test runner), source the script first:
```bash
source _private/docs/testing/device-automation/vauchi-gui-test.sh help 2>/dev/null
# Now all helpers are available as bash functions
```

| Helper | Usage | Notes |
|--------|-------|-------|
| `wda_ensure_session` | (no args) | Auto-renews stale WDA sessions |
| `ios_type_text "text"` | Text string | Virtual keyboard tapper (French QWERTZ) |
| `ios_tap_by_name "Label"` | Button label text | Tap iOS element by visible name |
| `ios_tap_by_id "a11y.id"` | Accessibility ID | Tap iOS element by identifier |
| `ios_tap x y` | Viewport coords | Tap iOS at coordinates |
| `ios_swipe_up` | [from_y] [to_y] | Scroll iOS content up |
| `ios_source` | [max_chars] | Dump WDA UI tree for debugging |
| `ios_clear_field` | [count] | Backspace N times |
| `samsung_tap_text "Text"` | Button/label text | uiautomator-based tap |
| `samsung_find_element "Text"` | Element text | Returns center x y coords |
| `samsung_handle_biometric` | (no args) | Auto-enters PIN on biometric prompt |
| `adb_tap <device> x y` | pixel/samsung + coords | Tap Android at screen coords |
| `adb_text <device> "text"` | pixel/samsung + text | Type text via ADB |
| `adb_key <device> KEY` | pixel/samsung + keyevent | Send key event |
| `adb_swipe <device> x1 y1 x2 y2` | Coords | Swipe gesture |
| `take_screenshot <device> <name>` | Any device + label | Unified cross-platform screenshot |

## Supporting Files

```
_private/docs/testing/device-automation/
├── vauchi-gui-test.sh          # Main test runner
├── test-run-context.md         # Full context: IDs, PINs, known issues, WDA setup
├── device-maps/
│   ├── pixel-3a.json           # Screen coordinates per screen
│   ├── samsung-s7.json         # uiautomator text + fallback coords
│   └── iphone-se.json          # a11y IDs + fallback coords
├── flows/
│   ├── onboarding-checklist.md
│   ├── exchange-checklist.md
│   └── settings-checklist.md
└── baselines/                  # Screenshot comparison baselines
```

## Automation IDs

### Android (testTag)
Compose elements have `Modifier.testTag("...")` for UI testing:
- Home: `home.settings`, `home.sync`, `home.add_field`, `home.exchange`, `home.contacts`
- Onboarding: `onboarding.get_started`, `.restore`, `.name_field`, `.name_next`, `.info_next`, `.info_skip`, `.preview_confirm`, `.preview_edit`, `.finish_setup`
- Exchange: `exchange.back`, `.camera_switch`, `.done`, `.retry`, `.grant_permission`
- Error: `error.retry`

**Note**: Pixel 3a uiautomator CANNOT find Compose elements. Use testTag with Espresso/ComposeTestRule for instrumented tests, or coordinates for ADB automation.

### iOS (accessibilityIdentifier)
SwiftUI elements have `.accessibilityIdentifier("...")` for WDA automation:
- Tabs: `tab.home`, `tab.contacts`, `tab.exchange`, `tab.settings`
- Onboarding: `onboarding.get_started`, `.restore`, `.name_field`, `.name_continue`, `.phone_field`, `.email_field`, `.info_continue`, `.info_skip`, `.preview_confirm`, `.preview_edit`, `.finish_setup`
- Exchange: `exchange.back`, `.camera_toggle`, `.done`, `.retry`, `.grant_permission`
- Home: `home.sync`, `card.field.add`, `card.empty`

Use `ios_tap_by_id "identifier"` or `ios_tap_by_name "Label"` in the test runner.

## Known Issues & Recipes

See `test-run-context.md` for the full known issues table, common recipes, tool compatibility, and WDA setup instructions.

Key gotchas: Pixel uiautomator can't find Compose elements (use coords). Samsung shows biometric on relaunch (use `samsung_handle_biometric`). WDA sessions go stale (use `wda_ensure_session`). WDA text entry is garbled (use `ios_type_text`).

## Exchange Testing

QR exchange requires **physical device interaction** — cameras must see each other's screens.

1. Run `verify-cameras` to check positioning
2. Run `exchange pixel samsung` — script prompts for physical actions
3. Hold devices steady (QR cycles every 300ms)
4. Check contacts list after completion
