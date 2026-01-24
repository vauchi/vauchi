# Manual Testing Guide

This guide covers how to manually test Vauchi apps locally, simulating multiple devices for testing contact exchange, sync, and other inter-device features.

## Prerequisites

- Rust toolchain installed (`rustup`)
- Xcode (for iOS simulator)
- Android Studio with SDK (for Android emulator)
- Node.js (for Desktop UI development)

## Quick Start

```bash
# Terminal 1: Start local relay server
./scripts/dev/local-relay.sh

# Terminal 2: Start first CLI instance as "Alice"
./scripts/dev/multi-cli.sh alice init "Alice Smith"

# Terminal 3: Start second CLI instance as "Bob"
./scripts/dev/multi-cli.sh bob init "Bob Jones"
```

---

## Dev Scripts Overview

All scripts are in `dev-tools/scripts/dev/`:

| Script | Purpose |
|--------|---------|
| `local-relay.sh` | Start local WebSocket relay server |
| `multi-cli.sh` | Run CLI with isolated data directory |
| `multi-tui.sh` | Run TUI with isolated data directory |
| `multi-desktop.sh` | Run Desktop with isolated data directory |
| `android-emulators.sh` | Manage Android emulators for testing |
| `ios-simulators.sh` | Manage iOS simulators, build/install/launch app |

---

## 1. Local Relay Server

The relay server handles sync between devices. Start it first.

```bash
cd code
./scripts/dev/local-relay.sh
```

Default: `ws://127.0.0.1:8080`

To use a custom port:
```bash
RELAY_PORT=9090 ./scripts/dev/local-relay.sh
```

---

## 2. CLI Testing (Multiple Instances)

Each CLI instance uses isolated storage, acting as a separate device.

### Setup Two Users

```bash
# Terminal 1 - Alice
./scripts/dev/multi-cli.sh alice init "Alice Smith"
./scripts/dev/multi-cli.sh alice card add-field email alice@example.com

# Terminal 2 - Bob
./scripts/dev/multi-cli.sh bob init "Bob Jones"
./scripts/dev/multi-cli.sh bob card add-field email bob@example.com
```

### Test Contact Exchange

```bash
# Alice generates exchange data
./scripts/dev/multi-cli.sh alice exchange start
# Output: Exchange data (base64 encoded QR content)

# Bob completes the exchange with Alice's data
./scripts/dev/multi-cli.sh bob exchange complete <alice-exchange-data>
# Output: Bob's exchange data to send back

# Alice completes with Bob's data
./scripts/dev/multi-cli.sh alice exchange complete <bob-exchange-data>

# Verify contacts
./scripts/dev/multi-cli.sh alice contacts list
./scripts/dev/multi-cli.sh bob contacts list
```

### Test Sync

```bash
# Alice updates her card
./scripts/dev/multi-cli.sh alice card add-field phone "+1-555-0100"

# Alice syncs (pushes update to relay)
./scripts/dev/multi-cli.sh alice sync

# Bob syncs (pulls Alice's update)
./scripts/dev/multi-cli.sh bob sync

# Bob sees Alice's new phone number
./scripts/dev/multi-cli.sh bob contacts show alice
```

### Test Visibility Labels

```bash
# Alice creates a label
./scripts/dev/multi-cli.sh alice labels create "Close Friends"

# Alice adds Bob to the label
./scripts/dev/multi-cli.sh alice labels add-contact <label-id> <bob-contact-id>

# Alice makes email visible to Close Friends
./scripts/dev/multi-cli.sh alice labels show-field <label-id> email

# Alice hides phone from Close Friends
./scripts/dev/multi-cli.sh alice labels hide-field <label-id> phone
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VAUCHI_RELAY_URL` | `ws://127.0.0.1:8080` | Relay server URL |
| `VAUCHI_TEST_DATA` | `/tmp/vauchi-test` | Base directory for test data |

---

## 3. TUI Testing (Multiple Instances)

Run each TUI instance in a separate terminal window.

```bash
# Terminal 1 - Start relay
./scripts/dev/local-relay.sh

# Terminal 2 - Alice's TUI
./scripts/dev/multi-tui.sh alice

# Terminal 3 - Bob's TUI
./scripts/dev/multi-tui.sh bob
```

### TUI Navigation

- Use arrow keys or `j`/`k` to navigate
- `Enter` to select
- `Esc` to go back
- `q` to quit

### Testing Exchange in TUI

1. In Alice's TUI: Go to "Exchange" → "Start Exchange"
2. Copy the displayed QR data
3. In Bob's TUI: Go to "Exchange" → "Complete Exchange" → Paste Alice's data
4. Copy Bob's response data
5. Back in Alice's TUI: Complete with Bob's data

