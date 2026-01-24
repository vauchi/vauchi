# Roadmap to Feature-Complete

**Last Updated**: January 2026
**Feature Source of Truth**: `features/*.feature` (separate repo)

---

## Current Status

| Platform | Core Features | Sync | Recovery | Device Mgmt |
|----------|--------------|------|----------|-------------|
| CLI | ✅ | ✅ | ✅ | ⚠️ Partial |
| TUI | ✅ | ⚠️ Stub | 📋 CLI | ⚠️ Partial |
| Desktop | ✅ | ✅ | ✅ | ⚠️ TODO |
| Android | ✅ | ✅ | ⚠️ UI stub | ⚠️ Partial |
| iOS | ✅ | ✅ | ❌ No UI | ❌ Missing |

**Legend**: ✅ Complete | ⚠️ Partial | ❌ Missing | 📋 Delegates

---

## P6: Recovery UI for Mobile (HIGH)

**Effort**: 3-5 days | **Blocks**: User safety
**Feature**: `features/contact_recovery.feature`

Core and bindings are **COMPLETE**. Only mobile UI wiring needed.

| Task | Platform | Files |
|------|----------|-------|
| Wire recovery methods | Android | `RecoveryScreen.kt`, `MainViewModel.kt` |
| Create recovery view | iOS | New `RecoveryView.swift` |
| Add to navigation | iOS | `ContentView.swift` |
| Add ViewModel methods | iOS | `VauchiViewModel.swift` |

**See**: `P6-recovery-mobile.md` for implementation details.

---

## P7: Pre-Production (HIGH)

**Effort**: 1 week | **Blocks**: Launch

| Section | Tasks |
|---------|-------|
| Documentation | FAQ updates, workflow guides |
| Relay security | TLS warning at startup |
| In-app help | Help links in Settings on all platforms |
| Testing | Cross-platform E2E |
| Infrastructure | Relay deployment, app store prep |

**See**: `P7-pre-production-checklist.md` for details.

---

## P8: GitHub & Governance (DEFERRED)

**Effort**: 2-3 days | **Post-launch**

| Task | Files |
|------|-------|
| LICENSE | `/LICENSE` |
| SECURITY.md | `/SECURITY.md` |
| CODE_OF_CONDUCT.md | `/CODE_OF_CONDUCT.md` |
| CONTRIBUTING.md | `/CONTRIBUTING.md` |
| GitHub templates | `.github/` |
| CI workflow | `.github/workflows/ci.yml` |

**See**: `P8-github-governance.md` for details.

---

## Minor Gaps (Parallel)

### Edit Display Name
Core has `Identity::set_display_name()`. Need UI.

| Platform | File |
|----------|------|
| CLI | `commands/init.rs` |
| TUI | `ui/settings.rs` |
| Desktop | `pages/Settings.tsx` |
| Android | `HomeScreen.kt` |
| iOS | `SettingsView.swift` |

### TUI Real Sync
Currently stubbed. Port from Desktop.

| File | Change |
|------|--------|
| `vauchi-tui/src/backend.rs` | Add WebSocket sync |
| `vauchi-tui/src/ui/sync.rs` | Real status display |

**Reference**: `vauchi-desktop/src-tauri/src/commands/sync.rs`

### Device Management
**Feature**: `features/device_management.feature`

| Task | Platform | File |
|------|----------|------|
| Complete join flow | Desktop | `commands/devices.rs` (line 135) |
| Device list UI | iOS | New `DevicesView.swift` |
| Link generation | Android | `DevicesScreen.kt` |

### iOS Field Edit
| File | Change |
|------|--------|
| `Views/ContactCard.swift` | Add edit button |
| `ViewModels/CardViewModel.swift` | Add updateField |

### Android Contact Verification
| File | Change |
|------|--------|
| `ui/ContactDetailScreen.kt` | Add verify button |
| `MainViewModel.kt` | Add verifyContact |

---

## Priority Order

1. **P6** (3-5 days): Recovery UI - critical safety
2. **P7** (1 week): Pre-production - blocks launch
3. **Minor gaps** (parallel): Edit name, TUI sync, device mgmt
4. **P8** (post-launch): GitHub governance

---

## Success Criteria

Per feature files:
- [ ] `contact_recovery.feature`: Mobile UI complete
- [ ] `device_management.feature`: All platforms testable
- [ ] `sync_updates.feature`: TUI has real sync

Infrastructure:
- [ ] Relay at relay.vauchi.app with TLS
- [ ] Cross-platform E2E verified
- [ ] 883+ tests passing

---

## Feature Matrix (Current → Target)

| Feature | CLI | TUI | Desktop | Android | iOS |
|---------|-----|-----|---------|---------|-----|
| Identity management | ✅ | ✅ | ✅ | ✅ | ✅ |
| Edit display name | ✅ | ❌ | ❌ | ❌ | ❌ |
| Card add/edit/remove | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| QR exchange | ✅ | ✅ | ✅ | ✅ | ✅ |
| Contact search | ✅ | ✅ | ✅ | ✅ | ✅ |
| Contact verification | ✅ | ✅ | ✅ | ❌ | ✅ |
| Visibility control | ✅ | ✅ | ✅ | ✅ | ✅ |
| Relay sync | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| Backup export/import | ✅ | ✅ | ✅ | ✅ | ✅ |
| Device management | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ❌ |
| Recovery workflow | ✅ | 📋 | ✅ | ⚠️ | ❌ |

**Target**: All ✅ (except TUI recovery which delegates to CLI)
