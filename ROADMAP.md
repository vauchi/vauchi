<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Roadmap — March 2026

**Goal**: Production release reordered around the adoption funnel — discover → try → use → grow → protect
**Last audit**: 2026-03-17 (counter-intuitive MVP rescoping — see `_private/docs/plans/2026-03-17-counter-intuitive-mvp-rescoping-design.md`)

---

## Approach

The crypto foundation, core protocol, and backend are production-ready. The gap is the **adoption path**, not the vault. v0.1 scope stays complete but is reordered: everything a new user touches in their first 30 minutes is prioritized. Ship criteria split into hard gates (blocks release) and soft gates (ship without, patch in v0.1.x).

- **No stubs**: Every feature uses real hardware APIs, real crypto, real platform integrations
- **No mocks in production paths**: Mocks exist only in test code
- **Platform tiers**: Tier 1 (funnel) ships at 99%, Tier 2 (ecosystem) at 95%, Tier 3 ships if ready
- **Relay**: Deployed independently on VPS, available throughout development

---

## What's Done (Verified)

| Component | Status | Evidence |
|-----------|--------|----------|
| Core crypto (aws-lc-rs) | Done | FIPS 140-3, Double Ratchet, X3DH. **Note**: SP-30 will migrate to ed25519-dalek (pure Rust) |
| E2E encryption | Done | XChaCha20-Poly1305, forward secrecy |
| Contact exchange (QR) | Done | QR exchange working, audio proximity |
| Recovery system | Done | 1,062 lines in recovery/mod.rs |
| Visibility labels | Done | labels.rs implemented, storage, API |
| Relay deployed | Done | https://relay.vauchi.app returns 200 |
| Relay persistence | Done | SQLite default backend, TTL, cleanup |
| Relay rate limiting | Done | Token bucket, per-client, configurable |
| Contact exchange (Mutual QR) | Done | Symmetric DH, fresh ephemeral keys, 102 QR exchange tests |
| Contact exchange (NFC Active) | Done | 174-byte APDU payload, VNFC magic, 40 tests |
| Contact exchange (BLE) | Done | GATT transport trait, VBLE magic, 129 tests |
| Rust tests | Done | ~4,874 tests across repos (3,400 core, 504 relay, 199 cli, 320 tui, 242 mobile, 36 protocol, 120 e2e, 53 cabi) |
| iOS test files | Done | 23 files — KeychainService, Audio, Exchange, Accessibility, VRT, etc. |
| Android test files | Done | 20 files — SyncWorker, Audio, Exchange, Accessibility, Screenshots, etc. |
| No unsafe code | Done | 0 unsafe blocks in vauchi-core |
| No unwraps in crypto | Partial | 50 `.unwrap()` in `src/crypto/` (chain.rs, wasm.rs, padding.rs), 713 across all core src |
| Accessibility (Code remediation) | Done | iOS ~367 a11y refs, Android ~152 refs, Desktop ~373 aria- refs. Formal audit NOT done |
| Phase 2 Security Hardening | Done | Key storage fixed, cert pinning implemented, scans clean |
| Security scan | Done | cargo-audit: 0 vulns (2026-02-02, all repos). 1/6 P0 security gaps still open (proximity audio) |

---

## Priority Stack

| Priority | What | Status |
|----------|------|--------|
| **P0** | Close last P0 security gap (proximity audio wiring) | 1 remaining |
| **P1** | ADR-031 + ADR-030 (architecture blockers) | In progress |
| **P2** | UX audit + GUI violation fixes (65 violations) | Not started |
| **P3** | Onboarding polish (SP-21, 95% → 100%) | ~95% |
| **P4** | Web Demo completion (SP-29) — **pulled into v0.1** | ~65%, blocked on crypto-backend-abstraction |
| **P5** | Facilitated Introductions (minimal vouched version) — **pulled into v0.1** | Not started. Trust Metrics v27 migration done — no blocker. |
| **P6** | Tier 1 platforms to 99% + Anonymous Sender Protocol | iOS/Android ~95%, CLI ~95%, Anonymous Sender ~40% |
| **P7** | Social network picker UI | Core done, 0 platform UI |
| **P8** | Resistance features remaining gaps | ~55% |
| **P9** | Tier 2 platforms to 95% (macOS, Windows, GTK, TUI) | 80-95% |
| **P10** | Contact enrichment (birthday, annotations) + relay uptime monitoring (hard gate, SP-25) | Core done + ops minimum |
| **P11** | Tier 3 (Linux Qt) — ship if ready | ~80% |

