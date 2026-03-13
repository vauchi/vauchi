---
name: ios-device-automation
description: Automate iOS physical device operations — launch apps with arguments, retrieve files, capture logs, take screenshots, and tap/swipe UI via WDA. Use when automating iOS device testing or retrieving data from the iPhone.
---

# iOS Physical Device Automation

## Tool Availability Matrix (iPhone SE, iOS 17.4)

| Tool | Screenshot | UI Tap/Swipe | Log Stream | App Launch | File Access |
|------|-----------|-------------|------------|------------|-------------|
| **WDA** (WebDriverAgent) | Yes | Yes | No | No | No |
| **devicectl** (`xcrun devicectl`) | No | No | **Yes** | Yes | No |
| **pymobiledevice3** | Broken* | No | Broken* | No | Yes |
| **idevicesyslog** | No | No | Broken* | No | No |
| **idb** (fb-idb) | Broken* | Broken* | Broken* | No | No |

\* These tools connect but produce no output or fail with protocol errors on iOS 17.4 physical devices.

**Primary tools**: WDA (UI + screenshots), devicectl (app launch + **log streaming**), pymobiledevice3 (file pull).

## Device Discovery

```bash
# List connected iOS devices
xcrun devicectl list devices

# Current device
IPHONE="07D4C7CE-25C3-59C0-A9DD-F0FD827BEC29"  # iPhone SE (iOS 17.4)
IPHONE_UDID_USB="00008030-000C04AE0ED0402E"      # USB UDID (for idevice* tools)
```

## WebDriverAgent (WDA) — UI Automation + Screenshots

WDA is installed at `/tmp/WebDriverAgent`. It must be running in a terminal for UI automation.

### Start WDA

```bash
# Start WDA (run in a separate terminal or background)
just dt-wda-start
# Or manually:
cd /tmp/WebDriverAgent
xcodebuild -project WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner \
  -destination 'id=00008030-000C04AE0ED0402E' \
  DEVELOPMENT_TEAM=<TEAM_ID> CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates test-without-building
```

Note the `ServerURLHere->http://<IP>:8100<-ServerURLHere` in output.

### Check WDA Status

```bash
WDA="http://localhost:8100"  # or device IP
curl -s "$WDA/status" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('WDA ready:', d.get('value',{}).get('ready', False))
"
```

### Create Session

```bash
WDA="http://<DEVICE_IP>:8100"
SID=$(curl -s -X POST "$WDA/session" -H 'Content-Type: application/json' \
  -d '{"capabilities":{}}' | python3 -c "import sys,json; print(json.load(sys.stdin)['value']['sessionId'])")
echo "Session: $SID"
```

### UI Actions

```bash
# Tap at (X, Y)
curl -s -X POST "$WDA/session/$SID/actions" -H 'Content-Type: application/json' \
  -d '{"actions":[{"type":"pointer","id":"finger1","parameters":{"pointerType":"touch"},"actions":[{"type":"pointerMove","duration":0,"x":X,"y":Y},{"type":"pointerDown","button":0},{"type":"pause","duration":50},{"type":"pointerUp","button":0}]}]}'

# Via just recipe
just dt-ios-tap X Y

# Swipe (x1,y1 → x2,y2)
curl -s -X POST "$WDA/session/$SID/actions" -H 'Content-Type: application/json' \
  -d '{"actions":[{"type":"pointer","id":"finger1","parameters":{"pointerType":"touch"},"actions":[{"type":"pointerMove","duration":0,"x":X1,"y":Y1},{"type":"pointerDown","button":0},{"type":"pointerMove","duration":300,"x":X2,"y":Y2},{"type":"pointerUp","button":0}]}]}'

# Get accessibility tree (find elements)
curl -s "$WDA/session/$SID/source" | python3 -m json.tool | head -50

# Find element by accessibility ID
curl -s -X POST "$WDA/session/$SID/element" -H 'Content-Type: application/json' \
  -d '{"using":"accessibility id","value":"Exchange"}'
```

### Screenshots via WDA

```bash
# Base64 PNG screenshot
curl -s "$WDA/session/$SID/screenshot" | python3 -c "
import sys,json,base64
data = json.load(sys.stdin)['value']
with open('/tmp/ios-screenshot.png','wb') as f:
    f.write(base64.b64decode(data))
print('Saved to /tmp/ios-screenshot.png')
"

# Or via just recipe
just dt-wda-screenshot

# Burst capture
for i in $(seq 1 20); do
    curl -s "$WDA/session/$SID/screenshot" | python3 -c "
import sys,json,base64
data=json.load(sys.stdin)['value']
with open('/tmp/ios-$(printf '%03d' $i).png','wb') as f: f.write(base64.b64decode(data))
"
    sleep 0.5
done
```

