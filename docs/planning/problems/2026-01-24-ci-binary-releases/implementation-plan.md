# Implementation Plan: CI Binary Releases

**Decisions Made:**
- Distribution: Separate repos (`vauchi-mobile-swift`, `vauchi-mobile-android`)
- Dev builds: Manual trigger only

## Architecture

```
vauchi/core (source)
    │
    │ [Release Pipeline]
    ▼
┌───────────────────────────────────────┐
│  Build Bindings (tag-triggered)       │
│  - iOS: XCFramework + Swift           │
│  - Android: JNI libs + Kotlin         │
└───────────────────────────────────────┘
    │
    ├──────────────────────────────────────┐
    ▼                                      ▼
vauchi/vauchi-mobile-swift          vauchi/vauchi-mobile-android
(Swift Package)                      (Maven/Gradle)
    │                                      │
    ▼                                      ▼
vauchi/ios                           vauchi/android
```

## Implementation Phases

### Phase 1: Core Release Pipeline

**Tasks:**
1. Add version management to `core/Cargo.toml`
2. Create `scripts/package-xcframework.sh`
3. Create `scripts/package-android.sh`
4. Update `core/.gitlab-ci.yml` with release jobs
5. Set up GitLab Generic Packages for artifacts

**CI Jobs:**
```yaml
# Triggered on tags matching v*
build:bindings:ios     # macOS runner
build:bindings:android # Linux runner
package:xcframework    # Create XCFramework zip
package:android        # Create JNI bundle
publish:artifacts      # Upload to Generic Packages
```

### Phase 2: Swift Package Repository

**Create `vauchi/vauchi-mobile-swift`:**
```
vauchi-mobile-swift/
├── Package.swift           # Binary target pointing to core artifacts
├── Sources/
│   └── VauchiMobile/
│       └── Exports.swift   # Re-export generated bindings
└── .gitlab-ci.yml          # Validate package builds
```

**Package.swift:**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VauchiMobile",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "VauchiMobile", targets: ["VauchiMobile", "VauchiMobileFFI"])
    ],
    targets: [
        .target(
            name: "VauchiMobile",
            dependencies: ["VauchiMobileFFI"],
            path: "Sources/VauchiMobile"
        ),
        .binaryTarget(
            name: "VauchiMobileFFI",
            url: "https://gitlab.com/api/v4/projects/vauchi%2Fcore/packages/generic/vauchi-mobile/VERSION/VauchiMobileFFI.xcframework.zip",
            checksum: "CHECKSUM"
        )
    ]
)
```

**Automation:**
- Core release triggers update to Package.swift
- Bump version, update URL and checksum
- Tag and push

### Phase 3: Android Maven Repository

**Create `vauchi/vauchi-mobile-android`:**
```
vauchi-mobile-android/
├── vauchi-mobile/
│   ├── build.gradle.kts
│   ├── src/main/
│   │   ├── kotlin/com/vauchi/mobile/
│   │   │   └── VauchiMobile.kt  # Generated bindings
│   │   └── jniLibs/
│   │       ├── arm64-v8a/libvauchi_mobile.so
│   │       └── armeabi-v7a/libvauchi_mobile.so
│   └── AndroidManifest.xml
├── build.gradle.kts
├── settings.gradle.kts
└── .gitlab-ci.yml
```

**Publish to GitLab Maven:**
```kotlin
publishing {
    publications {
        create<MavenPublication>("release") {
            groupId = "com.vauchi"
            artifactId = "vauchi-mobile"
            version = "0.1.0"
            from(components["release"])
        }
    }
    repositories {
        maven {
            url = uri("${System.getenv("CI_API_V4_URL")}/projects/${System.getenv("CI_PROJECT_ID")}/packages/maven")
            credentials(HttpHeaderCredentials::class) {
                name = "Job-Token"
                value = System.getenv("CI_JOB_TOKEN")
            }
            authentication {
                create<HttpHeaderAuthentication>("header")
            }
        }
    }
}
```

### Phase 4: Downstream Integration

**Update `vauchi/ios`:**
```swift
// Package.swift
dependencies: [
    .package(url: "https://gitlab.com/vauchi/vauchi-mobile-swift.git", from: "0.1.0")
]
```

**Update `vauchi/android`:**
```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        maven {
            url = uri("https://gitlab.com/api/v4/projects/vauchi%2Fvauchi-mobile-android/packages/maven")
        }
    }
}

// app/build.gradle.kts
dependencies {
    implementation("com.vauchi:vauchi-mobile:0.1.0")
}
```

### Phase 5: Manual Dev Build Trigger

**Add to `core/.gitlab-ci.yml`:**
```yaml
build:dev:
  stage: build
  rules:
    - if: $CI_PIPELINE_SOURCE == "web"  # Manual trigger
      when: manual
    - if: $CI_COMMIT_TAG =~ /^v.*-dev/   # Dev tags
  variables:
    DEV_VERSION: "${CI_COMMIT_SHORT_SHA}"
  script:
    - ./scripts/build-bindings.sh
    - ./scripts/publish-dev.sh $DEV_VERSION
```

## File Changes Summary

### New Files

| Repo | File | Purpose |
|------|------|---------|
| core | `scripts/package-xcframework.sh` | Create XCFramework from built libs |
| core | `scripts/package-android.sh` | Bundle Android JNI libs |
| core | `scripts/publish-packages.sh` | Upload to GitLab Packages |
| core | `scripts/trigger-downstream.sh` | Trigger distribution repos |
| vauchi-mobile-swift | `Package.swift` | Swift package definition |
| vauchi-mobile-swift | `.gitlab-ci.yml` | Validate and tag releases |
| vauchi-mobile-android | `build.gradle.kts` | Android library build |
| vauchi-mobile-android | `.gitlab-ci.yml` | Build and publish to Maven |

### Modified Files

| Repo | File | Changes |
|------|------|---------|
| core | `Cargo.toml` | Add workspace version |
| core | `.gitlab-ci.yml` | Add release pipeline stages |
| ios | `Package.swift` | Add VauchiMobile dependency |
| ios | `.gitlab-ci.yml` | Remove allow_failure, add version var |
| android | `build.gradle.kts` | Add Maven dependency |
| android | `.gitlab-ci.yml` | Remove allow_failure |

## Release Process

1. **Prepare release:**
   ```bash
   # Update version in Cargo.toml
   # Update CHANGELOG.md
   git commit -m "chore: prepare release v0.1.0"
   ```

2. **Create tag:**
   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

3. **Automated pipeline:**
   - Tests run
   - iOS bindings built (macOS runner)
   - Android bindings built (Linux runner)
   - XCFramework packaged
   - Android libs bundled
   - Artifacts uploaded to GitLab Packages
   - Distribution repos triggered

4. **Distribution repos auto-update:**
   - vauchi-mobile-swift: Update Package.swift, tag
   - vauchi-mobile-android: Publish to Maven, tag

5. **Downstream apps:**
   - Update dependency version
   - CI passes with new bindings

## Testing Strategy

| Test | When | Runner |
|------|------|--------|
| Rust unit tests | Every commit | Linux |
| Binding generation | Tags only | Linux + macOS |
| XCFramework build | Tags only | macOS |
| Android AAR build | Tags only | Linux |
| iOS app integration | After release | macOS |
| Android app integration | After release | Linux |

## Rollback Plan

If a release has issues:
1. Yank the broken version from packages
2. Distribution repos revert to previous tag
3. Fix issue in core
4. Release patch version (v0.1.1)
