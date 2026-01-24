# Problem: CI Pipeline with Binary Releases and UniFFI Bindings

**Status:** ready-for-implementation
**Created:** 2026-01-24
**Owner:** megloff1

## Problem Statement

How do we set up GitLab pipelines, versioning, binary releases, and UniFFI binding autogeneration so that:
- Downstream projects (iOS, Android, CLI, TUI, Desktop) can test against pre-built binaries
- Pipelines pass on releases or dev versions depending on needs
- Native bindings are automatically generated and distributed

## Current State

```
vauchi/core (vauchi-core + vauchi-mobile)
    ↓ git dependency (source)
vauchi/ios, vauchi/android, vauchi/cli, vauchi/tui, vauchi/desktop
```

**Problems:**
1. iOS/Android CI fails because UniFFI bindings must be built from source
2. Building from source requires Rust toolchain on all platforms
3. No versioned binary releases exist
4. No automated binding generation in CI

## Requirements

### Must Have
- [ ] Versioned releases of vauchi-core
- [ ] Pre-built UniFFI bindings (XCFramework for iOS, AAR for Android)
- [ ] CI pipelines that can use either source or binaries
- [ ] Automated binding generation on release

### Should Have
- [ ] Dev/nightly builds for testing unreleased changes
- [ ] Semantic versioning with git tags
- [ ] Release artifacts published to GitLab Package Registry

### Nice to Have
- [ ] Dependency version matrix testing
- [ ] Automatic dependency updates via Renovate/Dependabot

## Key Questions

1. **Versioning strategy**: SemVer? CalVer? How do we version vauchi-core vs vauchi-mobile?
2. **Release triggers**: Manual? Tag-based? Branch-based?
3. **Artifact storage**: GitLab Package Registry? Generic packages? Release assets?
4. **Binding distribution**: How do iOS/Android consume the bindings? CocoaPods? SPM? Maven?
5. **Dev workflow**: How do developers test local changes before release?

## Constraints

- Must work with GitLab CI (not GitHub Actions)
- Self-hosted runners available (Linux, macOS, DinD)
- iOS requires XCFramework, Android requires AAR/JNI libs
- Rust cross-compilation needed for mobile targets

## Related

- vauchi/core - Source of truth for crypto and bindings
- vauchi/ios - Consumes XCFramework
- vauchi/android - Consumes AAR
- `_infra/runners/` - CI runner configuration
