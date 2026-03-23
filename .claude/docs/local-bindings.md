<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Local vs Remote UniFFI Bindings

When developing new Rust types in `vauchi-platform`, the published SPM/Maven
packages don't include them yet. Use local bindings to test on-device before
publishing.

## Quick Reference

```bash
just bindings-local    # Build bindings + wire into iOS & Android
just bindings-remote   # Revert to published packages
```

## How It Works

### Normal (remote) flow

```
vauchi-platform-swift (SPM, GitLab) ──→ ios/Vauchi.xcodeproj
Group Maven registry (AAR, published from core) ──→ android/build.gradle.kts
```

Both packages are published by CI on `core` tags. Platform apps consume them
as external dependencies.

### Local dev flow

```
core/ ──build-bindings.sh──→ ios/Vauchi/Generated/ + Libs/
                           └→ android/app/src/main/jniLibs/
                           └→ android/app/src/local-bindings/kotlin/
                                    │
         wire-bindings-local.sh ────┘
                    │
                    ├─ iOS: creates Vauchi.xcworkspace pointing to
                    │       local vauchi-platform-swift with local XCFramework
                    │
                    └─ Android: build.gradle.kts uses -PlocalBindings flag
                                to swap Maven dep for local JNA + jniLibs,
                                and adds src/local-bindings/kotlin/ to source set
```

## Platform Details

### iOS

`just bindings-local` performs these steps:

1. Copies `vauchi_platform.swift` → `vauchi-platform-swift/Sources/VauchiPlatform/`
2. Copies static libs + headers → `VauchiPlatformFFI.xcframework/` slices
3. Fixes modulemap (UniFFI generates lowercase, framework needs `VauchiPlatformFFI`)
4. Switches `Package.swift` binaryTarget from URL to local path
5. Creates `ios/Vauchi.xcworkspace` that includes the local SPM package

**Build command changes:**

```bash
# Normal (remote)
xcodebuild -project Vauchi.xcodeproj -scheme Vauchi ...

# Local bindings
xcodebuild -workspace Vauchi.xcworkspace -scheme Vauchi ...
```

The workspace file is gitignored. The `Vauchi.xcodeproj` is not modified.

### Android

`build.gradle.kts` has a `useLocalBindings` flag:

```kotlin
val useLocalBindings = project.hasProperty("localBindings")
    || System.getenv("VAUCHI_LOCAL_BINDINGS") != null
```

When active, it swaps the Maven AAR for a direct JNA dependency (the AAR
bundles JNA, local jniLibs don't).

```bash
# Normal (remote)
./gradlew assembleDebug

# Local bindings
./gradlew assembleDebug -PlocalBindings
```

No file revert needed — the flag controls behavior at build time.

## Reverting

```bash
just bindings-remote
```

This removes the iOS workspace and restores `Package.swift` from git.
Android needs no revert — just omit `-PlocalBindings`.

## Dev vs Release Workflow

### During development

1. Work on core — changes are instantly available to Rust consumers via path overrides
2. For mobile testing: `just bindings-local` wires local bindings into iOS/Android
3. Dev tags (`v0.4.0-dev.0`) only run lint+test+downstream Rust verification — no binding builds
4. Check status: `just core-freshness`

### For releases

1. Bump version in `core/Cargo.toml` (remove `-dev.N` suffix for stable)
2. Merge to main — auto-tags and triggers:
   - **Stable tag**: full binding build+package+publish, triggers mobile repos, creates app bump MRs
   - **RC tag**: same as stable (for pre-release testing)
3. App repos get auto-merge MRs bumping SPM/Maven dependency

## Known Issues

- **modulemap mismatch**: UniFFI generates `module vauchi_platformFFI` but the
  framework expects `framework module VauchiPlatformFFI`. The local wiring script
  fixes this. A proper fix should go into `build-bindings.sh`.
- **XCFramework slices**: `just bindings` only builds device + simulator libs.
  The local XCFramework must have matching slices in its `Info.plist`.
- **xcodegen and local files**: `build-bindings.sh` copies `.a` files to
  `ios/Vauchi/Libs/` and Swift bindings to `ios/Vauchi/Generated/`. Both
  directories are excluded in `project.yml` so xcodegen produces the same
  output locally and on CI. If you add new local-only directories under
  `Vauchi/`, add them to `project.yml`'s `excludes` list or CI's
  `lint:xcodegen` will fail.
