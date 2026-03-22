<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

---
name: android-device-automation
description: Automate Android physical device operations — launch activities with intent extras, capture logcat, take screenshots, tap/swipe UI, and stream logs. Use when automating Android device testing or retrieving data from Android devices.
---

# Android Physical Device Automation

Tool: `adb` (Android Debug Bridge) — launch, logs, screenshots, UI input, file access.

## Device Discovery

```bash
# List connected devices
adb devices

# Known devices (update if hardware changes)
PIXEL="034AY1UQS9"            # Pixel 3a (primary test device)
SAMSUNG="9886784a544a484938"   # Samsung S7 (secondary, Android 8)

# Always specify device when multiple connected:
adb -s "$PIXEL" <command>
```

## App Lifecycle

```bash
# Force stop app
adb -s "$PIXEL" shell am force-stop app.vauchi

# Launch main activity
adb -s "$PIXEL" shell am start -n app.vauchi/.MainActivity

# Launch with intent extras (key automation mechanism)
adb -s "$PIXEL" shell am start -n app.vauchi/.diagnostic.BleDiagnosticActivity \
  --es test discovery    # String extra: test=discovery

# Intent extra types
#   --es key value    String extra
#   --ei key value    Int extra
#   --ez key value    Boolean extra
```

**Important**: Always `force-stop` before launching a new test — `onNewIntent` may not re-trigger if activity is already running.

## UI Automation (Physical Devices)

```bash
# Tap at screen coordinates
adb -s "$PIXEL" shell input tap X Y

# Swipe (x1 y1 x2 y2 duration_ms)
adb -s "$PIXEL" shell input swipe 540 1500 540 500 300

# Input text
adb -s "$PIXEL" shell input text "hello"

# Press key events
adb -s "$PIXEL" shell input keyevent KEYCODE_BACK
adb -s "$PIXEL" shell input keyevent KEYCODE_HOME

# Dump UI hierarchy (for finding coordinates)
adb -s "$PIXEL" shell uiautomator dump /sdcard/ui.xml
adb -s "$PIXEL" pull /sdcard/ui.xml /tmp/android-ui.xml
```

**Common key events**: `KEYCODE_BACK` (4), `KEYCODE_HOME` (3), `KEYCODE_ENTER` (66), `KEYCODE_TAB` (61).

## Log Capture

### Non-streaming (dump buffer)

```bash
# Dump current buffer filtered by tag
adb -s "$PIXEL" logcat -d -s Vauchi:I

# Dump with broader filter (Exchange, QR, etc.)
adb -s "$PIXEL" logcat -d | grep -iE "Vauchi|Exchange"

# Save to file
adb -s "$PIXEL" logcat -d -s Vauchi:I > /tmp/android-results.log

# Filter for test results
adb -s "$PIXEL" logcat -d -s Vauchi:I | grep -E 'PASS|FAIL|=== Test'

# Use just recipe
just dt-logs-android
```

### Streaming (live logs)

```bash
# Stream live logs (blocks until killed)
adb -s "$PIXEL" logcat -s Vauchi:I &
LOG_PID=$!
# ... do stuff ...
kill $LOG_PID 2>/dev/null

# Clear buffer then stream (clean capture)
adb -s "$PIXEL" logcat -c
adb -s "$PIXEL" logcat -s Vauchi:I > /tmp/android-live.log &
LOG_PID=$!
# ... run test ...
sleep 10
kill $LOG_PID 2>/dev/null
cat /tmp/android-live.log

# Stream with just recipe
just dt-logs-android-stream
```

### Streamed log pattern for Claude agents

```bash
# Start streaming to file in background
adb -s "$PIXEL" logcat -c
adb -s "$PIXEL" logcat -s Vauchi:* Exchange:* > /tmp/android-stream.log 2>&1 &
LOG_PID=$!

# ... perform actions ...

# Read captured logs (non-blocking)
cat /tmp/android-stream.log

# Stop streaming
kill $LOG_PID 2>/dev/null
```

**Log tags in the app**:
- `Exchange` — exchange session lifecycle (started/cancelled/completed)
- `Vauchi` — general app events, BLE diagnostics
- `Log.i("Vauchi", "[BLE Diag] ...")` — test results (PASS/FAIL)
- `Log.e("Vauchi", ...)` — errors

## Screenshots

```bash
# Direct adb (fastest, no just dependency)
adb -s "$PIXEL" exec-out screencap -p > /tmp/android-screenshot.png

# Via just recipe
just dt-screenshot-android output.png

# Burst capture (e.g., every 0.5s for 10s)
for i in $(seq 1 20); do
    adb -s "$PIXEL" exec-out screencap -p > "/tmp/android-$(printf '%03d' $i).png"
    sleep 0.5
done
```

## File Access

```bash
# Pull file from app storage (requires run-as or debuggable app)
adb -s "$PIXEL" shell run-as app.vauchi cat files/data.json > /tmp/data.json

# List app files
adb -s "$PIXEL" shell run-as app.vauchi ls files/

# Push file to shared storage
adb -s "$PIXEL" push /tmp/config.json /sdcard/Download/config.json
```

## Install APK

```bash
# Install on specific device
adb -s "$PIXEL" install -r android/app/build/outputs/apk/debug/app-debug.apk

# Install on all connected devices
for d in $(adb devices | grep 'device$' | awk '{print $1}'); do
    adb -s "$d" install -r android/app/build/outputs/apk/debug/app-debug.apk
done
```

## Gotchas

- **Multiple devices**: Always use `-s <DEVICE_ID>` — bare `adb` fails with "more than one device/emulator"
- **Samsung S7 (Android 8, API 26)**: No `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` permissions needed (only `ACCESS_FINE_LOCATION`). May crash on launch due to ABI issues.
- **Pixel 3a**: Primary test device, reliable for QR exchange testing
- **logcat buffer**: Fills up fast — system noise can push app logs out. Always capture logs to file during tests.
- **`force-stop` kills everything**: Any GATT server running on that device stops too
- **logcat `-s Vauchi:I`** filters to Info level only — use `Vauchi:*` for all levels including Debug
