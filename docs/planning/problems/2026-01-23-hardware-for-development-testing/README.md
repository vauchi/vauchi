# Problem: No hardware for real device testing and CI infrastructure

## Status: deferred

**Deferred reason**: Proceeding with simulator/emulator testing and cloud CI. Real device testing will be addressed post-MVP when funding is available.

## Problem Statement

The project cannot complete Phase 1 (Verify) of the roadmap because there are no physical mobile devices for testing and no dedicated CI infrastructure. Currently only desktop/laptop available.

Real device testing is critical because:
- Simulators don't catch hardware-specific issues (camera, audio, Bluetooth)
- QR scanning and audio proximity require physical sensors
- iOS Keychain and Android KeyStore behave differently on real devices
- Performance characteristics differ significantly from simulators

## Origin

- **Source**: Roadmap Phase 1 blockers
- **Date Created**: 2026-01-23

## Impact

- **Severity**: HIGH (MVP blocker)
- Cannot verify cross-platform exchange (iOS ↔ Android)
- Cannot test recovery flows on real devices
- Cannot run CI pipelines for all target platforms
- Release confidence is limited to simulator testing only

## Requirements

### Mobile Test Devices

**Minimum viable coverage (~75%):**
- 1 iOS device (camera, mic, recent iOS)
- 1 Android device (camera, mic, recent Android)

**Recommended coverage (~85-90%):**
- 2 iOS devices (different screen sizes/generations)
- 2 Android devices (Samsung + Pixel or similar diversity)

**Target device matrix:**

| Platform | Segment | Example Devices |
|----------|---------|-----------------|
| iOS | Budget/small | iPhone SE (2nd/3rd gen) |
| iOS | Standard | iPhone 12/13/14 |
| Android | Clean Android | Google Pixel 7/8 |
| Android | Popular OEM | Samsung Galaxy A35/A55 |
| Android | Budget | Xiaomi Redmi Note series |

**Device requirements:**
- Camera (QR scanning)
- Microphone + speaker (audio proximity)
- iOS 15+ / Android 10+
- Ability to install test builds (TestFlight / APK sideload)

### Development & CI Machines

| Machine | Purpose | Requirements |
|---------|---------|--------------|
| macOS | iOS/macOS development, Xcode, CI runner | Apple Silicon, 16GB+ RAM |
| Linux | Rust development, Docker, CI runner | Modern CPU, 16-32GB RAM |
| Windows | Windows builds, CI runner | Modern CPU, 16-32GB RAM |

**Recommended specs:**
- Mac mini M4 (or newer) — required for iOS builds
- 2x Mini PC (Beelink SER8 or similar) — Linux + Windows CI

### Why dedicated CI machines?

- Parallel builds across all 3 platforms
- Consistent build environment
- Can run 24/7 for scheduled jobs
- Frees up development machines

## Investigation Questions

1. Can we acquire hardware through open source funding?
2. What's the fastest path to funding (GitHub Sponsors, Open Collective, crowdfunding)?
3. Should we accelerate open source release to enable funding?
4. Are there device loan/lab programs for open source projects?
5. Can CI be cloud-based initially (GitHub Actions, GitLab CI) while acquiring hardware?

## Possible Solutions

### Solution A: Self-fund hardware acquisition
Acquire devices and machines through personal/project funds.

### Solution B: Open source funding (GitHub Sponsors + Open Collective)
Go fully open source, set up funding infrastructure, attract sponsors.

### Solution C: Crowdfunding campaign
Run a focused campaign (Indiegogo, Kickstarter) for hardware costs.

### Solution D: Hybrid cloud CI + minimal devices
Use cloud CI (GitHub Actions has macOS runners) for builds, acquire only test devices.

### Solution E: Device lab partnerships
Explore partnerships with device testing services or university labs.

## Related

- Roadmap: `docs/planning/roadmap.md` (Phase 1: Verify)
- GitHub Governance: `docs/planning/proposals/2026-01-22-P8-github-governance.md`
- PRINCIPLES: `docs/2026-01-23-PRINCIPLES.md`

## Artifacts

- [ ] Investigation document
- [ ] Funding strategy analysis
- [ ] Device matrix specification
- [ ] CI architecture plan
- [ ] Implementation plan

## Child Problems

(To be populated from investigation)
