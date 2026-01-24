# P12: Accessibility Implementation

**Priority**: HIGH
**Status**: In Progress (Phase 1-5 Complete All Platforms)
**Effort**: 2-3 weeks
**Feature File**: `features/accessibility.feature` (42 scenarios)

## Goal

Implement comprehensive accessibility support across all platforms to ensure Vauchi is usable by people with disabilities.

## Current State

| Platform | Screen Reader | Keyboard | Visual | Motor | Settings |
|----------|---------------|----------|--------|-------|----------|
| iOS | **Done** (VoiceOver labels/hints) | N/A | Basic | Basic | **Done** |
| Android | **Done** (TalkBack semantics) | N/A | Basic | Basic | **Done** |
| Desktop | **Done** (ARIA landmarks/labels) | **Done** (tabIndex/onKeyPress) | **Done** | **Done** | **Done** |
| TUI | Inherent (text) | Full | N/A | Full | N/A |

## Implementation Phases

### Phase 1: iOS VoiceOver (5 days) ✓ COMPLETE

**Files modified:**
- `ios/Vauchi/Views/SetupView.swift` - Welcome title, name field, create button
- `ios/Vauchi/Views/HomeView.swift` - Card fields, sync status, add/edit/delete buttons
- `ios/Vauchi/Views/ExchangeView.swift` - QR code description, scan button
- `ios/Vauchi/Views/ContactsView.swift` - Contact rows, empty state, verification badge
- `ios/VauchiTests/AccessibilityTests.swift` - 14 test scenarios with AccessibilityIdentifiers

**Tasks:**
- [x] Add `.accessibilityLabel()` to all interactive elements
- [x] Add `.accessibilityHint()` for non-obvious actions
- [x] Add `.accessibilityIdentifier()` for UI testing
- [x] Implement logical focus order (isHeader traits)
- [ ] Test with VoiceOver on real device
- [ ] Run Accessibility Inspector, fix issues

**Acceptance Criteria:**
- [ ] All 8 iOS-specific scenarios pass
- [x] VoiceOver user can complete: create identity, exchange, view contacts
- [ ] No critical issues in Accessibility Inspector

### Phase 2: Android TalkBack (5 days) ✓ COMPLETE

**Files modified:**
- `android/app/src/main/kotlin/com/vauchi/ui/ExchangeScreen.kt` - QR code semantics, scan button
- `android/app/src/main/kotlin/com/vauchi/ui/ContactsScreen.kt` - Empty state, contact cards

**Tasks:**
- [x] Add `contentDescription` to all icons and images
- [x] Implement `semantics { }` blocks for complex components
- [x] Add `semantics { heading() }` for section titles
- [ ] Add `liveRegion` for dynamic updates
- [ ] Set `mergeDescendants` appropriately
- [ ] Test with TalkBack on real device
- [ ] Run Accessibility Scanner, fix issues

**Acceptance Criteria:**
- [ ] All 8 Android-specific scenarios pass
- [x] TalkBack user can complete: create identity, exchange, view contacts
- [ ] No critical issues in Accessibility Scanner

### Phase 3: Desktop ARIA (3 days) ✓ COMPLETE

**Files modified:**
- `desktop/ui/src/pages/Setup.tsx` - Main landmark, form accessibility, error alerts
- `desktop/ui/src/pages/Home.tsx` - List roles, field visibility dialog, edit dialog
- `desktop/ui/src/pages/Exchange.tsx` - QR section, timer, navigation accessibility
- `desktop/ui/src/pages/Contacts.tsx` - Contact list, detail dialog, verification section
- `desktop/ui/src/pages/Settings.tsx` - Settings sections, backup/import dialogs
- `desktop/ui/src/pages/Devices.tsx` - Device list, link/join/revoke dialogs
- `desktop/ui/src/pages/Recovery.tsx` - Recovery menu, claim/vouch forms

**Tasks:**
- [x] Add ARIA landmarks (main, nav, banner, region)
- [x] Add `aria-label` to all interactive elements
- [x] Add `aria-describedby` for complex widgets
- [x] Implement focus management for dialogs/modals (aria-modal, role="dialog")
- [x] Add keyboard navigation (tabIndex, onKeyPress for Enter)
- [ ] Test with screen reader (NVDA/Narrator on Windows, VoiceOver on Mac)