---

## What's Required

### P0: Security Gap Closure (5/6 CLOSED)

| Gap | Severity | Status | Notes |
|-----|----------|--------|-------|
| Device Linking Proximity | **CRITICAL** | **CLOSED** | Mandatory ProximityProof, two-phase approval |
| Account Deletion Relay Purge | **HIGH** | **CLOSED** (archived) | Core DeletionManager returns revocations. **GDPR verification required**: confirm iOS/Android send revocations, relay purges blobs, contacts process revocation |
| Proximity Verification Integration | **MEDIUM** | **OPEN** | 290 LOC in proximity.rs. `verify_proximity_two_way()` called in session.rs:986 — verify platform wiring |
| Fingerprint Verification UI | **MEDIUM** | **CLOSED** | UX refinement only |
| Locked device startup iOS | **MEDIUM** | **CLOSED** | Fixed |
| Field Validation Core-Mobile | None | **CLOSED** (pre-existing) | Core + UniFFI + iOS + Android all wired — was never a gap |

### P1: Architecture Blockers (Layer 0)

| Feature | Status | Notes |
|---------|--------|-------|
| ADR-031: Exchange Architecture Unification | In progress | linux-gtk done. Core generalization + platform wiring remaining |
| ADR-030: Transport Type-Erasure | Phase 1 done (folded into ADR-031) | Phase 1 core type-erasure complete. CABI storage + Windows/Linux-Qt relay still pending (depends on ADR-031) |
| CABI Completion | Blocked on ADR-030 | 6 missing screens, CI distribution pipeline |
| SP-30: Crypto Backend Abstraction | Planning | aws-lc-rs → pure Rust (ed25519-dalek). Blocks Web Demo WASM. Problem record: `2026-03-16-crypto-backend-abstraction` |

### P2: UX Audit + GUI Guideline Compliance

65 violations of `gui-guidelines.md` across 3 audited platforms. `ux-guidelines.md` adopted 2026-03-10, not yet audited.

| Rule | Desktop | Android | iOS | Total |
|------|---------|---------|-----|-------|
| UI-01: No dialogs for reversible actions | 2 | 3 | 4 | 9 |
| UI-02: Confirm irrevocable inline (**hard gate**) | 4 | 6 | 3 | 13 |
| UI-03: Inline over overlay | 10 | 13 | 2 | 25 |
| UI-04–08: Other rules | 8 | 6 | 4 | 18 |
| **Total** | **24** | **28** | **13** | **65** |

### P3: Onboarding

| Feature | Status | Notes |
|---------|--------|-------|
| Onboarding (SP-21) | ~95% | Core state machine done (11 steps, 19 tests). All platforms wired. Web-demo wizard + polish remaining |

### P4: Web Demo (PULLED INTO v0.1)

| Feature | Status | Notes |
|---------|--------|-------|
| Web Demo (SP-29) | ~65% | Blocked on SP-30 crypto-backend-abstraction. Then: WASM bridge, onboarding wizard, card creation, visibility demo, simulated exchange, demo contact, download CTA |

### P5: Facilitated Introductions (PULLED INTO v0.1)

| Feature | Status | Notes |
|---------|--------|-------|
| Vouched Introduction (SP-31) | Not started | Minimal: introduction message type, consent state machine, invitation code. Both parties still meet in person. Trust Metrics v27 done — no blocker. |

### P6: Anonymous Sender Protocol

| Feature | Status | Notes |
|---------|--------|-------|
| Anonymous Sender (SP-32) | ~40% core | Epoch-based derivation, relay anonymity, recipient resolution. Wire protocol changes — must land before real device testing. Problem record: `2026-03-17-anonymous-sender-protocol` |

