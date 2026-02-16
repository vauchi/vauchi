<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Roadmap - February 2026

**Goal**: Full-feature production release — all 18 features implemented with real code, no stubs or mocks
**Last audit**: 2026-02-06 (code-verified)

---

## Approach

All 18 features must be production-ready with real implementations before real device testing begins. No feature is deferred or deprioritised.

- **No stubs**: Every feature uses real hardware APIs, real crypto, real platform integrations
- **No mocks in production paths**: Mocks exist only in test code
- **E2E validation**: Simulators, emulators, and dev systems validate each phase before real devices
- **Relay**: Deployed independently on VPS, available throughout development

---

## What's Done (Verified)

| Component | Status | Evidence |
|-----------|--------|----------|
| Core crypto (ring) | Done | 13 ring imports, Double Ratchet, X3DH |
| E2E encryption | Done | AES-256-GCM, forward secrecy |
| Contact exchange (QR) | Done | QR exchange working, audio proximity |
| Recovery system | Done | 28k lines in recovery/mod.rs |
| Visibility labels | Done | labels.rs implemented, storage, API |
| Relay deployed | Done | https://relay.vauchi.app returns 200 |
| Relay persistence | Done | SQLite default backend, TTL, cleanup |
| Relay rate limiting | Done | Token bucket, per-client, configurable |
| Contact exchange (Mutual QR) | Done | Symmetric DH, fresh ephemeral keys, 13 tests |
| Contact exchange (NFC Active) | Done | 174-byte APDU payload, VNFC magic, 25 tests |
| Contact exchange (BLE) | Done | GATT transport trait, VBLE magic, 27 tests |
| Rust tests | Done | ~2,119 tests across 166+ files |
| iOS test files | Done | 17 files — KeychainService, Audio, Exchange, Accessibility, VRT, etc. |
| Android test files | Done | 13 files — SyncWorker, Audio, Exchange, Accessibility, Screenshots, etc. |
| No unsafe code | Done | 0 unsafe blocks in vauchi-core |
| No unwraps in crypto | Done | 0 production unwraps |
| Accessibility (Phase 1-5) | Done | VoiceOver, TalkBack, ARIA complete |
| Phase 2 Security Hardening | Done | Desktop key storage fixed, cert pinning implemented, scans clean |
| Security scan | Done | cargo-audit: 0 vulns (2026-02-02, all repos) |

---

## What's Required (18 Features)

All features below must be complete — with real implementations — before real device testing.

### Phase 1: Security Foundation ✓

| Feature | Status | Notes |
|---------|--------|-------|
| Phase 2 Security Hardening | Done | Scans clean, key storage fixed, cert pinning (275 lines), desktop keychain (707 lines) |
| Android KeyStore Auth | Done | Biometric-gated key access, 300s timeout, 166 lines |
| Crypto-Shredding | Done | SMK hierarchy (192 lines), CEK (66 lines), ShredManager (937 lines, 3-phase protocol) |
| GDPR Compliance | Done | DPIA v1.2, data export, deletion, consent — all platforms wired |
| Protocol Hardening Gap 1 | Done | Noise NK inner transport encryption (361 lines core + relay) |

### Phase 2: Core Exchange ✓

| Feature | Status | Notes |
|---------|--------|-------|
| Mutual Offline QR Exchange | Done | Symmetric DH, fresh ephemeral keys, 13 tests |
| BLE Exchange | Done | `BLETransport` trait, GATT service, `ExchangeBle` payload, 27 tests |
| NFC Active Exchange | Done | `ExchangeNfc` payload, APDU protocol, 25 tests |

### Phase 3: Platform Completeness

Core Rust modules done and tested for all 6 features. Remaining work is platform UI wiring.

| Feature | Status | Notes |
|---------|--------|-------|
| Internationalization | Done | `src/i18n.rs` — 534 lines, 18 tests, 4 locales, 754 keys, runtime loading. All platforms wired |
| In-app Help Updates | Core done | `src/help.rs` — 390 lines, 15 tests, 14 FAQs. iOS + Android + Desktop UI done. CLI/TUI partial |
| Remote Theming Updates | Core done | `src/theme.rs` — 545 lines, 7 unit tests, 12 themes. iOS + Android + Desktop UI done |
| Aha Moments | Core done | Localized, CLI + TUI + iOS + Android done. Desktop partial |
| Performance & Scalability | Core done | Pagination + batch sync, 24 tests. Real device profiling remaining |
| Platform Edge Cases | Core done | Crash recovery (11 tests) + clock skew (23 tests) = 34 tests. Platform service hardening remaining |

### Phase 4: Privacy & Hardening

| Feature | Status | Notes |
|---------|--------|-------|
| Tor Mode | Done | 594 lines, feature-gated `tor = []`, arti-ready |
| Relay Federation | Done | All 4 phases: static federation, gossip discovery, mutual TLS (1,526 lines) |
| Protocol Hardening | Partial | Noise NK + fixed-size padding done. **AEAD identity binding not found in code** |
| Cargo Fuzz Targets | Done | 10 targets covering all attack surfaces |
| Testing Infrastructure Gaps | Done | cargo-deny CI (all repos), MASVS L1 self-assessment |
| Recovery Trust Contacts | Done | All platforms complete |
| CLI API Drift | Done | All 17 compilation errors resolved |
| Relay Authentication | Done | Ed25519 handshake verification in relay. Client hex format in core |
| X3DH Protocol Hardening | Done | Migration v18: visibility_rules encrypted, PBKDF2 600K |
| Trust Metrics & Indicators | Planning | Migration v19. Depends on X3DH v18 |
| Accessibility Audit | Planning | Formal audit with real screen readers |
| Birthday Field | Planning | No migration needed |
| Local Contact Annotations | Planning | Migration v20. Depends on Trust Metrics v19 |
| Contact Network Statistics | Planning | Pure computation, no migration |

