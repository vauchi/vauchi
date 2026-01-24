# Investigation: CI Pipeline with Binary Releases

## Current Architecture

```
vauchi/core/
├── vauchi-core/       # Core crypto library (Rust)
└── vauchi-mobile/     # UniFFI bindings (cdylib + staticlib)
    └── uniffi-bindgen # Generates Swift/Kotlin from Rust

Build outputs:
├── iOS:    libvauchi_mobile.a + vauchi_mobile.swift
└── Android: libvauchi_mobile.so + vauchi_mobile.kt
```

**Build scripts exist and work:**
- `scripts/build-bindings.sh` - Universal entry point
- `scripts/build-android.sh` - Android NDK cross-compilation
- `scripts/validate-bindings.sh` - Validates generated bindings

**Current CI gaps:**
- Only runs Rust checks (fmt, clippy, test)
- Does NOT build mobile bindings
- No release artifacts
- No versioning

## Proposed Solution: Multi-Stage Release Pipeline

### 1. Versioning Strategy

**Use SemVer with git tags:**
```
v0.1.0        # First stable release
v0.1.1        # Patch (bug fixes)
v0.2.0        # Minor (new features, backward compatible)
v1.0.0        # Major (breaking changes)
v0.2.0-dev.1  # Dev/nightly builds
```

**Single version for workspace** - vauchi-core and vauchi-mobile share version.

### 2. Release Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                      RELEASE PIPELINE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Tag Push (v*)                                                  │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────┐     ┌─────────┐     ┌─────────┐                   │
│  │  Test   │────▶│  Build  │────▶│ Publish │                   │
│  │  (all)  │     │ Bindings│     │ Release │                   │
│  └─────────┘     └─────────┘     └─────────┘                   │
│       │               │               │                         │
│       │               ▼               ▼                         │
│       │         ┌───────────┐   ┌───────────┐                  │
│       │         │ iOS Build │   │  GitLab   │                  │
│       │         │ (macOS)   │   │  Release  │                  │
│       │         └───────────┘   │  Assets   │                  │
│       │               │         └───────────┘                  │
│       │               ▼               │                         │
│       │         ┌───────────┐         │                         │
│       │         │ Android   │         │                         │
│       │         │ (Linux)   │         │                         │
│       │         └───────────┘         │                         │
│       │               │               │                         │
│       │               ▼               ▼                         │
│       │         ┌─────────────────────────┐                    │
│       │         │     Package Registry    │                    │
│       │         │  - XCFramework (iOS)    │                    │
│       │         │  - AAR (Android)        │                    │
│       │         │  - Source tarball       │                    │
│       │         └─────────────────────────┘                    │
│       │                                                         │
└───────┼─────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DOWNSTREAM TRIGGERS                          │
├─────────────────────────────────────────────────────────────────┤
│  vauchi/ios      - Triggered on new release                     │
│  vauchi/android  - Triggered on new release                     │
│  vauchi/cli      - Triggered on new release                     │
└─────────────────────────────────────────────────────────────────┘
```

### 3. Artifact Distribution

**Option A: GitLab Generic Packages (Recommended)**
```yaml
# Upload artifacts
curl --header "PRIVATE-TOKEN: $TOKEN" \
     --upload-file VauchiMobile.xcframework.zip \
     "https://gitlab.com/api/v4/projects/$PROJECT_ID/packages/generic/vauchi-mobile/v0.1.0/VauchiMobile.xcframework.zip"
```

Consumers download via:
```yaml
# iOS Package.swift
.binaryTarget(
    name: "VauchiMobile",
    url: "https://gitlab.com/api/v4/projects/vauchi%2Fcore/packages/generic/vauchi-mobile/0.1.0/VauchiMobile.xcframework.zip",
    checksum: "sha256..."
)
```

**Option B: GitLab Release Assets**
- Attached to release page
- Good for manual downloads
- Less suitable for package managers

### 4. iOS Distribution: XCFramework

```bash
# Build universal XCFramework
xcodebuild -create-xcframework \
    -library libvauchi_mobile_device.a -headers include/ \
    -library libvauchi_mobile_sim.a -headers include/ \
    -output VauchiMobile.xcframework

# Package with Swift bindings
zip -r VauchiMobile.xcframework.zip \
    VauchiMobile.xcframework \
    vauchi_mobile.swift
```

**Consumption in iOS app:**
```swift
// Package.swift
dependencies: [
    .package(url: "https://gitlab.com/vauchi/vauchi-mobile-swift", from: "0.1.0")
]

// Or binary target
.binaryTarget(name: "VauchiMobile", url: "...", checksum: "...")
```

### 5. Android Distribution: Maven/AAR

```groovy
// build.gradle.kts
repositories {
    maven {
        url = uri("https://gitlab.com/api/v4/projects/vauchi%2Fcore/packages/maven")
        credentials(HttpHeaderCredentials::class) {
            name = "Private-Token"
            value = findProperty("gitLabPrivateToken") as String?
        }
        authentication {
            create<HttpHeaderAuthentication>("header")
        }
    }
}

