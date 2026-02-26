<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Roadmap - February 2026

**Goal**: Full-feature production release — all features implemented with real code, no stubs or mocks
**Last audit**: 2026-02-26 (code-level audit, scope consolidated — resistance features, GUI compliance, social networks all v1.0)

---

## Approach

All features must be production-ready with real implementations before real device testing begins. Resistance features, GUI guideline compliance, and social network integration are v1.0 — nothing deferred except post-launch items.

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
| Rust tests | Done | ~2,981 tests across 166+ files (2,269 core, 282 relay, 118 cli, 186 tui, 75 mobile, 21 protocol, 30 e2e) |
| iOS test files | Done | 17 files — KeychainService, Audio, Exchange, Accessibility, VRT, etc. |
| Android test files | Done | 13 files — SyncWorker, Audio, Exchange, Accessibility, Screenshots, etc. |
| No unsafe code | Done | 0 unsafe blocks in vauchi-core |
| No unwraps in crypto | Done | 0 production unwraps |
| Accessibility (Code remediation) | Done | iOS ~367 a11y refs, Android ~152 refs, Desktop ~373 aria- refs. Formal audit (VoiceOver/TalkBack) NOT done |
| Phase 2 Security Hardening | Done | Desktop key storage fixed, cert pinning implemented, scans clean |
| Security scan | Done | cargo-audit: 0 vulns (2026-02-02, all repos). Note: 4 P0 security GAPS still open (see below) |

---

## What's Required

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

### Phase 4: Privacy, Hardening & Features

| Feature | Status | Notes |
|---------|--------|-------|
| Tor Mode | Done | 594 lines, feature-gated `tor = []`, arti-ready |
| Relay Federation | Done | All 4 phases: static federation, gossip discovery, mutual TLS (1,526 lines) |
| Protocol Hardening | Done | Noise NK + fixed-size padding + AEAD identity binding (confirmed 2026-02-20 deep check) |
| Cargo Fuzz Targets | Done | 10 targets covering all attack surfaces |
| Testing Infrastructure Gaps | Done | cargo-deny CI (all repos), MASVS L1 self-assessment |
| Recovery Trust Contacts | Done | All platforms complete |
| CLI API Drift | Done | All 17 compilation errors resolved |
| Relay Authentication | Done | Ed25519 handshake verification in relay. Client hex format in core |
| X3DH Protocol Hardening | Done | Migration v18: visibility_rules encrypted, PBKDF2 600K |
| Trust Metrics & Indicators | ~95% implemented | `TrustLevel` enum (4 levels), `ProfileValidation`, scoring in core. Needs v19 migration |
| Accessibility Audit | Planning | Formal audit with real screen readers |
| Birthday Field | Needs implementation | `FieldType::Birthday` with date validation — currently only test mock |
| Local Contact Annotations | Needs implementation | Migration v20. Depends on Trust Metrics v19 |
| Contact Network Statistics | Needs implementation | Pure computation, no migration |

### Resistance Features (v1.0)

| Feature | Status | Notes |
|---------|--------|-------|
| Duress PIN | ~80% | Core+storage+CLI+mobile UI done (51+98+119 LOC). Missing: locales, auth→decoy flow, TUI, desktop dialog |
| Panic Widget / Emergency Shred | ~75% | ShredManager done (1,075 LOC), iOS `panicShred()` done. Missing: Android widget, locales |
| Hidden Contact UI | Done | All platforms |
| Tor Mode Completion | Core done | Circuit isolation remaining |
| Emergency Broadcast | ~70% | Core+storage+CLI+Desktop+Android done (47+101+126+78 LOC). Missing: locales, iOS config, TUI, send flow |
| Mesh Exchange (BLE) | Core done | Zero platform implementation (30 Gherkin scenarios) |

### GUI Guideline Compliance (v1.0)

65 violations of `gui-guidelines.md` across 3 platforms. Zero infrastructure exists (no undo toast, inline confirm, click-to-edit).

| Rule | Desktop | Android | iOS | Total |
|------|---------|---------|-----|-------|
| UI-01: No dialogs for reversible actions | 2 | 3 | 4 | 9 |
| UI-02: Confirm irrevocable inline | 4 | 6 | 3 | 13 |
| UI-03: Inline over overlay | 10 | 13 | 2 | 25 |
| UI-04–08: Other rules | 6 | 5 | 0 | 11 |
| **Total** | **24** | **28** | **13** | **65** |

### Social Network Integration (v1.0)

Core `SocialNetworkRegistry` + `ContentManager` + bundled networks.json exist. Remote update via CDN with SHA-256 + Ed25519. **No platform UI wired** — no social network picker on any platform. Desktop `get_social_networks()` Tauri command exists but is never called.

### Security Gaps (Found in 2026-02-06 Code Audit)

Problem records created 2026-02-26. All must close before release.

