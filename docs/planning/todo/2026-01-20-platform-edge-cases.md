# P18: Platform-Specific Edge Cases

**Priority**: MEDIUM
**Status**: Planning
**Effort**: 1 week

## Goal

Handle platform-specific edge cases that can cause data loss, poor UX, or app instability on iOS, Android, and desktop.

## Current State

Feature files have 30+ @platform scenarios but miss critical platform-specific edge cases:
- iOS background termination
- Android memory pressure
- Desktop WebView security
- Platform permission handling
- App lifecycle edge cases

## Gap Analysis

| Platform | Covered | Missing |
|----------|---------|---------|
| iOS | Basic lifecycle | Background termination, low memory, permission revocation |
| Android | Basic lifecycle | onTrimMemory, doze mode, battery saver |
| Desktop | Basic | WebView security, multi-window, file associations |
| TUI | Good | None significant |

## Feature Scenarios to Add

### Add new `features/platform_edge_cases.feature`:

```gherkin
@platform @edge-cases
Feature: Platform-Specific Edge Cases
  As a Vauchi user on any platform
  I want the app to handle platform quirks gracefully
  So that I don't lose data or have poor experience

  # ============================================================
  # iOS Edge Cases
  # ============================================================

  @ios @background
  Scenario: Sync survives background termination
    Given I am syncing updates
    When iOS terminates the app in background
    Then pending syncs should be saved to disk
    And when I relaunch the app
    Then syncs should resume automatically
    And no data should be lost

  @ios @background
  Scenario: Background task completes before termination
    Given I started a sync operation
    When the app moves to background
    Then a background task should be requested
    And the sync should complete if possible
    And state should be saved before termination

  @ios @memory
  Scenario: Handle low memory warning
    Given the app is using significant memory
    When iOS sends a memory warning
    Then the app should release cached images
    And the app should release non-essential data
    And core functionality should continue working

  @ios @permissions
  Scenario: Handle camera permission revoked
    Given I previously granted camera permission
    When I revoke camera permission in Settings
    And I try to scan a QR code
    Then I should see a clear message about permission
    And there should be a button to open Settings
    And the app should not crash

  @ios @permissions
  Scenario: Handle notification permission denied
    Given I denied notification permission
    When a contact updates their card
    Then the update should still sync
    And I should see updates when I open the app
    And I should be gently prompted to enable notifications

  @ios @keychain
  Scenario: Keychain access after device restore
    Given I restored my iPhone from backup
    When I open Vauchi
    Then keychain items should be accessible
    Or I should be prompted to restore from backup
    And I should not be locked out of my identity

  @ios @extension
  Scenario: Share extension works
    Given I am in another app with a phone number
    When I use the share sheet
    Then Vauchi should appear as an option
    And I can create a contact from shared data
    And sharing should work even if main app not running

  # ============================================================
  # Android Edge Cases
  # ============================================================

  @android @memory
  Scenario: Handle onTrimMemory
    Given the system is under memory pressure
    When Android calls onTrimMemory(LEVEL_LOW)
    Then the app should release caches
    And images should be released from memory
    And core data should be preserved

  @android @memory
  Scenario: Handle process killed for memory
    Given Android kills the app process
    When I return to the app
    Then the app should restore state
    And unsaved changes should be preserved
    And the user should see where they left off

  @android @battery
  Scenario: Handle doze mode
    Given the device enters doze mode
    When a sync is scheduled
    Then sync should use WorkManager properly
    And it should respect doze restrictions
    And critical updates should use high-priority FCM

  @android @battery
  Scenario: Handle battery saver mode
    Given battery saver is enabled
    When background sync is due
    Then sync frequency should be reduced
    And the user should be informed
    And critical functionality should work

  @android @permissions
  Scenario: Handle runtime permission denied
    Given I denied camera permission
    When I try to scan a QR code
    Then I should see an explanation
    And there should be a button to request again
    And I should not be asked repeatedly

  @android @storage
  Scenario: Handle scoped storage restrictions
    Given Android 11+ scoped storage is enforced
    When I export my data
    Then export should use proper storage APIs
    And files should go to Downloads or app-specific
    And the user should be able to share the export

  @android @split
  Scenario: Handle split APK installation
    Given the app was installed via split APKs
    When I use native features (camera, crypto)
    Then all required libraries should be present
    And the app should not crash
    And features should work correctly

  # ============================================================
  # Desktop Edge Cases
  # ============================================================

  @desktop @webview
  Scenario: WebView security
    Given the desktop app uses WebView
    Then JavaScript should not access filesystem
    And external links should open in system browser
    And WebView should have secure defaults

  @desktop @multi-window
  Scenario: Handle multiple windows
    Given the app is open in one window
    When I try to open another instance
    Then the existing window should be focused
    Or multiple windows should sync state
    And data conflicts should be prevented

  @desktop @crash
  Scenario: Recovery after crash
    Given the app crashed unexpectedly
    When I relaunch the app
    Then the app should offer crash recovery
    And recent state should be restored
    And unsaved changes should be preserved if possible

  @desktop @file-association
  Scenario: Handle vauchi:// URL scheme
    Given I click a vauchi:// link
    When the app is not running
    Then the app should launch
    And the link should be processed
    And the appropriate action should occur

  @desktop @tray
  Scenario: System tray behavior
    Given the app is minimized to tray
    When a contact update arrives
    Then a notification should show
    And clicking the tray icon should restore the app
    And the app should not consume CPU while minimized

  # ============================================================
  # Cross-Platform Edge Cases
  # ============================================================

  @cross-platform @time
  Scenario: Handle clock skew
    Given my device clock is 1 hour behind
    When I sync with contacts
    Then timestamps should use server time
    And message ordering should be correct
    And no sync loops should occur

  @cross-platform @time
  Scenario: Handle timezone change
    Given I change timezone while app is running
    When I view timestamps
    Then they should update to new timezone
    And relative times should be correct
    And no duplicate notifications should occur

  @cross-platform @upgrade
  Scenario: Handle app upgrade
    Given I have data from version 1.0
    When I upgrade to version 2.0
    Then data migration should occur automatically
    And no data should be lost
    And the user should not need to reconfigure

  @cross-platform @downgrade
  Scenario: Prevent data loss on downgrade
    Given I downgraded to an older version
    When the older version can't read new data format
    Then a clear error should be shown
    And the user should be told to upgrade
    And data should not be corrupted

  @cross-platform @network
  Scenario: Handle network type change
    Given I am syncing on WiFi
    When I switch to cellular
    Then sync should continue seamlessly
    And no duplicate requests should occur
    And the connection should not hang

  @cross-platform @interrupt
  Scenario: Handle sync interruption
    Given a sync is in progress
    When the network drops mid-sync
    Then partial sync should be saved
    And sync should resume when network returns
    And no corruption should occur
```