### Security Gaps (Found in 2026-02-06 Code Audit)

| Gap | Severity | Status | Notes |
|-----|----------|--------|-------|
| Device Linking Proximity | **CRITICAL** | Intake | Core proximity gate exists but clients bypass it. Remote QR attack possible without client integration |
| Account Deletion Relay Purge | **HIGH** | Investigating | Revocations generated but not auto-sent via relay |
| Proximity Verification Integration | **MEDIUM** | Investigating | 510 lines of audio code on iOS+Android but NOT integrated into exchange flows |
| Fingerprint Verification UI | **MEDIUM** | Intake | Core API exists, UI scaffolding but doesn't show actual key fingerprints |
| Field Validation Core-Mobile | None | Done | Core + UniFFI + iOS + Android all wired — no gap |

### Phase 5: Validation

| Milestone | Status | Description |
|-----------|--------|-------------|
| Visual Regression Testing | Testing | ~95 baselines across 4 platforms (23 iOS, 14 Android, 34 Desktop, 24 TUI). CI stabilization remaining |
| E2E on simulators/emulators | Pending | Full test suite on iOS Simulator, Android Emulator, desktop dev builds |
| Relay on VPS | Done | Production relay deployment verified |
| Full regression green | Pending | All features passing, no regressions |

### Phase 6: Real Device Testing

| Milestone | Description |
|-----------|-------------|
| Physical iOS + Android | Real hardware testing on iPhones and Android phones |
| Cross-platform exchange | iOS <-> Android exchange verified (QR, BLE, NFC) |
| Production release prep | App store submissions, release tagging, monitoring |

### Phase 7: Post-Launch Features

| Feature | Status | Notes |
|---------|--------|-------|
| NFC Dead Drop Exchange | Planning | Passive NFC tag as physical dead drop |
| Facilitated Introductions | Investigating | Principle-compliant mutual introduction. Depends on Trust Metrics |
| Resistance Features | Implementing | Duress PIN, hidden contacts, emergency broadcast implemented. Panic widget + mesh exchange spec-only |

---

## Ship Criteria

| Requirement | Status | Verification |
|-------------|--------|--------------|
| E2E encryption works | Done | Rust tests |
| All exchange methods real | Pending | QR + BLE + NFC on real hardware |
| Card updates sync | Pending | Cross-platform E2E test |
| Recovery works | Pending | Cross-platform E2E test |
| No plaintext secrets | Done | All fields encrypted (migration v18) |
| Rate limiting active | Done | Relay config |
| Persistence working | Done | SQLite default |
| No critical vulnerabilities | Done | cargo-audit: 0 vulns (2026-02-02) |
| Tor mode functional | Done | Types, storage, transport, API, CLI, TUI implemented |
| GDPR compliance | Done | Data export, deletion (7-day grace), consent — all platforms wired |
| i18n on all platforms | Done | 754 keys, runtime loading, all platforms wired |
| Accessibility audited | Pending | Screen reader validation |
| Fuzz targets covering attack surfaces | Done | 10 targets |
| All platform edge cases handled | Core done | Platform hardening remaining |
| Device linking proximity-verified | **Not done** | CRITICAL: core gate exists but clients bypass; no proximity check in practice |
| Account deletion notifies contacts | **Not done** | Revocations not auto-sent via relay |
| Relay client authentication | Done | Ed25519 handshake verification in relay |
| Proximity verification in exchange | **Not done** | Audio code exists but not integrated |
| Key fingerprint verification UI | **Not done** | UI doesn't display actual fingerprints |
| TDD followed for all features | Ongoing | Red→Green→Refactor, no exceptions |
| 90%+ test coverage (vauchi-core) | Ongoing | Real crypto in tests, no mocking |

---

## Commands

```bash
# Verify current state
just verify-roadmap

# Run all tests
just test

# Build iOS
cd ios && ./build-ios.sh

# Build Android
cd android && ./gradlew assembleRelease

# Security scan (install first: cargo install cargo-audit)
cargo audit

# Check relay health
curl https://relay.vauchi.app/health
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Device linking remote attack | **High** | **Critical** | No proximity verification before seed transfer. Fix before real device testing |
| Account deletion silent failure | Medium | High | Contacts not notified on deletion. Wire relay revocation sending |
| BLE/NFC platform differences | High | Medium | Test on both iOS and Android early |
| Tor integration complexity | Medium | Medium | Prototype with arti crate first |
| Real device issues | Medium | High | Validate on simulators/emulators first, then physical devices |
| App store rejection | Low | Medium | Follow guidelines, test on TestFlight first |
| Relay overload | Low | Medium | Rate limiting in place |
| Security vulnerability | Low | High | Run cargo-audit, fuzz targets, code review |

---

## Verification

**Last verification**: 2026-02-06 (code-verified audit)