---

## 4. Desktop Testing (Tauri)

Desktop apps have single-instance restrictions on macOS. Options:

### Option A: Dev Mode + Built App

```bash
# Terminal 1 - Run in dev mode as Alice
./scripts/dev/multi-desktop.sh alice

# Terminal 2 - Build and run as Bob (different binary)
cd code/vauchi-desktop
cargo tauri build
# Run the built .app with different data dir
VAUCHI_DATA_DIR=/tmp/vauchi-test/bob open target/release/bundle/macos/Vauchi.app
```

### Option B: Desktop + CLI/TUI Combo

```bash
# Terminal 1 - Desktop as Alice
./scripts/dev/multi-desktop.sh alice

# Terminal 2 - CLI as Bob
./scripts/dev/multi-cli.sh bob init "Bob"
```

### Option C: Different User Accounts

Run Desktop on different macOS user accounts for true isolation.

---

## 5. Android Emulator Testing

### Initial Setup

```bash
# Create test AVDs (Alice and Bob)
./scripts/dev/android-emulators.sh setup
```

### Start Emulators

```bash
# Start both emulators
./scripts/dev/android-emulators.sh start-all

# Or start individually
./scripts/dev/android-emulators.sh start vauchi_alice
./scripts/dev/android-emulators.sh start vauchi_bob
```

### Deploy App

In Android Studio:
1. Run → Select Deployment Target
2. Hold `Ctrl` and click both emulators
3. Click OK to deploy to both

Or via command line:
```bash
./scripts/dev/android-emulators.sh install vauchi_alice
```

### Testing Exchange

1. On Alice's emulator: Go to Exchange → Generate QR
2. On Bob's emulator: Go to Exchange → Scan QR
3. Point Bob's camera at Alice's screen
4. Complete the mutual exchange

### List Available AVDs

```bash
./scripts/dev/android-emulators.sh list
```

---

## 6. iOS Simulator Testing

### Quick Start (Single Simulator)

```bash
# Start one simulator, build, install, and launch Vauchi
./scripts/dev/ios-simulators.sh start-one
```

This is the simplest way to test on iOS simulator. It:
1. Boots one iPhone simulator
2. Opens the Simulator app
3. Builds the iOS app
4. Installs it on the simulator
5. Launches the app

### Start Simulator Pair (Multi-Device Testing)

```bash
# Start two iPhone simulators
./scripts/dev/ios-simulators.sh start-pair
```

### Deploy App

**Option A: Using the script**
```bash
# Build and install on booted simulator
./scripts/dev/ios-simulators.sh install

# Launch the app
./scripts/dev/ios-simulators.sh launch
```

**Option B: Using Xcode**
1. Product → Destination → Select first simulator
2. Build and Run (Cmd+R)
3. Change destination to second simulator
4. Build and Run again (Cmd+R)

### Testing Exchange

1. On first simulator: Navigate to Exchange, generate QR
2. On second simulator: Navigate to Exchange, scan QR
3. Use the simulated camera or paste QR data

### Simulator Commands

```bash
# List available simulators
./scripts/dev/ios-simulators.sh list

# List running simulators
./scripts/dev/ios-simulators.sh booted

# Start one simulator with app installed
./scripts/dev/ios-simulators.sh start-one

# Start two simulators for multi-device testing
./scripts/dev/ios-simulators.sh start-pair

# Stop all simulators
./scripts/dev/ios-simulators.sh stop-all

# Build and install app (uses booted simulator if no UDID given)
./scripts/dev/ios-simulators.sh install [udid]

# Launch the app on simulator
./scripts/dev/ios-simulators.sh launch [udid]
```

---

## 7. Cross-Platform Testing

Test exchange between different platforms:

### Scenario: Android ↔ iOS

1. Start Android emulator: `./scripts/dev/android-emulators.sh start vauchi_alice`
2. Start iOS simulator: `./scripts/dev/ios-simulators.sh start-pair`
3. Deploy app to both
4. Perform exchange between them

### Scenario: Desktop ↔ Mobile

1. Start Desktop: `./scripts/dev/multi-desktop.sh alice`
2. Start Android: `./scripts/dev/android-emulators.sh start vauchi_bob`
3. Generate QR on Desktop
4. Scan with Android camera

### Scenario: CLI ↔ TUI ↔ Desktop

```bash
# Terminal 1: Relay
./scripts/dev/local-relay.sh

# Terminal 2: CLI as Alice
./scripts/dev/multi-cli.sh alice init "Alice"

# Terminal 3: TUI as Bob
./scripts/dev/multi-tui.sh bob

# Terminal 4: Desktop as Carol
./scripts/dev/multi-desktop.sh carol
```

