# P7: Pre-Production Checklist

**Status**: P0 Complete
**Priority**: P0 (Blocking production launch)
**Depends on**: P6 (Recovery UI)

## Overview

Items to address before production launch. GitHub/governance deferred to P8.

---

## 1. Documentation Gaps

### 1.1 FAQ Updates ✅ COMPLETE
| Question | Action | File | Status |
|----------|--------|------|--------|
| Storage requirements | Add: ~50MB app, data scales with contacts | `docs/faq.md` | ✅ |
| Battery usage | Add: Minimal, no background polling | `docs/faq.md` | ✅ |
| Background data | Add: Only during active sync | `docs/faq.md` | ✅ |
| Permissions needed | Add: Camera for QR, no contacts access | `docs/faq.md` | ✅ |
| Sync timing | Add: Real-time when online, queued offline | `docs/faq.md` | ✅ |

### 1.2 Workflow Guides ✅ COMPLETE
Created `docs/workflows/` directory with step-by-step guides:
- `2026-01-22-exchange.md` - Contact exchange flow ✅
- `2026-01-22-visibility.md` - Managing field visibility ✅
- `2026-01-22-recovery.md` - Social recovery process ✅
- `2026-01-22-multi-device.md` - Multi-device setup ✅

---

## 2. Relay Server Security

### 2.1 TLS Startup Warning ✅ COMPLETE (already implemented)
**Issue**: Relay starts without warning if no TLS configured
**Risk**: Operators may accidentally run unencrypted

| File | Change | Status |
|------|--------|--------|
| `vauchi-relay/src/main.rs` | Add TLS proxy detection at startup | ✅ |
| `vauchi-relay/src/config.rs` | Add `RELAY_TLS_VERIFIED` env var | ✅ |

Detection method (implemented in main.rs:47-71):
1. Check if binding to localhost (allowed for dev)
2. Or `RELAY_TLS_VERIFIED=true` env var
3. **Refuse to start** (not just warn) if neither present

### 2.2 Community Relay Guide ✅ COMPLETE
Created `docs/deployment/2026-01-23-community-relay.md`:
- Why run a relay (data sovereignty) ✅
- Minimum requirements (512MB-1GB RAM, 5-10GB storage) ✅
- One-command Docker setup ✅
- Monitoring tips ✅

---

## 3. In-App Help Links ✅ COMPLETE

Add to Settings screen on all platforms:

| Link | URL |
|------|-----|
| User Guide | `https://vauchi.app/user-guide` |
| FAQ | `https://vauchi.app/faq` |
| Report Issue | `https://github.com/vauchi/issues` |
| Privacy Policy | `https://vauchi.app/privacy` |

| Platform | File | Status |
|----------|------|--------|
| Android | `android/app/src/main/kotlin/.../SettingsScreen.kt` | ✅ |
| iOS | `ios/Vauchi/Views/SettingsView.swift` | ✅ |
| Desktop | `code/vauchi-desktop/ui/src/pages/Settings.tsx` | ✅ |
| TUI | `code/vauchi-tui/src/ui/settings.rs` | ✅ |

Also add version display: "Version 1.0.0 (build 123)" ✅

---

## 4. Pre-Launch Testing

### 4.1 Cross-Platform E2E
| From | To | Exchange | Sync | Recovery |
|------|-----|----------|------|----------|
| Android | iOS | ☐ | ☐ | ☐ |
| Android | Desktop | ☐ | ☐ | ☐ |
| iOS | Desktop | ☐ | ☐ | ☐ |
| CLI | TUI | ☐ | ☐ | ☐ |

### 4.2 Accessibility Audit
- [ ] Android TalkBack
- [ ] iOS VoiceOver
- [ ] Desktop screen readers (NVDA, VoiceOver)

### 4.3 Load Testing
- [ ] 1000 concurrent WebSocket connections
- [ ] 10,000 messages/minute throughput
- [ ] 7-day retention under load

---

## 5. Infrastructure

### 5.1 Production Relay ✅ COMPLETE
- [x] Provision VPS (IONOS - 87.106.25.46)
- [x] Configure TLS (kamal-proxy with auto Let's Encrypt)
- [x] Deploy relay (relay.vauchi.app)
- [ ] Set up monitoring (Prometheus + Grafana) - deferred
- [ ] Configure alerting - deferred

### 5.2 App Store Preparation

See: `deployment/2026-01-23-app-store-metadata.md` for full listings.

**Android**:
- [ ] Generate signed APK/AAB
- [x] Store listing (screenshots, description) - metadata drafted
- [x] Privacy policy URL (vauchi.app/privacy)
- [ ] Submit to Google Play

**iOS**:
- [ ] Archive for App Store
- [x] App Store Connect listing - metadata drafted
- [ ] Submit for review

**Desktop**:
- [ ] macOS notarization
- [ ] Windows code signing
- [ ] Create installers (DMG, MSI, AppImage)

---

## Priority Order

**P0 - Blocking** ✅ ALL COMPLETE:
- ✅ Relay TLS warning (already implemented)
- ✅ FAQ performance questions (added)
- ✅ In-app help links (all platforms)

**P1 - Important**:
- ✅ Workflow documentation
- Cross-platform E2E testing (Maestro flows ready, pending real device testing)

**P2 - Future**:
- Accessibility audit
- ✅ Community relay guide

---

## Verification

- [x] All P0 items complete
- [x] All tests passing (900+)
- [ ] Cross-platform E2E tested (blocked - needs devices)
- [x] Relay deployed with TLS (relay.vauchi.app)
- [ ] App stores ready for submission
