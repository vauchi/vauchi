# P9: Mobile Platform Requirements

**Status**: Proposed
**Priority**: HIGH
**Effort**: 1-2 days (configuration + verification)
**Created**: 2026-01-20

## Market Research Summary

### Android Version Distribution (January 2026)

| API Level | Android Version | Cumulative Coverage |
|-----------|-----------------|---------------------|
| 36+ | Android 16 | 4.6% |
| 35+ | Android 15 | 34.4% |
| 34+ | Android 14 | 49.4% |
| 33+ | Android 13 | 64.4% |
| 32+ | Android 12 | 75.3% |
| 30+ | Android 11 | 84.4% |
| 29+ | Android 10 | 89.1% |
| **28+** | **Android 9** | **91.8%** |
| 26+ | Android 8.0 | 94.8% |

**Source**: [apilevels.com](https://apilevels.com/), [AppBrain](https://www.appbrain.com/stats/top-android-sdk-versions)

### iOS Version Distribution (January 2026)

| iOS Version | Cumulative Coverage |
|-------------|---------------------|
| iOS 18+ | 82.8% |
| iOS 17+ | 88.1% |
| **iOS 16+** | **93.1%** |
| iOS 15+ | 95.9% |

**Source**: [iosref.com](https://iosref.com/ios-usage), [TelemetryDeck](https://telemetrydeck.com/survey/apple/iOS/majorSystemVersions/)

---

## Requirements

### REQ-1: Android Minimum SDK

**Target**: API Level 26 (Android 8.0 Oreo)
**Coverage**: 94.8% of active devices

**Rationale**:
- Provides ~95% market coverage (maximizes reach)
- Android 8 introduced notification channels, background limits
- Full Kotlin/Coroutines support
- Acceptable security profile (TLS 1.2 default, keystore available)
- Minor biometric compat code needed for API 26-27 (FingerprintManager fallback)

### REQ-2: iOS Minimum Version

**Target**: iOS 15
**Coverage**: 95.9% of active devices

**Rationale**:
- Provides ~96% market coverage (maximizes reach)
- iOS 15 has native async/await support (back-deployed)
- Full CryptoKit and Keychain capabilities
- SwiftUI NavigationView works (use `.navigationViewStyle(.stack)`)
- Minor navigation API differences from iOS 16+ (NavigationStack)

### REQ-3: Lightweight App Size

**Android APK Target**: < 15 MB (download size)
**iOS IPA Target**: < 20 MB (App Store download)

**Rationale**:
- Privacy-focused users often prefer minimal apps
- Faster downloads on constrained networks
- Lower storage footprint builds trust
- Competitive advantage (baseline React Native apps are ~4 MB)

### REQ-4: Resource Efficiency

| Metric | Target |
|--------|--------|
| Memory (idle) | < 50 MB |
| Memory (active) | < 100 MB |
| Background battery | Negligible (no background services) |
| Cold start time | < 2 seconds |

**Rationale**:
- E2E encrypted app should be efficient, not resource-hungry
- Privacy-conscious users expect minimal system footprint
- No cloud sync means local-only operations should be fast

---

## Implementation Plan

### Phase 1: Configuration (Day 1)

#### Task 1.1: Android Build Configuration ✅ DONE

**File**: `android/app/build.gradle.kts`

```kotlin
android {
    defaultConfig {
        minSdk = 26        // Android 8.0 (94.8% coverage)
        targetSdk = 35     // Android 15 (latest stable)
        ndk {
            abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a"))
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(...)
        }
    }
}
```

#### Task 1.2: iOS Deployment Target ✅ DONE

**File**: `ios/Vauchi.xcodeproj/project.pbxproj`

Set `IPHONEOS_DEPLOYMENT_TARGET = 15.0` for all targets (Debug & Release).

### Phase 2: Size Optimization (Day 1-2)

#### Task 2.1: Android Size Reduction

| Technique | Impact | File |
|-----------|--------|------|
| Enable R8 minification | ~30-50% reduction | `build.gradle.kts` |
| Strip debug symbols | ~10-20% reduction | `build.gradle.kts` |
| Use Android App Bundle (AAB) | ~15% per device | Play Store config |
| Remove unused resources | Variable | `lint.xml` |
| Optimize native libs (UniFFI) | Variable | `build.gradle.kts` |

```kotlin
// build.gradle.kts
android {
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            ndk {
                abiFilters += listOf("arm64-v8a", "armeabi-v7a")
                // Exclude x86/x86_64 for smaller APK (emulator only)
            }
        }
    }

    packaging {
        resources {
            excludes += listOf(
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/*.kotlin_module"
            )
        }
    }
}
```

#### Task 2.2: iOS Size Reduction

| Technique | Impact | Location |
|-----------|--------|----------|
| Enable Bitcode | App Store slicing | Build Settings |
| Asset catalog optimization | Variable | Xcode |
| Strip Swift symbols | ~10-15% reduction | Build Settings |
| Link-time optimization | ~5-10% reduction | Build Settings |

```
// Xcode Build Settings
DEAD_CODE_STRIPPING = YES
STRIP_STYLE = all
SWIFT_OPTIMIZATION_LEVEL = -O (Release)
ENABLE_BITCODE = YES
ASSETCATALOG_COMPILER_OPTIMIZATION = space
```

### Phase 3: UniFFI Library Optimization

#### Task 3.1: Rust Compilation Flags

**File**: `code/.cargo/config.toml`

```toml
[profile.release]
opt-level = "z"          # Optimize for size
lto = true               # Link-time optimization
codegen-units = 1        # Better optimization, slower compile
panic = "abort"          # Smaller binary, no unwinding
strip = true             # Strip symbols

[profile.release.package.vauchi-mobile]
opt-level = "z"
```

#### Task 3.2: Cargo Features

**File**: `code/vauchi-mobile/Cargo.toml`

```toml
[features]
default = []
# Only include necessary features, no dev dependencies
```

### Phase 4: Verification

#### Task 4.1: Size Measurement

```bash
# Android
./gradlew assembleRelease
ls -lh app/build/outputs/apk/release/app-release.apk

# Android App Bundle analysis
bundletool build-apks --bundle=app.aab --output=app.apks
bundletool get-size total --apks=app.apks

# iOS (after archive)
# Check Xcode Organizer → App Size Report
```

#### Task 4.2: Verification Checklist

- [ ] Android APK < 15 MB (release, per-ABI)
- [ ] iOS IPA < 20 MB (App Store download estimate)
- [ ] App launches on Android 9 device/emulator
- [ ] App launches on iOS 16 device/simulator
- [ ] Cold start < 2 seconds on mid-range device
- [ ] Memory stays under limits during normal use

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| UniFFI bloats binary | Aggressive LTO, `opt-level = "z"` |
| Ring crypto lib size | Already optimized; no alternatives per CLAUDE.md |
| Missing APIs on older OS | Test on min SDK; graceful degradation |
| ProGuard breaks reflection | Careful keep rules for UniFFI |

---

## Success Criteria

- [x] `minSdk = 26` configured in Android
- [x] `IPHONEOS_DEPLOYMENT_TARGET = 15.0` in iOS
- [x] Release profile configured with size optimizations
- [x] Build scripts support debug/release modes
- [ ] Release APK < 15 MB
- [ ] Release IPA < 20 MB (estimated)
- [ ] Builds pass on CI
- [ ] Manual test on minimum supported versions
- [ ] Memory profiling shows < 100 MB active usage

---

## References

- [Android API Levels](https://apilevels.com/)
- [iOS Version Usage](https://iosref.com/ios-usage)
- [Android App Size Optimization](https://developer.android.com/build/shrink-code)
- [iOS App Thinning](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)
- [Expo App Size Guide](https://docs.expo.dev/distribution/app-size/)

---

## Appendix: Market Research Sources

| Source | Data Date | URL |
|--------|-----------|-----|
| apilevels.com | Nov 2025 | https://apilevels.com/ |
| iosref.com | Nov 2025 | https://iosref.com/ios-usage |
| TelemetryDeck | Dec 2025 | https://telemetrydeck.com/ |
| AppBrain | Jan 2026 | https://www.appbrain.com/stats/top-android-sdk-versions |
| StatCounter | Jan 2026 | https://gs.statcounter.com/ |