---

## 8. Simulating Proximity (QR Exchange)

Vauchi uses QR codes for in-person contact exchange. For testing:

### CLI/TUI: Copy-Paste

Exchange data is text-based - copy from one terminal, paste to another.

### Desktop: Screenshot + Scan

1. Generate QR in one Desktop instance
2. Take screenshot
3. Use QR scanner app or decode manually

### Mobile Emulators: Virtual Camera

Android emulators support virtual camera input:

1. In emulator, go to Extended Controls (⋯)
2. Select "Camera"
3. Choose "Virtual Scene"
4. Point at QR code on your screen

iOS simulators have limited camera support. Alternatives:
- Use pasteboard to share QR data between simulators
- Test one simulator with Desktop/CLI for exchange

### Physical Device Testing

For true proximity testing:
1. Build debug app on physical devices
2. Connect to same local relay (use your machine's local IP)
3. Perform real QR scan between devices

```bash
# Start relay accessible on local network
RELAY_HOST=0.0.0.0 ./scripts/dev/local-relay.sh

# On devices, connect to ws://<your-machine-ip>:8080
```

---

## 9. Feature Testing Checklist

### Identity Management
- [ ] Create new identity
- [ ] View identity details
- [ ] Export identity backup
- [ ] Import identity backup on new device

### Contact Card
- [ ] Add field (email, phone, etc.)
- [ ] Update field value
- [ ] Remove field
- [ ] View own card

### Contact Exchange
- [ ] Generate exchange QR/data
- [ ] Complete exchange with peer
- [ ] Verify contact appears in list
- [ ] View exchanged contact details

### Sync
- [ ] Connect to relay
- [ ] Push card updates
- [ ] Receive updates from contacts
- [ ] Offline changes sync when online

### Device Linking
- [ ] Generate device link QR on primary
- [ ] Join from secondary device
- [ ] Verify identity synced
- [ ] Both devices show in device list

### Recovery
- [ ] Create recovery voucher (as contact)
- [ ] Generate recovery claim (losing device)
- [ ] Complete recovery with vouchers
- [ ] Verify identity restored

### Visibility Labels
- [ ] Create label
- [ ] Add contacts to label
- [ ] Set field visibility per label
- [ ] Override visibility for specific contact
- [ ] Verify contacts see correct fields

---

## 10. Troubleshooting

### Relay Connection Failed

```
Error: Connection refused
```

Ensure relay is running:
```bash
./scripts/dev/local-relay.sh
```

### Data Directory Issues

Clear test data to start fresh:
```bash
rm -rf /tmp/vauchi-test/*
```

### Android Emulator Won't Start

Check if AVD exists:
```bash
./scripts/dev/android-emulators.sh list
```

Create if missing:
```bash
./scripts/dev/android-emulators.sh setup
```

### iOS Simulator Not Found

List available simulators:
```bash
./scripts/dev/ios-simulators.sh list
```

Create iPhone 15 simulators in Xcode:
Window → Devices and Simulators → Simulators → +

### WebSocket Connection Issues

Check relay URL environment:
```bash
echo $VAUCHI_RELAY_URL  # Should be ws://127.0.0.1:8080
```

### Build Errors

Ensure you're in the `code/` directory:
```bash
cd /path/to/vauchi-workspace/code
cargo build --workspace
```

---

## 11. Tips for Effective Testing

1. **Start Fresh**: Clear `/tmp/vauchi-test/` before testing new flows
2. **Use Descriptive Names**: `alice`, `bob`, `carol` help track which is which
3. **Keep Relay Running**: Most features need the relay for sync
4. **Watch Logs**: Relay logs show real-time message passing
5. **Test Edge Cases**: Try offline, reconnect, conflicting updates
6. **Cross-Platform**: Exchange between different app types regularly

---

## Environment Summary

| Component | Location | Data |
|-----------|----------|------|
| Local Relay | `ws://127.0.0.1:8080` | None (stateless) |
| CLI/TUI Data | `/tmp/vauchi-test/<name>/` | SQLite + keys |
| Desktop Data | `/tmp/vauchi-test/<name>/` | SQLite + keys |
| Android Data | Emulator internal storage | SQLite + keys |
| iOS Data | Simulator app container | SQLite + keys |

---

## See Also

- [TDD Rules](planning/TDD_RULES.md) - Testing philosophy
- [Protocol Spec](architecture/protocol.md) - Exchange and sync protocols
- [Feature Files](../features/) - BDD scenarios for all features