### Platform Tiers

**Tier 1 — "The Funnel" (ship at 99%)**

| Platform | Status | Key gaps |
|----------|--------|----------|
| iOS | ~95% | Resistance stubs → UniFFI (duress PIN hard gate), GUI violations |
| Android | ~95% | Resistance stubs → UniFFI (duress PIN hard gate), GUI violations |
| CLI | ~95% | Minor gaps |
| Web Demo | ~65% | Blocked on crypto-backend-abstraction |

**Tier 2 — "The Ecosystem" (ship at 95%)**

| Platform | Status | Key gaps |
|----------|--------|----------|
| macOS | ~90% | ADR-031 exchange |
| Windows | ~80% | ADR-030 transport, action feedback loop |
| Linux GTK | ~95% | 5% polish |
| TUI | ~85% | Contact actions, ADR-031 exchange flow |

**Tier 3 — "Ship if ready"**

| Platform | Status | Key gaps |
|----------|--------|----------|
| Linux Qt | ~80% | Test framework, exchange, SecureStorage |

### Resistance Features (v0.1)

| Feature | Status | Notes |
|---------|--------|-------|
| Duress PIN | ~80% | Core+storage+CLI+mobile UI done. **Hard gate**: auth→decoy flow on iOS+Android |
| Emergency Broadcast | ~70% | Core+storage+CLI+Desktop+Android done. Missing: locales, iOS config, TUI, send flow |
| Hidden Contact UI | Done | All platforms |
| Tor Mode | Core done | Circuit isolation polish → v0.2 |

### Social Network Integration (v0.1)

Core `SocialNetworkRegistry` + `ContentManager` + bundled networks.json exist. Remote update via CDN with SHA-256 + Ed25519. **Platform UI wiring needed** — iOS + Android first (P7).

### Phase 5: Validation

| Milestone | Status | Description |
|-----------|--------|-------------|
| Visual Regression Testing | Testing | ~158 baselines across platforms (69 iOS, 23 Android, 66 TUI). CI stabilization remaining |
| E2E on simulators/emulators | Pending | Full test suite on iOS Simulator, Android Emulator |
| Relay on VPS | Done | Production relay deployment verified |
| Full regression green | Pending | All features passing, no regressions |

### Phase 6: Real Device Testing

| Milestone | Description |
|-----------|-------------|
| Physical iOS + Android | Real hardware testing on iPhones and Android phones |
| Cross-platform exchange | iOS <-> Android exchange verified (QR, BLE, NFC) |
| Production release prep | App store submissions, release tagging, monitoring |

---

## Ship Criteria

### Hard Gates (blocks release)

