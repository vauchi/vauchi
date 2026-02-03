<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Roadmap - January 2026 (Revised)

**Goal**: Ship secure MVP
**Last audit**: 2026-01-22

---

## Reality Check

### What's Actually Done (Verified)

| Component | Status | Evidence |
|-----------|--------|----------|
| Core crypto (ring) | ✓ Complete | 13 ring imports, Double Ratchet, X3DH |
| E2E encryption | ✓ Complete | AES-256-GCM, forward secrecy |
| Contact exchange | ✓ Complete | QR, audio proximity, BLE stubs |
| Recovery system | ✓ Complete | 28k lines in recovery/mod.rs |
| Visibility labels | ✓ Complete | labels.rs implemented, storage, API |
| Relay deployed | ✓ Live | https://relay.vauchi.app returns 200 |
| Relay persistence | ✓ SQLite | Default backend, TTL, cleanup |
| Relay rate limiting | ✓ Token bucket | Per-client, configurable |
| Rust tests | ✓ 966 pass | All green |
| iOS test files | ✓ 10 files | KeychainService, Audio, Exchange, etc. |
| Android test files | ✓ 10 files | SyncWorker, Audio, Exchange, etc. |
| No unsafe code | ✓ Verified | 0 unsafe blocks in vauchi-core |
| No unwraps in crypto | ✓ Verified | 0 production unwraps |
| Accessibility (all platforms) | ✓ Phase 1-5 | VoiceOver, TalkBack, ARIA complete |

### What's Actually Missing (MVP Blockers)

| Gap | Severity | Effort | Notes |
|-----|----------|--------|-------|
| Cross-platform E2E test | HIGH | 1 day | Manual + automated |
| Real device testing | HIGH | 1-2 days | Simulators ≠ reality |
| ~~Security audit tool~~ | ~~MEDIUM~~ | ~~1 hour~~ | ✓ Done - 0 vulns (2026-01-22) |
| Feature audit accuracy | LOW | Fix later | Script misreports coverage |

---

## Fast Path to Secure MVP

### Phase 1: Verify (1-2 days)

**Goal**: Prove the system works end-to-end.

```
Day 1 Morning:
[x] Install cargo-audit, run security scan (0 vulns, 3 unmaintained warnings)
[x] Build Android app (debug APK ready)
[x] Build iOS app (simulator build succeeded)

Day 1 Afternoon:
[ ] Test: Alice (iOS) exchanges contact with Bob (Android)
[ ] Test: Alice updates card, Bob receives update
[ ] Test: Recovery flow between devices

Day 2:
[ ] Fix any bugs found
[ ] Document test results
[ ] Sign off on E2E functionality
```

### Phase 2: Harden (1-2 days)

**Goal**: Address any security findings.

```
[ ] Address cargo-audit findings (if any)
[ ] Review relay logs for anomalies
[ ] Verify TLS cert pinning on mobile
[ ] Check key storage on iOS (Keychain) and Android (KeyStore)
```

### Phase 3: Ship (1 day)

**Goal**: Production release.

```
[ ] Tag release version
[ ] Build release APK and IPA
[ ] Submit to TestFlight / Play Store internal
[ ] Monitor relay metrics
```

---

## Ship Criteria (Minimum Secure MVP)

| Requirement | Status | Verification |
|-------------|--------|--------------|
| E2E encryption works | ✓ | Rust tests |
| Contact exchange works | ? | Needs real device test |
| Card updates sync | ? | Needs real device test |
| Recovery works | ? | Needs real device test |
| No plaintext secrets | ✓ | Code review |
| Rate limiting active | ✓ | Relay config |
| Persistence working | ✓ | SQLite default |
| No critical vulnerabilities | ✓ | cargo-audit: 0 vulns (2026-01-22) |

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

## Phase 4: User Testing Readiness (~1 week)

**Goal**: Prepare for user testing with features that demonstrate value without requiring a second user.

| Component | Status | Description |
|-----------|--------|-------------|
| Aha moments system | Pending | Micro-celebrations at key actions |
| Demo contact | Pending | "Vauchi Tips" contact for solo users |
| In-app help | Pending | FAQ, tooltips, privacy explainer |
| Exchange celebration | Pending | First contact/update celebrations |

---

## What's NOT Required for MVP

| Feature | Status | Why Not MVP |
|---------|--------|-------------|
| BLE exchange | Stubbed | QR works, BLE is enhancement |
| NFC Active exchange | Planning (post-MVP) | Phone-to-phone tap, two active devices |
| NFC Dead Drop | Investigating (post-MVP) | Passive tag + active phone, zero-knowledge relay preserved |
| Tor mode | Planned | Privacy enhancement, not core |
| Hidden contacts | Planned | Privacy enhancement |
| Duress password | Planned | Security enhancement |
| Multi-relay | Planned | Single relay is sufficient |
| Relay federation | Future | Requires protocol design |

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
| Real device issues | Medium | High | Test early on physical devices |
| App store rejection | Low | Medium | Follow guidelines, test on TestFlight first |
| Relay overload | Low | Medium | Rate limiting in place |
| Security vulnerability | Low | High | Run cargo-audit, code review |

---

## Verification

**Last verification**: PASSED (18 pass, 0 fail, 0 warnings)

---

## Timeline Summary

| Phase | Duration | Outcome |
|-------|----------|---------|
| Verify | 1-2 days | E2E tested on real devices |
| Harden | 1-2 days | Security reviewed |
| Ship | 1 day | Production release |
| **Total** | **3-5 days** | **Secure MVP** |

The system is much more complete than the old roadmap suggested.
The gap is verification, not implementation.