**Acceptance Criteria:**
- [ ] All desktop-specific scenarios pass
- [ ] WCAG 2.1 AA compliance (Lighthouse score > 90)
- [x] Full keyboard navigation works

### Phase 4: Visual & Motor Accessibility (2 days)

**Desktop tasks (COMPLETE):**
- [x] Verify 4.5:1 contrast ratio for all text (improved #888 -> #a0a0a0)
- [x] Respect system high contrast mode (prefers-contrast media query)
- [x] Ensure touch targets are 44px minimum
- [x] Respect reduced motion preference (prefers-reduced-motion media query)
- [x] Add visible focus indicators (:focus-visible)

**Mobile tasks (remaining):**
- [ ] Ensure touch targets are 44x44pt (iOS) / 48x48dp (Android)
- [ ] Add alternatives for all gestures
- [ ] Test with Switch Control (iOS) and Switch Access (Android)

**Acceptance Criteria:**
- [ ] All @visual and @motor scenarios pass
- [ ] No color-only information

### Phase 5: In-App Accessibility Settings (1 day) ✓ COMPLETE

**Desktop implementation:**
- `desktop/ui/src/pages/Settings.tsx` - Accessibility section with 3 toggles
- `desktop/ui/src/App.tsx` - Apply settings on startup
- `desktop/ui/src/styles/app.css` - Toggle styles, data attribute selectors

**iOS implementation:**
- `ios/Vauchi/Services/SettingsService.swift` - Accessibility settings with UserDefaults
- `ios/Vauchi/Views/SettingsView.swift` - Accessibility section with 3 toggles

**Android implementation:**
- `android/app/src/main/kotlin/com/vauchi/data/VauchiRepository.kt` - SharedPreferences storage
- `android/app/src/main/kotlin/com/vauchi/ui/MainViewModel.kt` - State and handlers
- `android/app/src/main/kotlin/com/vauchi/ui/SettingsScreen.kt` - Accessibility section with 3 toggles

**Tasks:**
- [x] Add Settings > Accessibility section (Desktop)
- [x] Add Settings > Accessibility section (iOS)
- [x] Add Settings > Accessibility section (Android)
- [x] Implement: Reduce animations toggle (all platforms)
- [x] Implement: Increase touch target size toggle (all platforms)
- [x] Implement: High contrast mode toggle (all platforms)
- [x] Persist preferences across sessions (localStorage/UserDefaults/SharedPreferences)

**Acceptance Criteria:**
- [ ] All @settings scenarios pass

## Testing Strategy

### Automated Testing
```bash
# iOS
xcrun simctl launch booted app.vauchi --accessibility-testing

# Android
./gradlew connectedCheck -Pandroid.testInstrumentationRunnerArguments.accessibility=true

# Desktop
npx lighthouse http://localhost:1420 --only-categories=accessibility
```

### Manual Testing
- Real device testing with actual screen reader users (if possible)
- Internal testing with VoiceOver/TalkBack enabled
- Keyboard-only navigation test

## Metrics

| Metric | Target |
|--------|--------|
| iOS Accessibility Inspector | 0 critical issues |
| Android Accessibility Scanner | 0 critical issues |
| Desktop Lighthouse a11y score | > 90 |
| Scenarios passing | 42/42 |

## Dependencies

- None - can proceed independently

## Risks

| Risk | Mitigation |
|------|------------|
| Screen reader behavior varies | Test on multiple screen readers |
| Layout breaks with large text | Use flexible layouts, test at 200% |
| Performance with a11y enabled | Profile, optimize critical paths |

## References

- [Apple VoiceOver Guide](https://developer.apple.com/accessibility/ios/)
- [Android Accessibility](https://developer.android.com/guide/topics/ui/accessibility)
- [WCAG 2.1](https://www.w3.org/WAI/WCAG21/quickref/)
- [Kobalte](https://kobalte.dev/)
