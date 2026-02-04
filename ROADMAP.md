<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Roadmap - February 2026

**Goal**: Full-feature production release — all 18 features implemented with real code, no stubs or mocks
**Last audit**: 2026-02-04

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
| Contact exchange (Mutual QR) | Done | Symmetric DH, fresh ephemeral keys, 14 tests |
| Contact exchange (NFC Active) | Done | 174-byte APDU payload, VNFC magic, 25 tests |
| Contact exchange (BLE) | Done | GATT transport trait, VBLE magic, 27 tests |
| Rust tests | Done | 1032 pass, all green |
| iOS test files | Done | 10 files — KeychainService, Audio, Exchange, etc. |
| Android test files | Done | 10 files — SyncWorker, Audio, Exchange, etc. |
| No unsafe code | Done | 0 unsafe blocks in vauchi-core |
| No unwraps in crypto | Done | 0 production unwraps |
| Accessibility (Phase 1-5) | Done | VoiceOver, TalkBack, ARIA complete |
| Phase 2 Security Hardening | Partial | Desktop key storage fixed, cert pinning implemented |
| Security scan | Done | cargo-audit: 0 vulns (2026-02-02, all repos) |

---

## What's Required (18 Features)

All features below must be complete — with real implementations — before real device testing.

### Phase 1: Security Foundation

Finish the security layer that protects everything else.

| Feature | Status | Problem Record |
|---------|--------|----------------|
| Phase 2 Security Hardening | In progress | `2026-02-02-phase2-security-hardening` |
| Android KeyStore Auth | Done | `2026-02-03-android-keystore-authentication` |
| Crypto-Shredding | Done | `2026-02-02-crypto-shredding` |
| GDPR Compliance | Done | DPIA v1.2 + controller model documented |
| Protocol Hardening Gap 1 | Done | Noise NK inner transport encryption (relay + core) |

### Phase 2: Core Exchange

Core protocol and payload modules complete. Platform hardware adapters deferred to platform integration.

| Feature | Status | Problem Record |
|---------|--------|----------------|
| Mutual Offline QR Exchange | Done | `2026-02-03-mutual-offline-exchange` — symmetric DH, fresh ephemeral keys |
| BLE Exchange | Done | `2026-02-03-ble-exchange` — `BLETransport` trait, GATT service, `ExchangeBle` payload |
| NFC Active Exchange | Done | `2026-02-02-nfc-active-device-exchange` — `ExchangeNfc` payload, APDU protocol |

### Phase 3: Platform Completeness

Core Rust modules done and tested for all 6 features. Remaining work is platform UI wiring (iOS, Android, Desktop, CLI, TUI).

| Feature | Status | Problem Record |
|---------|--------|----------------|
| Internationalization | Core done | `src/i18n.rs` — 18 tests, 4 locales. Platform UI wiring remaining |
| In-app Help Updates | Core done | `src/help.rs` — 14 tests, 16 FAQs. Platform UI layout remaining |
| Remote Theming Updates | Core done | `src/theme.rs` — 24 tests, 12 themes. Platform theme application remaining |
| Aha Moments | Core done | UniFFI bindings exposed. Trigger integration at milestones remaining |
| Performance & Scalability | Core done | `2026-02-01-performance-scalability` — pagination + batch sync, 19 tests. Real device profiling remaining |
| Platform Edge Cases | Core done | `2026-02-01-platform-edge-cases` — crash recovery + clock skew, 22 tests. Platform service hardening remaining |

### Phase 4: Privacy & Hardening

Advanced privacy and testing infrastructure.

| Feature | Status | Problem Record |
|---------|--------|----------------|
| Tor Mode | Pending | `2026-01-26-tor-mode` — real Tor integration, not proxy stub |
| Relay Federation | Phase 1 done | Phase 1 merged: static peer offloading, forwarding hints, integrity hashing (`relay!22`). Phase 2-4 pending: client multi-relay, gossip discovery, mutual TLS |
| Protocol Hardening | Done | All 3 gaps closed: inner transport encryption (Noise NK), AEAD identity binding, fixed-size padding |
| Cargo Fuzz Targets | Done | `2026-02-03-cargo-fuzz-targets` — 10 targets covering all attack surfaces |
| Testing Infrastructure Gaps | Pending | `2026-02-03-testing-infrastructure-gaps` — Miri, cargo-deny CI, MASVS checklist |
| Accessibility Audit | Pending | Formal audit with real screen readers |

### Phase 5: Validation

All features integrated, verified on simulators and emulators.

| Milestone | Description |
|-----------|-------------|
| E2E on simulators/emulators | Full test suite on iOS Simulator, Android Emulator, desktop dev builds |
| Relay on VPS | Production relay deployment verified |
| Full regression green | All 18 features passing, no regressions |

### Phase 6: Real Device Testing

Physical devices, cross-platform verification, production preparation.

| Milestone | Description |
|-----------|-------------|
| Physical iOS + Android | Real hardware testing on iPhones and Android phones |
| Cross-platform exchange | iOS <-> Android exchange verified (QR, BLE, NFC) |
| Production release prep | App store submissions, release tagging, monitoring |

---

## Ship Criteria

| Requirement | Status | Verification |
|-------------|--------|--------------|
| E2E encryption works | Done | Rust tests |
| All exchange methods real | Pending | QR + BLE + NFC on real hardware |
| Card updates sync | Pending | Cross-platform E2E test |
| Recovery works | Pending | Cross-platform E2E test |
| No plaintext secrets | Done | Code review |
| Rate limiting active | Done | Relay config |
| Persistence working | Done | SQLite default |
| No critical vulnerabilities | Done | cargo-audit: 0 vulns (2026-02-02) |
| Tor mode functional | Pending | Real Tor integration test |
| GDPR compliance | Pending | Data export, deletion, consent |
| i18n on all platforms | Pending | String extraction, locale switching |
| Accessibility audited | Pending | Screen reader validation |
| Fuzz targets covering attack surfaces | Done | 10 targets: QR, relay, padding, delta, recovery, NFC, BLE (x2), exchange payload, encrypted exchange |
| All platform edge cases handled | Core done | Crash recovery + clock skew tested; platform hardening remaining |
| TDD followed for all features | Ongoing | Red→Green→Refactor, no exceptions |
| 90%+ test coverage (vauchi-core) | Ongoing | Real crypto in tests, no mocking |

---

## Feature Audit Correction

The automated feature-audit.sh reports misleading coverage numbers:

| Feature | Audit Says | Reality |
|---------|------------|---------|
| visibility_labels | "0% done" | Code exists: labels.rs, storage/labels.rs, API |
| contact_recovery | "0% coverage" | 28k lines in recovery/mod.rs |

The audit counts keyword matches in tests, not implementation completeness.
**Action**: Fix audit script OR ignore these metrics.

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
| BLE/NFC platform differences | High | Medium | Test on both iOS and Android early |
| Tor integration complexity | Medium | Medium | Prototype with arti crate first |
| Real device issues | Medium | High | Validate on simulators/emulators first, then physical devices |
| App store rejection | Low | Medium | Follow guidelines, test on TestFlight first |
| Relay overload | Low | Medium | Rate limiting in place |
| Security vulnerability | Low | High | Run cargo-audit, fuzz targets, code review |

---

## Verification

**Last verification**: 2026-02-04