dependencies {
    implementation("com.vauchi:vauchi-mobile:0.1.0")
}
```

### 6. Dev Workflow: Local Overrides

**For local development (no release needed):**

```toml
# .cargo/config.toml (already exists)
[patch."https://gitlab.com/vauchi/core.git"]
vauchi-core = { path = "../core/vauchi-core" }
```

**iOS local development:**
```swift
// Package.swift - switch between local and remote
#if LOCAL_DEV
.package(path: "../core")
#else
.package(url: "https://gitlab.com/vauchi/vauchi-mobile-swift", from: "0.1.0")
#endif
```

### 7. CI Pipeline Stages

```yaml
# vauchi/core/.gitlab-ci.yml

stages:
  - test
  - build
  - package
  - publish
  - trigger

# ===== TEST STAGE =====
test:rust:
  stage: test
  tags: [linux, rust]
  script:
    - cargo fmt --check
    - cargo clippy -- -D warnings
    - cargo test --workspace

# ===== BUILD STAGE =====
build:ios:
  stage: build
  tags: [macos, xcode]
  rules:
    - if: $CI_COMMIT_TAG =~ /^v/
  script:
    - ./scripts/build-bindings.sh --ios
    - ./scripts/validate-bindings.sh
  artifacts:
    paths:
      - ios/Vauchi/Generated/
      - ios/Vauchi/Libs/

build:android:
  stage: build
  tags: [linux, rust]
  rules:
    - if: $CI_COMMIT_TAG =~ /^v/
  script:
    - ./scripts/build-bindings.sh --android
    - ./scripts/validate-bindings.sh
  artifacts:
    paths:
      - android/app/src/main/jniLibs/
      - android/app/src/main/kotlin/

# ===== PACKAGE STAGE =====
package:xcframework:
  stage: package
  tags: [macos]
  needs: [build:ios]
  rules:
    - if: $CI_COMMIT_TAG =~ /^v/
  script:
    - ./scripts/package-xcframework.sh
  artifacts:
    paths:
      - dist/VauchiMobile.xcframework.zip

package:aar:
  stage: package
  tags: [linux]
  needs: [build:android]
  rules:
    - if: $CI_COMMIT_TAG =~ /^v/
  script:
    - ./scripts/package-aar.sh
  artifacts:
    paths:
      - dist/vauchi-mobile.aar

# ===== PUBLISH STAGE =====
publish:packages:
  stage: publish
  rules:
    - if: $CI_COMMIT_TAG =~ /^v/
  script:
    - ./scripts/publish-packages.sh $CI_COMMIT_TAG

release:create:
  stage: publish
  rules:
    - if: $CI_COMMIT_TAG =~ /^v/
  script:
    - |
      release-cli create --name "Release $CI_COMMIT_TAG" \
        --tag-name $CI_COMMIT_TAG \
        --assets-link "{\"name\":\"XCFramework\",\"url\":\"$PACKAGE_URL/VauchiMobile.xcframework.zip\"}" \
        --assets-link "{\"name\":\"AAR\",\"url\":\"$PACKAGE_URL/vauchi-mobile.aar\"}"

# ===== TRIGGER DOWNSTREAM =====
trigger:ios:
  stage: trigger
  rules:
    - if: $CI_COMMIT_TAG =~ /^v/
  trigger:
    project: vauchi/ios
    strategy: depend

trigger:android:
  stage: trigger
  rules:
    - if: $CI_COMMIT_TAG =~ /^v/
  trigger:
    project: vauchi/android
    strategy: depend
```

### 8. Downstream Pipeline (iOS Example)

```yaml
# vauchi/ios/.gitlab-ci.yml

variables:
  VAUCHI_VERSION: "0.1.0"  # Or from trigger

.download-bindings:
  before_script:
    - |
      curl -L -o VauchiMobile.xcframework.zip \
        "${CI_API_V4_URL}/projects/vauchi%2Fcore/packages/generic/vauchi-mobile/${VAUCHI_VERSION}/VauchiMobile.xcframework.zip"
      unzip VauchiMobile.xcframework.zip -d Vauchi/Frameworks/

build:debug:
  extends: [.macos-only, .download-bindings]
  script:
    - xcodebuild -scheme Vauchi build
```

### 9. Version Matrix Testing

For testing multiple vauchi-core versions:

```yaml
test:matrix:
  parallel:
    matrix:
      - VAUCHI_VERSION: ["0.1.0", "0.2.0", "latest"]
  script:
    - ./download-bindings.sh $VAUCHI_VERSION
    - xcodebuild test
```

## Recommended Implementation Order

1. **Phase 1: Basic Release Pipeline**
   - Add version to Cargo.toml
   - Create tag-triggered build jobs
   - Upload to GitLab Generic Packages

2. **Phase 2: iOS Integration**
   - Create XCFramework packaging script
   - Update iOS to download from packages
   - Remove `allow_failure` from iOS CI

3. **Phase 3: Android Integration**
   - Create AAR packaging script
   - Set up Maven repository
   - Update Android to use Maven dependency

4. **Phase 4: Automation**
   - Downstream triggers
   - Version matrix testing
   - Automated dependency updates

## Open Questions

1. Should we create separate repos for distribution packages?
   - `vauchi/vauchi-mobile-swift` (Swift Package)
   - `vauchi/vauchi-mobile-android` (Maven artifact)

2. How to handle breaking changes in bindings?
   - Semantic versioning should suffice
   - Major version = breaking API changes

3. Dev builds frequency?
   - On every main merge?
   - Nightly?
   - Manual trigger?
