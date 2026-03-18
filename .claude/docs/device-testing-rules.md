## Device Testing Rules (MANDATORY)

### Build Process

- Always use `just prepare-device-test` — never manual cross-compilation
- Verify build versions match on both devices before testing (`just dt-verify-builds`)
- Never amend commits based on different binding generations (worktree vs working dir)

### Testing Discipline

- **One variable at a time** — never change QR format + protocol + bindings simultaneously
- Capture logs before and after each test
- On failure: screenshot + logs + exact repro steps before attempting fixes
- Test same-platform first (Android↔Android), then cross-platform on physical devices

### iOS UI Automation (WebDriverAgent)

Android has `adb shell input tap X Y` for UI automation on physical devices. iOS has no built-in equivalent — use WebDriverAgent (WDA).

**Setup** (one-time per device):
```bash
# Clone WDA
git clone https://github.com/appium/WebDriverAgent.git /tmp/WebDriverAgent

# Build for device (replace device ID and team)
cd /tmp/WebDriverAgent
xcodebuild -project WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner \
  -destination 'id=<DEVICE_UDID>' \
  DEVELOPMENT_TEAM=<TEAM_ID> CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates build-for-testing
```

**Running WDA** (each session):
```bash
cd /tmp/WebDriverAgent
xcodebuild -project WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner \
  -destination 'id=<DEVICE_UDID>' \
  DEVELOPMENT_TEAM=<TEAM_ID> CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates test-without-building
```
- First run requires Touch ID / passcode authentication on device ("Enable UI Automation")
- Server URL printed in output: `ServerURLHere->http://<DEVICE_IP>:8100<-ServerURLHere`

**Creating a session:**
```bash
WDA="http://<DEVICE_IP>:8100"
SID=$(curl -s -X POST "$WDA/session" -H 'Content-Type: application/json' \
  -d '{"capabilities":{}}' | python3 -c "import sys,json; print(json.load(sys.stdin)['value']['sessionId'])")
```

**Tap at coordinates** (W3C Actions API):
```bash
curl -s -X POST "$WDA/session/$SID/actions" -H 'Content-Type: application/json' \
  -d '{"actions":[{"type":"pointer","id":"finger1","parameters":{"pointerType":"touch"},"actions":[{"type":"pointerMove","duration":0,"x":<X>,"y":<Y>},{"type":"pointerDown","button":0},{"type":"pause","duration":50},{"type":"pointerUp","button":0}]}]}'
```

**Other useful endpoints:**
- `GET /session/$SID/screenshot` — base64 screenshot
- `GET /session/$SID/source` — page source (accessibility tree)
- `POST /session/$SID/element` — find element by accessibility ID
- `GET /status` — check WDA is alive

**Gotchas:**
- WDA must be rebuilt after iOS app reinstall if it loses its provisioning
- `idb ui tap` only works on **simulators**, not physical devices
- WDA process must stay running in a terminal — it dies when xcodebuild exits
- Device must remain unlocked while WDA is running

### Common Gotchas

- **Info.plist**: xcframework requires Info.plist in each framework slice — SPM silently fails without them
- **Binding oscillation**: worktree builds can flip API signatures (e.g. `String` vs `String?`) — always verify with `grep` after binding copy
- **Clock drift**: Exchange protocol rejects QR codes with >120s clock drift — check device time settings
- **iOS log capture**: Use `idevicesyslog` (from libimobiledevice) for log capture — `pymobiledevice3` has Python 3.14 compatibility issues

### Recipes

| Recipe | Purpose |
|--------|---------|
| `just prepare-device-test` | Full build + install pipeline |
| `just rebuild-ios` | iOS-only rebuild + install |
| `just rebuild-android` | Android-only rebuild + install |
| `just dt-verify-builds` | Check installed versions match |
| `just dt-logs-android` | Dump Android logs |
| `just dt-logs-android-stream` | Clear + stream Android logs |
| `just dt-logs-ios` | iOS log capture instructions |
| `just dt-screenshot-android` | Screenshot from Android |
| `just dt-screenshot-ios` | Screenshot from iOS |
| `just dt-wda-start` | Start WDA on connected iPhone |
| `just dt-ios-tap X Y` | Tap iOS screen at coordinates via WDA |
| `just dt-wda-screenshot` | Screenshot via WDA (alternative to pymobiledevice3) |