| Gap | Severity | Status | Notes |
|-----|----------|--------|-------|
| Device Linking Proximity | **CRITICAL** | **OPEN** | Proximity check optional, not mandatory before `approveDeviceLink()`. Remote QR attack possible |
| Account Deletion Relay Purge | **HIGH** | **OPEN** | Core generates revocations but iOS/Android don't auto-send via relay. Contacts not notified |
| Proximity Verification Integration | **MEDIUM** | **OPEN** | 510+ lines audio code exists but orphaned from exchange flow. Not wired into ceremony |
| Fingerprint Verification UI | **MEDIUM** | **PARTIAL** | Fingerprints shown post-exchange but NOT during exchange confirmation step |
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

### Post-Launch Features (v1.1+)

| Feature | Status | Notes |
|---------|--------|-------|
| NFC Dead Drop Exchange | Planning | Passive NFC tag as physical dead drop |
| Facilitated Introductions | Investigating | Principle-compliant mutual introduction. Depends on Trust Metrics |
| Demo Web App | Planning | WASM-based web demo |
| Windows Release | Conditional | Ship if code signing cert obtained |

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
| Device linking proximity-verified | **Not done** | CRITICAL: must make proximity mandatory |
| Account deletion notifies contacts | **Not done** | Must auto-send revocations via relay |
| Relay client authentication | Done | Ed25519 handshake verification in relay |
| Proximity verification in exchange | **Not done** | Must wire audio code into exchange ceremony |
| Key fingerprint verification UI | **Not done** | Must display during exchange confirmation |
| Resistance features complete | ~65-75% | Duress, emergency, shred, mesh — locale keys + platform gaps remaining |
| GUI guidelines compliant | **Not done** | 65 violations across 3 platforms |
| Social network picker | **Not done** | Core registry exists, platform UIs not wired |
| Trust Metrics | ~95% | Needs v19 migration |
| Birthday field | **Not done** | Needs FieldType::Birthday with date validation |
| Local Contact Annotations | **Not done** | Needs v20 migration |
| Contact Network Statistics | **Not done** | Needs implementation |
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
| GUI guideline debt | High | Medium | 65 violations cause dialog fatigue. Fix before beta |
| Social network picker missing | Medium | Medium | Core ready, UIs not wired. Wire before beta |
| Tor integration complexity | Medium | Medium | Prototype with arti crate first |
| Real device issues | Medium | High | Validate on simulators/emulators first, then physical devices |
| App store rejection | Low | Medium | Follow guidelines, test on TestFlight first |
| Relay overload | Low | Medium | Rate limiting in place |
| Security vulnerability | Low | High | Run cargo-audit, fuzz targets, code review |

---

## Verification

**Last verification**: 2026-02-26 (code-level audit + scope consolidation)

<details>
<summary>2026-02-26 Scope Consolidation</summary>

- **SP-6 resistance features moved to v1.0** (was Post-MVP). Deep audit found ~65-75% complete — NOT stubs as previously claimed. ShredManager, duress PIN, emergency broadcast all have multi-layer implementations (core+storage+CLI+mobile UI). Missing: locale keys, some platform gaps.
- **SP-19 GUI Guideline Compliance added** — 65 violations found across 3 platforms. Problem record exists with full investigation.
- **SP-20 Social Network Integration added** — core registry infrastructure complete but no platform UI picker wired.
- **Trust Metrics corrected** — ~95% implemented in core (TrustLevel enum, ProfileValidation, scoring). Only v19 migration missing.
- **Birthday Field clarified** — needs real `FieldType::Birthday` with date validation. Currently only test mock.
- **4 P0 security gap problem records created** — device linking proximity, account deletion relay purge, proximity audio integration, fingerprint verification UI.
- **Post-launch only**: NFC Dead Drop, Facilitated Introductions, Demo Web App, Windows (conditional).

</details>

<details>
<summary>2026-02-25 Re-Verification Findings</summary>

7 parallel agents verified all SP statuses against actual code. Key corrections:

- **P0 security gaps**: Previous "ALL 5 CLOSED" was incorrect. Only 1/5 closed (field validation). 4 remain open.
- **SP-4**: Was ~98%, now ~75-80%. Desktop CI release build missing. Android APK exceeds size target.
- **SP-5**: Was ~90%, now ~85%. App store metadata is ~10%, not "remaining". App store submission 0%.
- **SP-8b**: Was "Phase 2 done", now fully DONE. All 4 phases verified complete.
- **SP-9**: Was "~10 remain", now ~95%. Most cross-repo items verified merged. 2-4 items unclear.
- **SP-11**: Was "Phase 1-5 done", now ~35%. Label counts were wrong. No formal audit done.
- **SP-14**: Confirmed Phase 1 DONE with verified metrics.

See `_private/docs/planning/todo/2026-02-15-master-plan.md` for corrected statuses.

</details>