## Implementation Plan

### Phase 1: iOS Edge Cases (2 days)

**Tasks:**
- [ ] Implement background task handling
- [ ] Add low memory response
- [ ] Handle permission revocation gracefully
- [ ] Test keychain after restore
- [ ] Implement share extension

**Key Code Areas:**
- `AppDelegate` / `SceneDelegate`
- Background task registration
- Memory warning handlers

### Phase 2: Android Edge Cases (2 days)

**Tasks:**
- [ ] Implement onTrimMemory handling
- [ ] Use WorkManager for background sync
- [ ] Handle doze mode properly
- [ ] Implement proper permission request flow
- [ ] Use scoped storage APIs

**Key Code Areas:**
- `Application` class
- `ViewModel` save/restore
- WorkManager configuration

### Phase 3: Desktop Edge Cases (2 days)

**Tasks:**
- [ ] Secure WebView configuration
- [ ] Implement single-instance or multi-window sync
- [ ] Add crash recovery
- [ ] Implement URL scheme handler
- [ ] Add system tray support

**Key Code Areas:**
- Tauri configuration
- IPC handlers
- Window management

### Phase 4: Cross-Platform Testing (1 day)

**Tasks:**
- [ ] Test clock skew handling
- [ ] Test timezone changes
- [ ] Test upgrade migration
- [ ] Test network transitions
- [ ] Test sync interruption

## Testing Strategy

### iOS Testing
```bash
# Test background termination
# Use Xcode > Debug > Simulate Background Fetch
# Kill app from app switcher

# Test low memory
# Use Xcode > Debug > Simulate Memory Warning

# Test permission revocation
# Settings > Vauchi > Permissions
```

### Android Testing
```bash
# Test memory pressure
adb shell am send-trim-memory <package> RUNNING_LOW

# Test doze mode
adb shell dumpsys deviceidle force-idle

# Test battery saver
adb shell settings put global low_power 1
```

### Desktop Testing
```bash
# Test crash recovery
kill -9 <pid>

# Test URL scheme
xdg-open "vauchi://exchange?..."
```

## Platform-Specific Considerations

### iOS
- Background execution limited to ~30s
- Memory warnings must be handled immediately
- Keychain may not survive backup/restore without proper attributes
- Share extension runs in separate process

### Android
- Process can be killed anytime
- onSaveInstanceState must save critical state
- WorkManager for reliable background work
- Scoped storage mandatory on Android 11+

### Desktop
- WebView security varies by platform
- File access permissions differ (macOS sandbox)
- URL scheme registration platform-specific
- Tray icon behavior varies (Windows/macOS/Linux)

## Metrics

| Metric | Target |
|--------|--------|
| Crash-free sessions | > 99.5% |
| Background sync success | > 95% |
| Data loss incidents | 0 |
| Permission request flow completion | > 80% |

## Dependencies

- Platform-specific testing devices
- CI with iOS and Android emulators
