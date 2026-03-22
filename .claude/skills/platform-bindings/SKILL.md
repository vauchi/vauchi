---
name: platform-bindings
description: UniFFI binding generation, packaging, CI-driven distribution to iOS (SPM) and Android (Maven), and consumer integration. Use when modifying platform bindings or debugging platform build issues.
model: haiku
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi Platform Bindings

## Overview

```
core/vauchi-platform (UniFFI crate)
    ↓ CI builds on tag v*.*.*
    ├── iOS: XCFramework + Swift bindings
    │   ↓ published to GitLab packages
    │   vauchi-platform-swift (SPM distribution)
    │       ↓ triggers
    │       ios/ (consumer app, auto-MR)
    │
    └── Android: JNI .so + Kotlin bindings
        ↓ published to GitLab packages
        vauchi-platform-kotlin (Maven distribution)
            ↓ triggers
            android/ (consumer app, auto-MR)
```

**Distribution repos are NOT manually edited.** CI generates and pushes everything.

## vauchi-platform Crate

**Location**: `core/vauchi-platform/`

```toml
[lib]
crate-type = ["cdylib", "staticlib", "lib"]
name = "vauchi_platform"

[[bin]]
name = "uniffi-bindgen"
path = "uniffi-bindgen.rs"  # Calls uniffi::uniffi_bindgen_main()
```

**Key constraint**: Forces `network-rustls` (no OpenSSL for cross-compilation).

### Source Structure

```
src/
├── lib.rs        # uniffi::setup_scaffolding!(), exported functions + VauchiPlatform object
├── types.rs      # Mobile* wrapper types with From/Into conversions
├── error.rs      # MobileError (uniffi::Error)
├── protocol.rs   # Re-exports from vauchi-core
├── sync.rs       # Sync API
├── content.rs    # Content updates API
└── audio.rs      # Proximity verification API
```

### Wrapper Pattern

```rust
#[derive(Debug, Clone, uniffi::Record)]
pub struct MobileContactField {
    pub id: String,
    pub field_type: MobileFieldType,
    pub label: String,
    pub value: String,
}

impl From<&ContactField> for MobileContactField { /* ... */ }
impl From<MobileContactField> for FieldType { /* reverse */ }

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum MobileError {
    #[error("Library not initialized")]
    NotInitialized,
    // From impls for core errors
}
```

## Build Process

**Script**: `core/scripts/build-bindings.sh`

### iOS Targets

```bash
# 3 targets
aarch64-apple-ios          # Device ARM64
aarch64-apple-ios-sim      # Simulator ARM64 (Apple Silicon)
x86_64-apple-ios           # Simulator Intel

# Build each
cargo build -p vauchi-platform --target aarch64-apple-ios --release
# ... repeat for each

# Generate Swift bindings from device library
cargo run -p vauchi-platform --bin uniffi-bindgen -- generate \
  --library target/aarch64-apple-ios/release/libvauchi_platform.a \
  --language swift --out-dir target/bindings/ios/generated

# Create universal simulator library
lipo -create sim-arm64.a sim-x86_64.a -output libvauchi_platform_sim.a
```

Output: `vauchi_platform.swift` + `vauchi_platformFFI.h`

### Android Targets

```bash
# 2 targets (armv7 optional)
aarch64-linux-android      # ARM64 devices
x86_64-linux-android       # x86_64 emulator

# NDK toolchain setup: CC_*, AR_*, CARGO_TARGET_*_LINKER env vars
# Build each
cargo build -p vauchi-platform --target aarch64-linux-android --release

# CRITICAL: Build native lib WITHOUT stripping for metadata
RUSTFLAGS="-Cstrip=none" cargo build -p vauchi-platform --release

# Generate Kotlin bindings
cargo run -p vauchi-platform --bin uniffi-bindgen --release -- generate \
  --library target/release/libvauchi_platform.so \
  --language kotlin --out-dir target/bindings/android/kotlin
```

**PITFALL**: Symbol stripping removes UniFFI metadata. Always build with `-Cstrip=none` before generating Kotlin bindings.

Output: `uniffi/vauchi_platform/vauchi_platform.kt`

## Packaging

### iOS: `package-xcframework.sh`

```bash
xcodebuild -create-xcframework \
  -framework device/VauchiPlatformFFI.framework \
  -framework simulator/VauchiPlatformFFI.framework \
  -output VauchiPlatformFFI.xcframework
```