## App Lifecycle (via devicectl)

```bash
# Launch app
xcrun devicectl device process launch --device "$IPHONE" app.vauchi.ios

# Launch with command-line arguments
xcrun devicectl device process launch --device "$IPHONE" app.vauchi.ios \
  -- --ble-test discovery

# Terminate app (find PID first — no direct "kill by bundle" command)
# The app must handle termination gracefully
```

**Note**: `--url` deep links are unreliable on cold launch via devicectl. Use `--` arguments instead.

## Log Capture

### Primary: `devicectl --console` (WORKS on iOS 17.4)

The `--console` flag on `devicectl device process launch` captures the app's stdout/stderr in real time. This is the **only reliable CLI log streaming** method for iOS 17.4 physical devices.

```bash
# Launch app and stream logs to terminal
xcrun devicectl device process launch --terminate-existing \
  --device "$IPHONE" --console app.vauchi.ios

# Stream logs to file in background (for automated testing)
xcrun devicectl device process launch --terminate-existing \
  --device "$IPHONE" --console app.vauchi.ios \
  > /tmp/ios-console.log 2>&1 &
DCTL_PID=$!

# ... perform test actions ...

# Read captured logs
cat /tmp/ios-console.log

# Stop (terminates the app too)
kill $DCTL_PID 2>/dev/null
```

**Important**: `--console` blocks until the app terminates. The app is killed when the `devicectl` process is killed. Use `--terminate-existing` to ensure a clean start.

**Captures**: `NSLog()`, `print()`, `os_log()` output, and stderr. Format: `2026-03-08 08:24:02.736 Vauchi[4671:3604018] [Vauchi] Build: v1.0.0 ...`

### Streamed log pattern for Claude agents

```bash
IPHONE="07D4C7CE-25C3-59C0-A9DD-F0FD827BEC29"

# Start log capture in background
xcrun devicectl device process launch --terminate-existing \
  --device "$IPHONE" --console app.vauchi.ios \
  > /tmp/ios-stream.log 2>&1 &
IOS_LOG_PID=$!
sleep 3  # wait for app to launch

# ... perform test actions (WDA taps, etc.) ...

# Read captured logs (non-blocking)
cat /tmp/ios-stream.log

# Stop capture + app
kill $IOS_LOG_PID 2>/dev/null
```

### Secondary: App-level file logging

For logs that persist across sessions, the app can write to Documents/:

```bash
pymobiledevice3 apps pull app.vauchi.ios Documents/ble-diagnostic.log /tmp/ios-result.log
cat /tmp/ios-result.log
```

### Broken tools (do NOT use for log streaming)

- `idevicesyslog` — connects but produces zero log lines on iOS 17.4
- `pymobiledevice3 syslog live` — `os_trace_relay` service responds `RequestSuccessful` but never sends log entries
- `idb log` — protocol errors on physical devices

## File Access

```bash
# Pull file from app container
pymobiledevice3 apps pull app.vauchi.ios Documents/ble-diagnostic.log /tmp/out.log

# Push file to app container
pymobiledevice3 apps push /tmp/config.json app.vauchi.ios Documents/config.json

# List app container files (interactive)
pymobiledevice3 apps afc app.vauchi.ios --documents
```

## Gotchas

- **WDA must stay running** — it dies when the xcodebuild process exits
- **WDA needs rebuild** after iOS app reinstall if provisioning changes
- **Device must stay unlocked** while WDA is running
- **`idb ui tap` is simulator-only** — does NOT work on physical devices despite being installed
- **`idevicescreenshot` requires DeveloperDiskImage** mounted — fails with "Invalid service" on iOS 17.4
- **pymobiledevice3 developer commands** require Developer Mode + DeveloperDiskImage — may need `pymobiledevice3 mounter auto-mount`
- **devicectl has ~1-2s overhead** per command (tunnel acquisition)
- **`devicectl --console` is the only working CLI log stream** — `idevicesyslog`, `pymobiledevice3 syslog`, and `idb log` all fail silently on iOS 17.4
- **`--console` kills the app on exit** — when you kill the `devicectl` process, the app is terminated too