| # | Criterion | Status |
|---|-----------|--------|
| 1 | P0 security gap closed (proximity audio wired into exchange) | 1 remaining |
| 2 | E2E encryption verified on real devices | Pending |
| 3 | Cross-platform exchange works (iOS ↔ Android QR) | Pending |
| 4 | Onboarding completes without confusion on iOS + Android | ~95% |
| 5 | Web demo loads and runs the happy path (depends on #9) | ~65%, blocked on crypto-backend-abstraction |
| 6 | UX audit complete on Tier 1 platforms | Not started |
| 7 | No critical GUI violations on Tier 1 (UI-02: irrevocable action confirmations) | 13 violations |
| 8 | Recovery works cross-platform | Pending |
| 9 | crypto-backend-abstraction merged (aws-lc-rs → pure Rust) | Planning |
| 10 | 90%+ test coverage vauchi-core | Ongoing |
| 11 | Anonymous Sender Protocol complete | ~40% core |
| 12 | Offline happy path works (card creation + QR exchange + contact view, zero network) | Not verified |
| 13 | Update propagation verified cross-platform (Alice changes field → Bob sees it) | Pending |
| 14 | Backup/restore on real devices | Not verified |
| 15 | Relay uptime monitoring + alerting (minimum: health check + webhook) | Partial — Tier 1 done, dashboard + uptime-kuma config done, deployment pending |
| 16 | Duress PIN works on iOS + Android (auth → decoy flow) | ~80% |
| 17 | Account deletion relay purge verified end-to-end (GDPR Art. 17) | Platform wiring unverified |

### Soft Gates (ship without, patch in v0.1.x)

| # | Criterion | Rationale |
|---|-----------|-----------|
| 1 | All 65 GUI violations fixed | UI-02 is hard gate. UI-01/UI-03 are polish. |
| 2 | Facilitated Introductions live | Growth feature. Launch without if not ready. |
| 3 | Social network picker on all platforms | iOS + Android first. Desktop follows. |
| 4 | Resistance features 100% wired (except duress PIN) | Core works. CLI fallback. |
| 5 | Accessibility formal audit (VoiceOver/TalkBack) | Code remediation done. |
| 6 | Tier 2 platforms at 95% | Ship at whatever state. Tier 1 is the gate. |
| 7 | ~~Trust Metrics v19 migration~~ | **Resolved**: v27 migration already in code. No longer a gate. |
| 8 | Birthday field, annotations, statistics | Polish. |
| 9 | Post-onboarding engagement flow | Demo contact covers partially. |
| 10 | Clock drift graceful error handling | >120s drift rejection needs human-readable error. |
| 11 | App store submission readiness (SP-5 remaining manual actions) | Operational, not feature. |
| 12 | Performance and robustness (SP-12c, 69 scenarios) | 0% implemented, intake. Lowest soft gate. |

---

## Deferred to v0.2+

| Feature | Status | Notes |
|---------|--------|-------|
| Mesh Exchange BLE platform UI | Core done, 0 platform code | 30 Gherkin scenarios. Event/crowd niche. |
| Panic Widget (WidgetKit/AppWidget) | ShredManager done | Shred works in-app. Widget is chrome. |
| Tor circuit isolation polish | Core done | Tor mode works. Hardening. |
| Contact Network Statistics | 0% | Pure computation. No demand signal. |
| NFC Dead Drop Exchange | Planning | Passive NFC tag as dead drop. Design only. |
| Steganographic Shell | Design only | Post-launch. |

---

## Critical Paths (Parallel)

```
Path 1: Discovery Funnel
  crypto-backend-abstraction → Web Demo WASM → onboarding wizard → download CTA

Path 2: Platform Ecosystem
  ADR-031 → macOS/Windows/TUI exchange wiring
  ADR-030 → Windows/Linux-Qt relay connectivity

Path 3: Growth Engine
  Facilitated Introductions (Trust Metrics v27 done — no blocker)

Independent:
  P0 proximity audio wiring
  Anonymous Sender Protocol (core + relay)
  UX audit + GUI violation fixes (continuous)
  GDPR deletion verification
  Resistance feature wiring
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| GDPR deletion gap | Medium | **Critical** | Verify iOS/Android send revocations + relay purges. Hard gate #17. |
| Anonymous Sender delay | Medium | High | ~40% done, wire protocol changes. Must land before device testing. |
| crypto-backend-abstraction complexity | Medium | High | Decision made (pure Rust). Implementation plan exists. Blocks Web Demo. |
| GUI guideline debt | High | Medium | 65 violations. Fix UI-02 (irrevocable) first. Rest is polish. |
| UX guideline debt | Medium | Medium | Rules adopted 2026-03-10, not audited. Audit Tier 1 first. |
| Social network picker missing | Medium | Medium | Core ready, UIs not wired. Wire iOS+Android first. |
| Web Demo trust perception | Low | Medium | "Demo only — data stays in browser" banner + link to real apps. |
| Facilitated Introductions scope creep | Medium | Medium | Minimal: vouched introduction, in-person exchange still required. |
| BLE/NFC platform differences | High | Medium | Test on both iOS and Android early |
| Real device issues | Medium | High | Validate on simulators/emulators first, then physical devices |
| App store rejection | Low | Medium | Follow guidelines, test on TestFlight first |
| Relay overload | Low | Medium | Rate limiting in place |

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

## Verification

**Last verification**: 2026-03-17 (counter-intuitive MVP rescoping)

<details>
<summary>2026-03-17 Counter-Intuitive MVP Rescoping</summary>

- **Approach A: "Fix the Funnel"** selected — keep full scope, reorder around adoption path
- **Web Demo pulled into v0.1** (was post-v0.2). Zero-friction discovery. Blocked on crypto-backend-abstraction.
- **Facilitated Introductions pulled into v0.1** (was post-v0.2). Minimal "Vouched Introduction" — both parties still meet in person. Trust Metrics v27 done — no blocker.
- **Anonymous Sender Protocol promoted to hard gate** — metadata privacy is a core promise.
- **GDPR deletion verification added as hard gate** — Art. 17 compliance, not just feature completeness.
- **Duress PIN on mobile promoted to hard gate** — target audience safety feature.
- **Offline happy path added as hard gate** — principle UX-08 compliance.
- **Platform tiers established**: Tier 1 (iOS/Android/CLI/Web Demo), Tier 2 (macOS/Windows/GTK/TUI), Tier 3 (Linux Qt).
- **Deferred to v0.2**: Mesh BLE platform UI, Panic Widget native, Tor circuit isolation, Contact Statistics, NFC Dead Drop, Steganographic Shell.
- **Hard/soft gate split** replaces monolithic ship criteria (17 hard, 12 soft).

</details>

<details>
<summary>2026-02-26 Scope Consolidation</summary>

- **SP-6 resistance features moved to v0.1** (was Post-MVP). Deep audit found ~65-75% complete — NOT stubs as previously claimed. ShredManager, duress PIN, emergency broadcast all have multi-layer implementations (core+storage+CLI+mobile UI). Missing: locale keys, some platform gaps.
- **SP-19 GUI Guideline Compliance added** — 65 violations found across 3 platforms. Problem record exists with full investigation.
- **SP-20 Social Network Integration added** — core registry infrastructure complete but no platform UI picker wired.
- **Trust Metrics corrected** — ~95% implemented in core (TrustLevel enum, ProfileValidation, scoring). v27 migration done. v19 reference was stale (v19 = duress PIN password schema, not trust metrics).
- **Birthday Field clarified** — needs real `FieldType::Birthday` with date validation. Currently only test mock.
- **4 P0 security gap problem records created** — device linking proximity, account deletion relay purge, proximity audio integration, fingerprint verification UI.
- **SP-4 now DONE** — desktop strip=true + LTO + opt-level="z" (20→7 MB). All release builds verified.
- **SP-5 now ~97%** — icons (all platforms), signing, privacy policy, Playwright a11y audit (14/14) all done. Only manual store actions remain.
- **Desktop ARIA audit done** — 4 PASS, 14 PARTIAL, 6 FAIL. Problem record `2026-02-26-desktop-accessibility-remediation` created.
- **Post-launch only** (as of 2026-02-26; **superseded by 2026-03-17 rescoping** — Facilitated Introductions + Web Demo pulled into v0.1, Windows moved to Tier 2): NFC Dead Drop, ~~Facilitated Introductions~~, ~~Demo Web App~~, ~~Windows (conditional)~~.

</details>

<details>
<summary>2026-02-25 Re-Verification Findings (partially superseded)</summary>

7 parallel agents verified all SP statuses against actual code. Key corrections:

- **P0 security gaps**: Previous "ALL 5 CLOSED" was incorrect. Only 1/5 closed (field validation). 4 remain open.
- **SP-4**: Was ~98%, corrected to ~75-80% → **now DONE** (see 2026-02-26 above).
- **SP-5**: Was ~90%, corrected to ~85% → **now ~97%** (see 2026-02-26 above).
- **SP-8b**: Was "Phase 2 done", now fully DONE. All 4 phases verified complete.
- **SP-9**: Was "~10 remain", now ~95%. Most cross-repo items verified merged. 2-4 items unclear.
- **SP-11**: Was "Phase 1-5 done", now ~35%. Label counts were wrong. No formal audit done.
- **SP-14**: Confirmed Phase 1 DONE with verified metrics.

</details>
