<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Local vs Remote UniFFI Bindings

When developing new Rust types in `vauchi-mobile`, the published SPM/Maven
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
vauchi-mobile-swift (SPM, GitLab) ──→ ios/Vauchi.xcodeproj
vauchi-mobile-android (Maven, GitLab) ──→ android/build.gradle.kts
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
                    │       local vauchi-mobile-swift with local XCFramework
                    │
                    └─ Android: build.gradle.kts uses -PlocalBindings flag
                                to swap Maven dep for local JNA + jniLibs,
                                and adds src/local-bindings/kotlin/ to source set
```

## Platform Details

### iOS

`just bindings-local` performs these steps:

1. Copies `vauchi_mobile.swift` → `vauchi-mobile-swift/Sources/VauchiMobile/`
2. Copies static libs + headers → `VauchiMobileFFI.xcframework/` slices
3. Fixes modulemap (UniFFI generates lowercase, framework needs `VauchiMobileFFI`)
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

## Known Issues

- **modulemap mismatch**: UniFFI generates `module vauchi_mobileFFI` but the
  framework expects `framework module VauchiMobileFFI`. The local wiring script
  fixes this. A proper fix should go into `build-bindings.sh`.
- **XCFramework slices**: `just bindings` only builds device + simulator libs.
  The local XCFramework must have matching slices in its `Info.plist`.
