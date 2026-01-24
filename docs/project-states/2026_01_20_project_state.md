# Project State: 2026-01-20

**Verdict: NOT PRODUCTION READY (C+)**

Advanced prototype at 50-70% completion. Core crypto solid; mobile apps are scaffolding.

---

## What Works

| Component | Grade | Reality |
|-----------|-------|---------|
| Crypto (ring-based) | A- | X3DH, Double Ratchet, forward secrecy - proper |
| Core Protocol | A | Exchange, sync, recovery logic complete |
| Desktop (Tauri) | B- | ~90% features, usable |
| CLI/TUI | B | Functional dev tools |
| Relay | C+ | Works, untested at scale, no persistence |
| iOS | C- | Screens exist, recovery non-functional |
| Android | C | Better than iOS, recovery not wired |

---

## Critical Failures

### 1. Ultrasonic Audio: IMPLEMENTED ✅
`vauchi-core/src/exchange/audio.rs` - **Real CPAL implementation**

All platforms now have real ultrasonic proximity verification:
- **CLI**: `--proximity` flag for emit/listen
- **Desktop**: Tauri commands with CPAL backend
- **TUI**: 'p' keybind for ultrasonic emission  
- **Mobile**: Full UI integration with AudioProximityService

**Impact**: Security model restored. Proximity verification uses 18-20 kHz FSK signals.

### 2. iOS Recovery: BROKEN
`ios/Vauchi/Views/RecoveryView.swift` - UI exists, calls nothing

Users cannot recover identity on iOS. Blocks P6.

### 3. Android Recovery: STUBBED
`android/.../RecoveryScreen.kt` - Shows instructions, doesn't call bindings

`MainActivity.kt:onGenerateLink = { null } // TODO`

### 4. Mobile Tests: NON-EXISTENT
- iOS: 2 test files for 25+ Swift files (<4% coverage)
- Android: 1 test file for 20+ Kotlin files (<3% coverage)

FFI integration is untested. Silent failures guaranteed.

### 5. 270+ `.unwrap()` in Production
Panic-prone code throughout. Example:
```rust
let new_card = wb.own_card()?.unwrap(); // Crashes if None
```

---

## Tech Stack

| Layer | Tech | State |
|-------|------|-------|
| Crypto | ring (audited) | Solid |
| Core | Rust | 16k LOC, 86% test coverage |
| Mobile FFI | UniFFI | Works, untested integration |
| iOS | SwiftUI | Scaffolding |
| Android | Jetpack Compose | Scaffolding |
| Desktop | Tauri + SolidJS | Mostly complete |
| Relay | tokio + tungstenite | Functional, fragile |
| CI | GitLab CI | Working |

---

## Architecture

**Good**:
- Clean monorepo separation (core → mobile → apps)
- Relay can't decrypt (stateless forwarder)
- Proper error types in core

**Bad**:
- Audio/BLE/NFC are trait-only (zero implementations)
- No persistence layer for relay (memory-only)
- Mobile apps are thin wrappers with no tests

**Ugly**:
- "Proximity verification" is a lie
- Device management stubbed on all mobile platforms
- Cross-platform E2E testing: unchecked in P7

---

## Maintainability

| Aspect | Score | Notes |
|--------|-------|-------|
| Code organization | 8/10 | Clear crate boundaries |
| Test coverage (core) | 9/10 | TDD enforced, 90%+ |
| Test coverage (mobile) | 2/10 | Nearly zero |
| Documentation | 7/10 | Good planning docs, sparse code docs |
| Error handling | 6/10 | Good in core, panic-prone elsewhere |
| Technical debt | Medium | Mostly unwraps and stubs |

---

## Roadmap Reality

| Phase | Status | Blocker |
|-------|--------|---------|
| P1-P5 (Core) | Done | - |
| P6 (Recovery Mobile) | **STUCK** | iOS/Android UI not wired |
| P7 (Pre-production) | Blocked | P6, E2E tests |
| P8 (Governance) | Not started | - |
| P9 (Platform reqs) | Not started | - |

**Honest timeline to MVP**: 6-8 weeks minimum

---

## Actionable Fixes

### This Week (P0)

1. **Wire iOS Recovery** - 2 days
   - `RecoveryView.swift`: Call `VauchiRepository.createRecoveryClaim()`
   - Add progress indicators, error handling
   - Test manually

2. **Wire Android Recovery** - 2 days
   - `RecoveryScreen.kt`: Wire `viewModel.createRecoveryClaim()`
   - Implement `onGenerateLink` in `MainActivity.kt`
   - Test manually

3. **Replace `.unwrap()` with proper errors** - 1 day
   - Grep for `unwrap()` in `src/` (not tests)
   - Replace with `ok_or(Error::...)?` or `context()?`
   - Priority: crypto paths

### Next 2 Weeks (P1)

4. **Decide on proximity verification**
   - Option A: Implement real audio (iOS AVAudioEngine, Android AudioRecord) - 2 weeks
   - Option B: Remove feature, document "manual confirmation only" - 1 day
   - **Don't ship with fake feature**

5. **Add mobile integration tests** - 3 days
   - iOS: Test FFI calls work, recovery flow end-to-end
   - Android: Same
   - Goal: 20% coverage minimum

6. **Run cross-platform E2E tests** - 2 days
   - iOS ↔ Android exchange
   - Mobile ↔ Desktop sync
   - Document failures

### Before Launch (P2)

7. **Relay hardening**
   - Add SQLite persistence as default
   - Add per-identity rate limiting
   - Add blob expiration (7 days?)
   - Load test to 1000 concurrent connections

8. **Device management**
   - Complete mobile UI for device linking
   - Or remove from feature list

9. **Security review**
   - External audit of crypto paths
   - Review all `expect()` in crypto code

---

## Ship Criteria

**Minimum Viable**:
- [ ] P6 complete (recovery works on iOS + Android)
- [ ] Proximity verification resolved (real or removed)
- [ ] Cross-platform E2E green
- [ ] No panics in happy path

**Responsible Launch**:
- [ ] All above
- [ ] 20%+ mobile test coverage
- [ ] Relay persistence enabled
- [ ] External crypto audit

**Current State**: 0/4 minimum criteria met

---

## Summary

The core is solid. The mobile apps are demos pretending to be products. Ship the CLI/Desktop to developers. Don't ship mobile until P6 is actually done and proximity verification is either real or honestly documented as manual-only.

**Estimated state**: 4-6 weeks from responsible MVP.