Produces:
- `VauchiPlatformFFI.xcframework.zip` (binary for SPM)
- `VauchiPlatform-{version}.zip` (framework + Swift bindings)
- SHA256 checksums

### Android: `package-android.sh`

Produces:
- `vauchi-platform-kotlin-{version}.zip` containing:
  - `jniLibs/arm64-v8a/libvauchi_platform.so`
  - `jniLibs/x86_64/libvauchi_platform.so`
  - `kotlin/uniffi/vauchi_platform/vauchi_platform.kt`

## CI Release Flow (core/.gitlab-ci.yml)

On tag `v*.*.*`:

1. **release:verify** — confirm tag is on main
2. **build:ios** (macOS runner) + **build:android** (Linux+NDK) + **build:validate-bindings**
3. **package:xcframework** + **package:android**
4. **publish:packages** → GitLab Generic Packages registry
5. **trigger:swift** + **trigger:android** → triggers distribution repos via native `trigger:` keyword

### Binding Validation

`validate-bindings.sh` checks:
- Swift bindings: min 3500 lines
- Kotlin bindings: min 5000 lines
- Grep for 47 expected types (MobileContact, MobileError, etc.)

## Distribution Repos

### vauchi-platform-swift

**Package.swift**:
```swift
let version = "0.1.4"
let checksum = "319802bc..."

// Binary target from GitLab packages
.binaryTarget(
    name: "VauchiPlatformFFI",
    url: "https://gitlab.com/api/v4/projects/vauchi%2Fcore/packages/generic/vauchi-platform/{version}/VauchiPlatformFFI.xcframework.zip",
    checksum: checksum
)
```

**CI `update:version` job** (triggered by core):
1. Downloads checksum from core packages
2. Downloads Swift bindings from `VauchiPlatform-{VERSION}.zip`
3. Updates `Package.swift` (version + checksum)
4. Updates `Sources/VauchiPlatform/vauchi_platform.swift`
5. Commits, tags, force-pushes to main
6. Triggers `vauchi/ios` → auto-MR with auto-merge

### vauchi-platform-kotlin

**build.gradle.kts**:
```kotlin
android { namespace = "app.vauchi.platform"; compileSdk = 34; minSdk = 26 }
dependencies {
    implementation("net.java.dev.jna:jna:5.14.0@aar")  // UniFFI runtime
}
publishing {
    // Publishes to GitLab Maven registry
    groupId = "app.vauchi"; artifactId = "vauchi-platform"
}
```

**CI `update:bindings` job** (triggered by core):
1. Downloads Android bindings zip from core packages
2. Extracts JNI libs + Kotlin bindings
3. Builds + publishes AAR to Maven
4. Commits, tags
5. Triggers `vauchi/android` → MR to bump dependency

## Consumer Integration

### iOS App

```swift
// Package.swift or Xcode SPM
.package(url: "https://gitlab.com/vauchi/vauchi-platform-swift.git", from: "0.1.0")

// Usage
import VauchiPlatform
let vauchi = try VauchiPlatform(storagePath: "...")
```

Version pinned in `Package.resolved` with commit SHA + checksum.

### Android App

```kotlin
// settings.gradle.kts — GitLab Maven registry
maven { url = uri("https://gitlab.com/api/v4/projects/77955319/packages/maven") }

// app/build.gradle.kts
implementation("app.vauchi:vauchi-platform:0.1.2")

// Usage
import uniffi.vauchi_platform.VauchiPlatform
val vauchi = VauchiPlatform(storagePath = filesDir.resolve("vauchi.db").absolutePath)
```

## Local Development

Always use `just` recipes for local development. The raw `cargo build` commands in sections above document what CI does internally.

```bash
just bindings           # Generate UniFFI bindings locally
just build-ios debug    # Build iOS framework (macOS only)
just build-android debug # Build Android native libs
just check-ios          # Full iOS check (lint + build + test)
just check-android      # Full Android check
just check-mobile       # Both
```

## Gotchas

1. **Never strip symbols** before Kotlin binding generation (`RUSTFLAGS="-Cstrip=none"`)
2. **vauchi-platform-swift/android are auto-generated** — don't edit manually
3. **rustls required** — adding OpenSSL deps breaks Android/iOS builds
4. **XCFramework needs macOS** — iOS packaging can't run on Linux
5. **Native `trigger:` keyword** used to pass UPSTREAM_VERSION (CI_JOB_TOKEN lacks `api` scope for Pipeline API)
6. **Version mismatch** — if tag != Cargo.toml version, CI auto-creates MR to sync
