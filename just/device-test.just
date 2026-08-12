# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Device testing preparation recipes (physical iPhone + Android device)

# ═══════════════════════════════════════════════════════════════════
# DEVICE TESTING (physical device workflow)
# ═══════════════════════════════════════════════════════════════════

[group('tests')]
test-device-test-recipes:
    python3 "{{justfile_directory()}}/tests/test_device_test_recipe.py" \
        "{{justfile_directory()}}/just/device-test.just" \
        "{{justfile_directory()}}/just/device-test-lib.sh"

# Build, package, and install both apps on physical devices
[group('device-test')]
[script]
prepare-device-test core_dir="":
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    CORE_DIR=$(dt_resolve_core_dir "{{core_dir}}")
    printf "%b\n" "${YELLOW}╔════════════════════════════════════════════════╗${NC}"
    printf "%b\n" "${YELLOW}║     Prepare Device Test — Full Pipeline       ║${NC}"
    printf "%b\n" "${YELLOW}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Core directory: $CORE_DIR"
    echo ""

    dt_check_prerequisites

    TOTAL_START=$SECONDS

    echo ""
    printf "%b\n" "${BLUE}[1/6] Building mobile libraries...${NC}"
    just _dt-build-mobile-libs "$CORE_DIR"

    echo ""
    printf "%b\n" "${BLUE}[2/6] Generating UniFFI bindings...${NC}"
    just _dt-generate-bindings "$CORE_DIR"

    echo ""
    printf "%b\n" "${BLUE}[3/6] Packaging iOS bindings...${NC}"
    just _dt-package-ios "$CORE_DIR"

    echo ""
    printf "%b\n" "${BLUE}[4/6] Packaging Android bindings...${NC}"
    just _dt-package-android "$CORE_DIR"

    echo ""
    printf "%b\n" "${BLUE}[5/6] Building apps...${NC}"
    just _dt-build-ios
    just _dt-build-android

    echo ""
    printf "%b\n" "${BLUE}[6/6] Installing apps on devices...${NC}"
    just _dt-install-ios
    just _dt-install-android

    ELAPSED=$((SECONDS - TOTAL_START))
    echo ""
    printf "%b\n" "${GREEN}╔════════════════════════════════════════════════╗${NC}"
    printf "%b\n" "${GREEN}║     Device Test Preparation Complete           ║${NC}"
    printf "%b\n" "${GREEN}║     Total time: ${ELAPSED}s                            ${NC}"
    printf "%b\n" "${GREEN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Both apps installed and ready for testing."

# Rebuild + install iOS only (skip Android)
[group('device-test')]
[script]
rebuild-ios core_dir="":
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    CORE_DIR=$(dt_resolve_core_dir "{{core_dir}}")
    printf "%b\n" "${YELLOW}═══ Rebuild iOS (device) ═══${NC}"
    echo "Core directory: $CORE_DIR"
    echo ""

    dt_check_prerequisites_ios

    just _dt-build-mobile-libs-ios "$CORE_DIR"
    just _dt-generate-bindings-swift "$CORE_DIR"
    just _dt-package-ios "$CORE_DIR"
    just _dt-build-ios
    just _dt-install-ios

    echo ""
    printf "%b\n" "${GREEN}iOS app installed and ready for testing.${NC}"

# Rebuild + install Android only (skip iOS)
[group('device-test')]
[script]
rebuild-android core_dir="":
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    CORE_DIR=$(dt_resolve_core_dir "{{core_dir}}")
    printf "%b\n" "${YELLOW}═══ Rebuild Android (device) ═══${NC}"
    echo "Core directory: $CORE_DIR"
    echo ""

    dt_check_prerequisites_android

    just _dt-build-mobile-libs-android "$CORE_DIR"
    just _dt-generate-bindings-kotlin "$CORE_DIR"
    just _dt-package-android "$CORE_DIR"
    just _dt-build-android
    just _dt-install-android

    echo ""
    printf "%b\n" "${GREEN}Android app installed and ready for testing.${NC}"

# ─── Internal sub-recipes ────────────────────────────────────────

# Build vauchi-platform for iOS device target (aarch64-apple-ios)
[group('device-test')]
[private]
[script]
_dt-build-mobile-libs-ios core_dir:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    cd "{{core_dir}}"
    unset RUSTC_WRAPPER
    export VAUCHI_LOCALES_DIR="{{justfile_directory()}}/locales"
    export IPHONEOS_DEPLOYMENT_TARGET="10.0"

    printf "%b\n" "${YELLOW}Building vauchi-platform for aarch64-apple-ios (device)...${NC}"
    cargo build -p vauchi-platform --target aarch64-apple-ios --release --features dev-logging
    printf "%b\n" "${GREEN}  iOS device library built${NC}"

# Build vauchi-platform for Android device target (aarch64-linux-android)
[group('device-test')]
[private]
[script]
_dt-build-mobile-libs-android core_dir:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    cd "{{core_dir}}"
    unset RUSTC_WRAPPER
    export VAUCHI_LOCALES_DIR="{{justfile_directory()}}/locales"

    dt_setup_android_ndk
    printf "%b\n" "${YELLOW}Building vauchi-platform for aarch64-linux-android (device)...${NC}"
    cargo build -p vauchi-platform --target aarch64-linux-android --release --features dev-logging
    printf "%b\n" "${GREEN}  Android device library built${NC}"

# Build vauchi-platform for both device targets + native (for Kotlin bindgen)
[group('device-test')]
[private]
[script]
_dt-build-mobile-libs core_dir:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    cd "{{core_dir}}"
    unset RUSTC_WRAPPER
    export VAUCHI_LOCALES_DIR="{{justfile_directory()}}/locales"
    export IPHONEOS_DEPLOYMENT_TARGET="10.0"

    # iOS device
    printf "%b\n" "${YELLOW}Building vauchi-platform for aarch64-apple-ios (device)...${NC}"
    cargo build -p vauchi-platform --target aarch64-apple-ios --release --features dev-logging
    printf "%b\n" "${GREEN}  iOS device library built${NC}"

    # Android device
    dt_setup_android_ndk
    printf "%b\n" "${YELLOW}Building vauchi-platform for aarch64-linux-android (device)...${NC}"
    cargo build -p vauchi-platform --target aarch64-linux-android --release --features dev-logging
    printf "%b\n" "${GREEN}  Android device library built${NC}"

    # Native macOS (needed for Kotlin binding generation)
    unset IPHONEOS_DEPLOYMENT_TARGET
    printf "%b\n" "${YELLOW}Building vauchi-platform native (for Kotlin bindgen)...${NC}"
    RUSTFLAGS="-Cstrip=none" cargo build -p vauchi-platform --release
    printf "%b\n" "${GREEN}  Native macOS library built${NC}"

# Generate Swift bindings from iOS .a
[group('device-test')]
[private]
[script]
_dt-generate-bindings-swift core_dir:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    cd "{{core_dir}}"
    unset RUSTC_WRAPPER

    printf "%b\n" "${YELLOW}Generating Swift bindings...${NC}"
    BINDINGS_OUT="target/bindings/ios/generated"
    mkdir -p "$BINDINGS_OUT"
    cargo run -p vauchi-platform --bin uniffi-bindgen -- generate \
        --library target/aarch64-apple-ios/release/libvauchi_platform.a \
        --language swift \
        --out-dir "$BINDINGS_OUT"
    printf "%b\n" "${GREEN}  Swift bindings generated at $BINDINGS_OUT${NC}"

# Generate Kotlin bindings from native macOS .dylib
[group('device-test')]
[private]
[script]
_dt-generate-bindings-kotlin core_dir:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    cd "{{core_dir}}"
    unset RUSTC_WRAPPER

    # Always rebuild the native library — cargo is a no-op when nothing
    # changed, but skipping entirely means a stale dylib can leak removed
    # UniFFI symbols into the Kotlin bindings while the fresh Android .so
    # no longer exports them, causing UnsatisfiedLinkError on app startup.
    printf "%b\n" "${YELLOW}Building native macOS library (for Kotlin bindgen)...${NC}"
    RUSTFLAGS="-Cstrip=none" cargo build -p vauchi-platform --release

    printf "%b\n" "${YELLOW}Generating Kotlin bindings from macOS .dylib...${NC}"
    BINDINGS_OUT="target/bindings/android/kotlin"
    mkdir -p "$BINDINGS_OUT"
    cargo run -p vauchi-platform --bin uniffi-bindgen -- generate \
        --library target/release/libvauchi_platform.dylib \
        --language kotlin \
        --out-dir "$BINDINGS_OUT"
    printf "%b\n" "${GREEN}  Kotlin bindings generated at $BINDINGS_OUT${NC}"

# Generate both Swift and Kotlin bindings
[group('device-test')]
[private]
[script]
_dt-generate-bindings core_dir:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    cd "{{core_dir}}"
    unset RUSTC_WRAPPER

    # Swift bindings from iOS .a
    printf "%b\n" "${YELLOW}Generating Swift bindings...${NC}"
    SWIFT_OUT="target/bindings/ios/generated"
    mkdir -p "$SWIFT_OUT"
    cargo run -p vauchi-platform --bin uniffi-bindgen -- generate \
        --library target/aarch64-apple-ios/release/libvauchi_platform.a \
        --language swift \
        --out-dir "$SWIFT_OUT"
    printf "%b\n" "${GREEN}  Swift bindings generated${NC}"

    # Kotlin bindings from macOS .dylib
    printf "%b\n" "${YELLOW}Generating Kotlin bindings from macOS .dylib...${NC}"
    KOTLIN_OUT="target/bindings/android/kotlin"
    mkdir -p "$KOTLIN_OUT"
    cargo run -p vauchi-platform --bin uniffi-bindgen -- generate \
        --library target/release/libvauchi_platform.dylib \
        --language kotlin \
        --out-dir "$KOTLIN_OUT"
    printf "%b\n" "${GREEN}  Kotlin bindings generated${NC}"

# Package iOS: copy .a, Swift bindings, header, modulemap into xcframework
[group('device-test')]
[private]
[script]
_dt-package-ios core_dir:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    CORE_DIR="{{core_dir}}"
    WORKSPACE_ROOT="$(pwd)"

    BINDINGS_DIR="$CORE_DIR/target/bindings/ios/generated"
    DEVICE_LIB="$CORE_DIR/target/aarch64-apple-ios/release/libvauchi_platform.a"
    # Absolute — the SPM symlink below must resolve from inside
    # vauchi-platform-swift/ (a relative `core/target/...` link dangles).
    XCFW_DIR="$WORKSPACE_ROOT/$CORE_DIR/target/xcframework-build/VauchiPlatformFFI.xcframework"
    SPM_DIR="$WORKSPACE_ROOT/vauchi-platform-swift"

    # Extract version from workspace Cargo.toml
    VERSION=$(grep '^version' "$CORE_DIR/Cargo.toml" | head -1 | sed 's/.*"\(.*\)".*/\1/')
    echo "  Core version: $VERSION"

    # Verify source artifacts exist
    if [[ ! -f "$DEVICE_LIB" ]]; then
        printf "%b\n" "${RED}ERROR: iOS device library not found: $DEVICE_LIB${NC}"
        echo "Run: just _dt-build-mobile-libs-ios $CORE_DIR"
        exit 1
    fi
    if [[ ! -f "$BINDINGS_DIR/vauchi_platform.swift" ]]; then
        printf "%b\n" "${RED}ERROR: Swift bindings not found: $BINDINGS_DIR/vauchi_platform.swift${NC}"
        echo "Run: just _dt-generate-bindings-swift $CORE_DIR"
        exit 1
    fi

    # Layer 2 ABI parity gate: bindings and artifact must agree
    # before packaging. Catches stale-artifact bugs like the
    # 2026-04-20 Android startup crash (cached dylib → bindings
    # referenced a removed UniFFI symbol).
    echo "  Verifying iOS binding/artifact ABI parity..."
    "$WORKSPACE_ROOT/scripts/scripts/check-binding-abi.sh" \
        --platform ios \
        --artifact "$DEVICE_LIB" \
        --bindings "$BINDINGS_DIR/vauchi_platform.swift"

    # Ensure xcframework directory structure exists
    printf "%b\n" "${YELLOW}Packaging iOS xcframework...${NC}"
    DEVICE_FW="$XCFW_DIR/ios-arm64/VauchiPlatformFFI.framework"
    SIM_FW="$XCFW_DIR/ios-arm64_x86_64-simulator/VauchiPlatformFFI.framework"

    # Create xcframework structure if it doesn't exist yet
    if [[ ! -d "$XCFW_DIR" ]]; then
        printf "%b\n" "${YELLOW}  Creating xcframework structure from scratch...${NC}"
        mkdir -p "$DEVICE_FW/Headers" "$DEVICE_FW/Modules"
        mkdir -p "$SIM_FW/Headers" "$SIM_FW/Modules"
    fi

    # Copy device .a as framework binary
    echo "  Copying device .a to xcframework..."
    cp "$DEVICE_LIB" "$DEVICE_FW/VauchiPlatformFFI"

    # Copy header to both slices
    echo "  Copying header to xcframework slices..."
    if [[ -f "$BINDINGS_DIR/vauchi_platformFFI.h" ]]; then
        cp "$BINDINGS_DIR/vauchi_platformFFI.h" "$DEVICE_FW/Headers/vauchi_platformFFI.h"
        cp "$BINDINGS_DIR/vauchi_platformFFI.h" "$SIM_FW/Headers/vauchi_platformFFI.h"
    fi

    # Ensure modulemap says "framework module VauchiPlatformFFI" (not "module vauchi_platformFFI")
    MODULEMAP_CONTENT='framework module VauchiPlatformFFI {
        umbrella header "vauchi_platformFFI.h"
        export *
        module * { export * }
        link "vauchi_platform"
    }'
    echo "$MODULEMAP_CONTENT" > "$DEVICE_FW/Headers/module.modulemap"
    echo "$MODULEMAP_CONTENT" > "$DEVICE_FW/Modules/module.modulemap"
    echo "$MODULEMAP_CONTENT" > "$SIM_FW/Headers/module.modulemap"
    echo "$MODULEMAP_CONTENT" > "$SIM_FW/Modules/module.modulemap"

    # Generate Info.plist for device framework slice (required by SPM)
    echo "  Generating Info.plist for device framework..."
    /usr/libexec/PlistBuddy -c "Clear dict" "$DEVICE_FW/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy \
        -c "Add :CFBundleExecutable string VauchiPlatformFFI" \
        -c "Add :CFBundleIdentifier string app.vauchi.VauchiPlatformFFI" \
        -c "Add :CFBundleName string VauchiPlatformFFI" \
        -c "Add :CFBundlePackageType string FMWK" \
        -c "Add :CFBundleVersion string 1" \
        -c "Add :CFBundleShortVersionString string $VERSION" \
        "$DEVICE_FW/Info.plist"

    # Generate Info.plist for simulator framework slice
    echo "  Generating Info.plist for simulator framework..."
    cp "$DEVICE_FW/Info.plist" "$SIM_FW/Info.plist"

    # Generate root xcframework Info.plist with AvailableLibraries
    echo "  Generating root xcframework Info.plist..."
    XCFW_PLIST="$XCFW_DIR/Info.plist"
    rm -f "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Save" "$XCFW_PLIST" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string XFWK" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :XCFrameworkFormatVersion string 1.0" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries array" "$XCFW_PLIST"
    # Device slice
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:0 dict" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:0:LibraryIdentifier string ios-arm64" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:0:LibraryPath string VauchiPlatformFFI.framework" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:0:SupportedArchitectures array" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:0:SupportedArchitectures:0 string arm64" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:0:SupportedPlatform string ios" "$XCFW_PLIST"
    # Simulator slice
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:1 dict" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:1:LibraryIdentifier string ios-arm64_x86_64-simulator" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:1:LibraryPath string VauchiPlatformFFI.framework" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:1:SupportedArchitectures array" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:1:SupportedArchitectures:0 string arm64" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:1:SupportedArchitectures:1 string x86_64" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:1:SupportedPlatform string ios" "$XCFW_PLIST"
    /usr/libexec/PlistBuddy -c "Add :AvailableLibraries:1:SupportedPlatformVariant string simulator" "$XCFW_PLIST"

    # Copy Swift bindings to SPM package
    echo "  Copying Swift bindings to vauchi-platform-swift..."
    cp "$BINDINGS_DIR/vauchi_platform.swift" "$SPM_DIR/Sources/VauchiPlatform/vauchi_platform.swift"

    # Sync xcframework into SPM package (supports both symlink and real directory)
    SPM_XCFW="$SPM_DIR/VauchiPlatformFFI.xcframework"
    if [[ -L "$SPM_XCFW" ]]; then
        # Already a symlink — recreate if dangling or pointing elsewhere
        # (-e follows the link; dangling links fail the test).
        SYMLINK_TARGET=$(readlink "$SPM_XCFW")
        if [[ ! -e "$SPM_XCFW" ]] || [[ "$SYMLINK_TARGET" != "$XCFW_DIR" ]]; then
            printf "%b\n" "${YELLOW}  Updating SPM symlink...${NC}"
            rm -f "$SPM_XCFW"
            ln -s "$XCFW_DIR" "$SPM_XCFW"
        fi
    elif [[ -d "$SPM_XCFW" ]]; then
        # Real directory — copy artifacts into it
        echo "  Copying xcframework artifacts into SPM package..."
        cp -R "$XCFW_DIR/" "$SPM_XCFW/"
    else
        # Neither — create symlink
        printf "%b\n" "${YELLOW}  Creating SPM symlink to xcframework...${NC}"
        ln -s "$XCFW_DIR" "$SPM_XCFW"
    fi

    printf "%b\n" "${GREEN}  iOS packaging complete${NC}"
    echo "  XCFramework: $XCFW_DIR"
    echo "  SPM package: $SPM_XCFW"
    echo "  Info.plist files: 3 (device + simulator + root)"
    ls -lh "$DEVICE_FW/VauchiPlatformFFI"

# Package Android: copy .so and Kotlin bindings to android repo
[group('device-test')]
[private]
[script]
_dt-package-android core_dir:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    CORE_DIR="{{core_dir}}"
    WORKSPACE_ROOT="$(pwd)"

    ANDROID_SO="$CORE_DIR/target/aarch64-linux-android/release/libvauchi_platform.so"
    KOTLIN_DIR="$CORE_DIR/target/bindings/android/kotlin"
    ANDROID_DIR="$WORKSPACE_ROOT/android"

    if [[ ! -f "$ANDROID_SO" ]]; then
        printf "%b\n" "${RED}ERROR: Android .so not found: $ANDROID_SO${NC}"
        echo "Run: just _dt-build-mobile-libs-android $CORE_DIR"
        exit 1
    fi

    printf "%b\n" "${YELLOW}Packaging Android bindings...${NC}"

    # Copy .so to jniLibs
    echo "  Copying .so to android/app/src/main/jniLibs/arm64-v8a/..."
    mkdir -p "$ANDROID_DIR/app/src/main/jniLibs/arm64-v8a"
    cp "$ANDROID_SO" "$ANDROID_DIR/app/src/main/jniLibs/arm64-v8a/libvauchi_platform.so"

    # Copy Kotlin bindings to local-bindings source set (only compiled with -PlocalBindings)
    if [[ -f "$KOTLIN_DIR/uniffi/vauchi_platform/vauchi_platform.kt" ]]; then
        echo "  Copying Kotlin bindings to android/app/src/local-bindings/kotlin/uniffi/..."
        mkdir -p "$ANDROID_DIR/app/src/local-bindings/kotlin/uniffi/vauchi_platform"
        cp "$KOTLIN_DIR/uniffi/vauchi_platform/vauchi_platform.kt" \
           "$ANDROID_DIR/app/src/local-bindings/kotlin/uniffi/vauchi_platform/vauchi_platform.kt"
        # Remove stale bindings from default source set if present
        rm -f "$ANDROID_DIR/app/src/main/kotlin/uniffi/vauchi_platform/vauchi_platform.kt"
    else
        printf "%b\n" "${RED}ERROR: Kotlin bindings not found: $KOTLIN_DIR/uniffi/vauchi_platform/vauchi_platform.kt${NC}"
        exit 1
    fi

    # Layer 2 ABI parity gate: the freshly-packaged .so must
    # export every UniFFI symbol the freshly-copied Kotlin
    # bindings reference. Pre-install failure point for the
    # 2026-04-20 UnsatisfiedLinkError class of bugs.
    echo "  Verifying Android binding/artifact ABI parity..."
    "$WORKSPACE_ROOT/scripts/scripts/check-binding-abi.sh" \
        --platform android \
        --artifact "$ANDROID_DIR/app/src/main/jniLibs/arm64-v8a/libvauchi_platform.so" \
        --bindings "$ANDROID_DIR/app/src/local-bindings/kotlin/uniffi/vauchi_platform/vauchi_platform.kt"

    printf "%b\n" "${GREEN}  Android packaging complete${NC}"
    ls -lh "$ANDROID_DIR/app/src/main/jniLibs/arm64-v8a/libvauchi_platform.so"

# Build iOS app for physical device
[group('device-test')]
[private]
[script]
_dt-build-ios:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    WORKSPACE_ROOT=$(pwd)
    IOS_DEVICE_ID=$(dt_detect_ios_device)
    printf "%b\n" "${YELLOW}Building iOS app for device $IOS_DEVICE_ID...${NC}"

    security unlock-keychain -p "build" "$HOME/Library/Keychains/build.keychain-db"
    security set-keychain-settings -t 300 \
        "$HOME/Library/Keychains/build.keychain-db"

    dt_set_xcode_auth_args
    dt_provision_ios_local_spm "$WORKSPACE_ROOT"
    trap dt_restore_ios_spm_config EXIT

    cd ios
    # Drop both possible workspace locks so SwiftPM resolves the synthetic
    # local-mirror tag containing the freshly packaged XCFramework.
    rm -f "$DT_IOS_SPM_CACHE_PATH/workspace-state.json"
    rm -f Vauchi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
    rm -f Vauchi.xcworkspace/xcshareddata/swiftpm/Package.resolved
    # Use -workspace (not -project) so SPM picks up the local
    # vauchi-platform-swift override declared in the workspace.
    # Without this env var, the vauchi-platform-swift manifest emits a URL
    # binaryTarget and SPM silently links the PUBLISHED (stale) core —
    # local Rust changes never reach the device (mobile.just:75-79).
    export VAUCHI_PLATFORM_USE_LOCAL_XCFRAMEWORK=1
    DT_XCODEBUILD_ARGS=(
        -workspace Vauchi.xcworkspace
        -scheme Vauchi
        -configuration Debug
        -destination "id=$IOS_DEVICE_ID"
        -derivedDataPath build
        -allowProvisioningUpdates
    )
    if [[ "${#DT_XCODE_AUTH_ARGS[@]}" -gt 0 ]]; then
        DT_XCODEBUILD_ARGS+=("${DT_XCODE_AUTH_ARGS[@]}")
    fi
    DT_XCODEBUILD_ARGS+=(
        -clonedSourcePackagesDirPath "$DT_IOS_SPM_CACHE_PATH"
        clean build
    )
    xcodebuild "${DT_XCODEBUILD_ARGS[@]}" 2>&1 | tail -20

    dt_restore_ios_spm_config
    trap - EXIT
    printf "%b\n" "${GREEN}  iOS build complete${NC}"

# Build Android APK
[group('device-test')]
[private]
[script]
_dt-build-android:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    printf "%b\n" "${YELLOW}Building Android APK (assembleDebug -PlocalBindings)...${NC}"
    cd android
    ./gradlew assembleDebug -PlocalBindings 2>&1 | tail -10
    printf "%b\n" "${GREEN}  Android build complete${NC}"
    ls -lh app/build/outputs/apk/debug/app-debug.apk 2>/dev/null || true

# Install iOS app on connected device
[group('device-test')]
[private]
[script]
_dt-install-ios:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    IOS_DEVICE_ID=$(dt_detect_ios_device)
    printf "%b\n" "${YELLOW}Installing iOS app on device $IOS_DEVICE_ID...${NC}"

    # Find the built .app bundle
    APP_PATH=$(find ios/build -name "Vauchi.app" -path "*/Debug-iphoneos/*" 2>/dev/null | head -1)
    if [[ -z "$APP_PATH" ]]; then
        # Try DerivedData location
        APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Vauchi.app" -path "*/Debug-iphoneos/*" 2>/dev/null | sort -t/ -k8 -r | head -1)
    fi

    if [[ -z "$APP_PATH" ]]; then
        printf "%b\n" "${RED}ERROR: Could not find built Vauchi.app${NC}"
        echo "The xcodebuild step may have failed. Check build output above."
        exit 1
    fi

    echo "  App bundle: $APP_PATH"
    xcrun devicectl device install app --device "$IOS_DEVICE_ID" "$APP_PATH"
    printf "%b\n" "${GREEN}  iOS app installed${NC}"

# Install Android APK on connected device
[group('device-test')]
[private]
[script]
_dt-install-android:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    APK_PATH="android/app/build/outputs/apk/debug/app-debug.apk"
    if [[ ! -f "$APK_PATH" ]]; then
        printf "%b\n" "${RED}ERROR: APK not found: $APK_PATH${NC}"
        echo "Run: just _dt-build-android"
        exit 1
    fi

    printf "%b\n" "${YELLOW}Installing Android APK via adb...${NC}"
    ANDROID_SERIAL=$(dt_detect_android_device)
    echo "  Device: $ANDROID_SERIAL"
    adb -s "$ANDROID_SERIAL" install -r "$APK_PATH"
    printf "%b\n" "${GREEN}  Android app installed${NC}"

# Debug keys carry `setUserAuthenticationRequired(false)`, so every other
# device recipe exercises the one configuration in which an auth-bound
# storage key cannot fail. That blind spot is how a launch crash reached
# a shippable build (`2026-08-12-android-release-build-crashes-on-launch`).

# Smoke-test the release build on a device: it must survive launch
[group('device-test')]
[script]
device-smoke-release:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    PKG="app.vauchi"
    APK_PATH="android/app/build/outputs/apk/release/app-release.apk"

    # Signed with the local debug keystore purely to make the release
    # variant installable. What is under test is the release build
    # *configuration's* runtime behaviour, not distribution signing.
    if [[ -z "${ANDROID_KEYSTORE_PATH:-}" ]]; then
        if [[ ! -f "$HOME/.android/debug.keystore" ]]; then
            printf "%b\n" "${RED}ERROR: no keystore available${NC}"
            echo "Set ANDROID_KEYSTORE_PATH, or run a debug build once to create the default."
            exit 1
        fi
        export ANDROID_KEYSTORE_PATH="$HOME/.android/debug.keystore"
        export ANDROID_KEYSTORE_PASSWORD="android"
        export ANDROID_KEY_ALIAS="androiddebugkey"
        export ANDROID_KEY_PASSWORD="android"
    fi

    printf "%b\n" "${YELLOW}Building Android APK (assembleRelease -PlocalBindings)...${NC}"
    (cd android && ./gradlew assembleRelease -PlocalBindings 2>&1 | tail -10)

    ANDROID_SERIAL=$(dt_detect_android_device)

    # Don't leave a release build on a shared test device: its storage key is
    # minted with `setUserAuthenticationRequired(true)`, so whatever runs next
    # inherits a build that demands device authentication. Uninstall rather
    # than `pm clear` — Keystore entries outlive cleared app data.
    #
    # This is hygiene, not a fix for the ordering fragility in
    # `2026-08-12-instrumented-before-gate-fails-on-a-busy-device`: that one
    # reproduces with the uninstall in place.
    remove_release_build() {
        printf "%b\n" "${YELLOW}Removing the release build...${NC}"
        adb -s "$ANDROID_SERIAL" uninstall "$PKG" || true
    }
    trap remove_release_build EXIT

    printf "%b\n" "${YELLOW}Installing release APK on $ANDROID_SERIAL...${NC}"
    adb -s "$ANDROID_SERIAL" install -r "$APK_PATH"

    adb -s "$ANDROID_SERIAL" shell am force-stop "$PKG"
    adb -s "$ANDROID_SERIAL" logcat -c
    adb -s "$ANDROID_SERIAL" shell am start -n "$PKG/.MainActivity" >/dev/null

    # Asserts only that the process survives its own launch. It deliberately
    # does not unlock the device or drive the auth prompt: the prompt *is*
    # the expected first screen here, and driving it would mean polling a
    # system-owned modal (CC-23).
    PID=""
    attempt=0
    while [[ $attempt -lt 20 ]]; do
        PID=$(adb -s "$ANDROID_SERIAL" shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
        if [[ -n "$PID" ]]; then break; fi
        attempt=$((attempt + 1))
        sleep 1
    done

    # Started is not survived — the crash landed after first frame.
    sleep 5
    PID=$(adb -s "$ANDROID_SERIAL" shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)

    if adb -s "$ANDROID_SERIAL" logcat -d | grep -q "FATAL EXCEPTION"; then
        printf "%b\n" "${RED}FAIL: the release build crashed on launch${NC}"
        adb -s "$ANDROID_SERIAL" logcat -d | grep -A 15 "FATAL EXCEPTION" | head -25
        echo "Retrace with: android/app/build/outputs/mapping/release/mapping.txt"
        exit 1
    fi

    if [[ -z "$PID" ]]; then
        printf "%b\n" "${RED}FAIL: $PKG is not running after launch${NC}"
        exit 1
    fi

    printf "%b\n" "${GREEN}  Release build survived launch (pid $PID)${NC}"

# ─── Diagnostics & log capture ────────────────────────────────────

# Capture Android logs (Vauchi + exchange tags). Auto-selects device if multiple connected.
[group('device-test')]
[script]
dt-logs-android:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    SERIAL=$(dt_detect_android_device)
    adb -s "$SERIAL" logcat -d -s "Exchange:*" "Vauchi:*" "QrAnalyzer:*" "FaceToFace:*"

# Clear and stream Android logs. Auto-selects device if multiple connected.
[group('device-test')]
[script]
dt-logs-android-stream:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    SERIAL=$(dt_detect_android_device)
    adb -s "$SERIAL" logcat -c
    adb -s "$SERIAL" logcat -s "Exchange:*" "Vauchi:*" "QrAnalyzer:*" "FaceToFace:*"

# Stream iOS logs via idevicesyslog (captures NSLog from app process).
# Falls back to pymobiledevice3 if idevicesyslog is not installed.
[group('device-test')]
[script]
dt-logs-ios:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    UDID=$(dt_detect_ios_device)
    echo "Streaming iOS logs (Vauchi)... Press Ctrl+C to stop."
    if command -v idevicesyslog &>/dev/null; then
        # idevicesyslog with --syslog-relay captures NSLog from app processes.
        # pymobiledevice3 syslog uses unified logging which misses app-level NSLog.
        # Filter to Vauchi process logs (format: "Vauchi(subsystem)[pid]") and our NSLog tags.
        idevicesyslog -u "$UDID" --syslog-relay 2>&1 | grep --line-buffered -E "^ *Vauchi\(|\[Vauchi\]|\[Exchange\]|\[MultiStage\]"
    elif command -v pymobiledevice3 &>/dev/null; then
        echo "(Using pymobiledevice3 fallback — app NSLog may not appear)"
        echo "(Install libimobiledevice for reliable capture: brew install libimobiledevice)"
        pymobiledevice3 syslog live --match Vauchi 2>&1
    else
        echo "ERROR: No iOS log tool found."
        echo "Install: brew install libimobiledevice (preferred) or pip install pymobiledevice3"
        exit 1
    fi

# Verify installed build versions on connected devices
[group('device-test')]
[script]
dt-verify-builds:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    printf "%b\n" "${BLUE}=== Build Verification ===${NC}"

    # Android — check all connected devices
    DEVICES=$(adb devices 2>/dev/null | grep -w "device$" | awk '{print $1}')
    if [[ -n "$DEVICES" ]]; then
        for SERIAL in $DEVICES; do
            MODEL=$(adb -s "$SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
            echo ""
            printf "%b\n" "${YELLOW}Android ($MODEL — $SERIAL):${NC}"
            adb -s "$SERIAL" shell dumpsys package app.vauchi 2>/dev/null | grep -E "versionName|versionCode" | head -2 || echo "  App not installed"
            echo "  Core version (from logcat):"
            adb -s "$SERIAL" logcat -d -s "Vauchi:I" 2>/dev/null | grep "Build:" | tail -1 || echo "  No build log found — launch app first"
        done
    else
        printf "%b\n" "${YELLOW}Android: no device connected${NC}"
    fi

    # iOS — capture build version via idevicesyslog (falls back to pymobiledevice3)
    echo ""
    printf "%b\n" "${YELLOW}iOS:${NC}"
    if command -v idevicesyslog &>/dev/null; then
        UDID=$(dt_detect_ios_device 2>/dev/null || true)
        if [[ -n "$UDID" ]]; then
            # Kill existing app so relaunch produces a fresh startup NSLog
            APP_PID=$(idevicesyslog -u "$UDID" pidlist 2>/dev/null | grep "Vauchi" | awk '{print $1}')
            if [[ -n "$APP_PID" ]]; then
                xcrun devicectl device process terminate --device "$UDID" --pid "$APP_PID" 2>/dev/null || true
                sleep 1
            fi
            # Capture logs to temp file, relaunch, then read
            LOGFILE="/tmp/vauchi-ios-verify-$$.log"
            idevicesyslog -u "$UDID" --syslog-relay -o "$LOGFILE" &
            LOG_PID=$!
            sleep 0.5
            xcrun devicectl device process launch --device "$UDID" app.vauchi.ios 2>/dev/null || true
            sleep 3
            kill $LOG_PID 2>/dev/null || true
            wait $LOG_PID 2>/dev/null || true
            grep "\[Vauchi\]" "$LOGFILE" 2>/dev/null | head -3 || echo "  No [Vauchi] logs captured"
            rm -f "$LOGFILE"
        else
            echo "  No iOS device detected"
        fi
    elif command -v pymobiledevice3 &>/dev/null; then
        echo "  (pymobiledevice3 may miss app NSLog — install libimobiledevice for reliable capture)"
        pymobiledevice3 syslog live --match "Build:" 2>/dev/null | head -5 &
        PID=$!
        sleep 3
        kill $PID 2>/dev/null || true
    else
        echo "  Install libimobiledevice (brew install libimobiledevice) for iOS log capture"
    fi

# Run the exchange permission-denial instrumentation test on a connected
# Android device/emulator (T2.4 acceptance for exchange-waits-forever). Drives
# the camera+BLE-denial scenario and asserts the core-driven grant/other-mode
# affordance appears (queried via the screen_id testTag) — never infinite
# "Searching...". The BLE leg works today (Phase 0 PermissionDenied forwarding);
# the camera leg is gated on T0.3 (camera-deny → PermissionDenied forwarding).
# SCAFFOLD: the test class PermissionDeniedExchangeTest is NOT committed yet —
# see _private/docs/problems/2026-06-11-exchange-waits-forever-without-capabilities
# (T2.4) for the test design. Until it lands, this recipe reports "no tests
# found". It is the human-run entry point (no device CI runner exists).
[group('device-test')]
[script]
dt-android-permission-test:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    SERIAL=$(dt_detect_android_device)
    printf "%b\n" "${YELLOW}Running exchange permission-denial test on $SERIAL...${NC}"
    printf "%b\n" "${YELLOW}(install the debug APK first via 'just rebuild-android' if needed)${NC}"
    cd android
    ANDROID_SERIAL="$SERIAL" ./gradlew connectedDebugAndroidTest \
        -PlocalBindings \
        -Pandroid.testInstrumentationRunnerArguments.class=app.vauchi.ui.PermissionDeniedExchangeTest \
        2>&1 | tail -40
    printf "%b\n" "${GREEN}  Permission-denial test run complete${NC}"

# Take a screenshot from connected Android device. Auto-selects device if multiple connected.
[group('device-test')]
[script]
dt-screenshot-android file="screenshot.png":
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    SERIAL=$(dt_detect_android_device)
    adb -s "$SERIAL" exec-out screencap -p > "{{file}}"
    if [[ ! -s "{{file}}" ]]; then
        echo "ERROR: adb screencap wrote a 0-byte file." >&2
        echo "       Possible causes: device locked (screencap denied)," >&2
        echo "       USB drop mid-stream, or screencap-deny by policy." >&2
        echo "       Unlock the device and retry, or use:" >&2
        echo "         adb -s $SERIAL shell screencap -p /sdcard/s.png && adb pull /sdcard/s.png" >&2
        exit 1
    fi
    echo "Screenshot saved to {{file}} (device: $SERIAL)"

# Take a screenshot from connected iOS device (requires pymobiledevice3)
[group('device-test')]
[script]
dt-screenshot-ios file="screenshot.png":
    set -euo pipefail
    if ! command -v pymobiledevice3 &>/dev/null; then
        echo "ERROR: pymobiledevice3 not installed. Install: pip install pymobiledevice3"
        exit 1
    fi
    pymobiledevice3 developer dvt screenshot "{{file}}"
    if [[ ! -s "{{file}}" ]]; then
        echo "ERROR: pymobiledevice3 reported success but no screenshot file was written." >&2
        echo "       (pymobiledevice3 exits 0 on tunneld connection failure — known upstream bug.)" >&2
        echo "       Start tunneld:  sudo python3 -m pymobiledevice3 remote tunneld" >&2
        exit 1
    fi
    echo "Screenshot saved to {{file}}"

# ─── App lifecycle (kill / launch) ────────────────────────────────

# Kill and relaunch iOS app
[group('device-test')]
[script]
dt-relaunch-ios:
    set -euo pipefail
    echo "Killing and relaunching Vauchi on iOS..."
    pymobiledevice3 developer dvt kill app.vauchi.ios 2>/dev/null || true
    sleep 1
    LAUNCH_OUT=$(pymobiledevice3 developer dvt launch app.vauchi.ios 2>&1)
    echo "$LAUNCH_OUT" | head -2
    if ! echo "$LAUNCH_OUT" | grep -q "Launched application"; then
        echo "ERROR: pymobiledevice3 launch did not confirm success." >&2
        echo "       Common cause: tunneld is not running. Start it with:" >&2
        echo "       sudo python3 -m pymobiledevice3 remote tunneld" >&2
        exit 1
    fi
    echo "iOS app relaunched."

# Kill and relaunch Android app. Auto-selects device if multiple connected.
[group('device-test')]
[script]
dt-relaunch-android:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    SERIAL=$(dt_detect_android_device)
    echo "Killing and relaunching Vauchi on Android ($SERIAL)..."
    adb -s "$SERIAL" shell am force-stop app.vauchi
    sleep 1
    START_OUT=$(adb -s "$SERIAL" shell am start -n app.vauchi/.MainActivity 2>&1)
    echo "$START_OUT"
    if echo "$START_OUT" | grep -qiE "^Error|Activity not found|does not exist"; then
        echo "ERROR: am start reported failure (see above)." >&2
        exit 1
    fi
    echo "Android app relaunched."

# Install + relaunch iOS (convenience: build already done, just install and restart)
[group('device-test')]
[script]
dt-deploy-ios:
    set -euo pipefail
    just _dt-install-ios
    just dt-relaunch-ios

# Install + relaunch Android (convenience: build already done, just install and restart)
[group('device-test')]
[script]
dt-deploy-android:
    set -euo pipefail
    just _dt-install-android
    just dt-relaunch-android

# Uninstall Vauchi from all connected devices (clean slate)
[group('device-test')]
[script]
dt-clean-devices:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"

    printf "%b\n" "${YELLOW}╔════════════════════════════════════════════════╗${NC}"
    printf "%b\n" "${YELLOW}║     Clean Devices — Uninstall Vauchi          ║${NC}"
    printf "%b\n" "${YELLOW}╚════════════════════════════════════════════════╝${NC}"
    echo ""

    # Android (all connected devices)
    ANDROID_SERIALS=$(adb devices 2>/dev/null | grep -E "^[^[:space:]]+[[:space:]]+device$" | awk '{print $1}')
    if [[ -n "$ANDROID_SERIALS" ]]; then
        while IFS= read -r SERIAL; do
            printf "%b\n" "${BLUE}Uninstalling from Android ($SERIAL)...${NC}"
            adb -s "$SERIAL" uninstall app.vauchi 2>/dev/null && \
                printf "%b\n" "${GREEN}  Android app uninstalled${NC}" || \
                printf "%b\n" "${YELLOW}  Android app not installed (skipped)${NC}"
        done <<< "$ANDROID_SERIALS"
    else
        printf "%b\n" "${YELLOW}No Android device connected (skipped)${NC}"
    fi

    # iOS — pymobiledevice3 apps uninstall exits 0 with "Installation succeed"
    # regardless of actual outcome (even for a non-existent bundle id), so the
    # naive `&& uninstalled || skip` pattern always took the success branch.
    # Determine real state via `apps list` and verify the uninstall took effect.
    if UDID=$(dt_detect_ios_device 2>/dev/null); then
        printf "%b\n" "${BLUE}Uninstalling from iOS ($UDID)...${NC}"
        if pymobiledevice3 apps list 2>/dev/null | python3 -c "import sys,json; sys.exit(0 if 'app.vauchi.ios' in json.load(sys.stdin) else 1)" 2>/dev/null; then
            pymobiledevice3 apps uninstall app.vauchi.ios 2>/dev/null || true
            if pymobiledevice3 apps list 2>/dev/null | python3 -c "import sys,json; sys.exit(0 if 'app.vauchi.ios' in json.load(sys.stdin) else 1)" 2>/dev/null; then
                printf "%b\n" "${RED}  ERROR: pymobiledevice3 reported success but app.vauchi.ios is still installed.${NC}" >&2
                echo "         (pymobiledevice3 apps uninstall exits 0 regardless of outcome.)" >&2
                exit 1
            fi
            printf "%b\n" "${GREEN}  iOS app uninstalled${NC}"
        else
            printf "%b\n" "${YELLOW}  iOS app not installed (skipped)${NC}"
        fi
    else
        printf "%b\n" "${YELLOW}No iOS device connected (skipped)${NC}"
    fi

    echo ""
    printf "%b\n" "${GREEN}Devices cleaned. Run 'just prepare-device-test' to install fresh.${NC}"

# ─── iOS UI Automation (WebDriverAgent) ──────────────────────────

# Start WebDriverAgent on connected iPhone (builds if needed)
[group('device-test')]
[script]
dt-wda-start:
    set -euo pipefail
    source "$(pwd)/just/device-test-lib.sh"
    # macOS clears /tmp aggressively between reboots, and CoreDevice's
    # bookmark sandbox refuses to install xcodebuild artefacts out of
    # /tmp paths (errSecInternalComponent + "Failed to obtain access
    # to one or more requested file system resources because
    # CoreDevice was unable to create bookmark data"). Persistent
    # location matches `_private/docs/testing/device-automation/test-run-context.md`
    # and the runner's preflight expectations.
    WDA_DIR="${HOME}/Workspace/.tools/WebDriverAgent"

    if [[ ! -d "$WDA_DIR" ]]; then
        printf "%b\n" "${YELLOW}Cloning WebDriverAgent...${NC}"
        mkdir -p "$(dirname "$WDA_DIR")"
        git clone https://github.com/appium/WebDriverAgent.git "$WDA_DIR"
    fi

    UDID=$(dt_detect_ios_device)
    TEAM_ID="L2853TNSJ4"

    printf "%b\n" "${YELLOW}Starting WebDriverAgent on device $UDID...${NC}"
    echo "First run requires Touch ID / passcode on device ('Enable UI Automation')"
    echo ""
    cd "$WDA_DIR"
    # test-without-building fails on a fresh machine ("Failed to install
    # the app on the device" / missing products) — build-for-testing
    # first when no Runner app exists yet (2026-06-11 session).
    if ! ls "$HOME/Library/Developer/Xcode/DerivedData"/WebDriverAgent-*/Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}No WDA build products found — running build-for-testing first...${NC}"
        xcodebuild -project WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner \
            -destination "id=$UDID" \
            DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="Apple Development" \
            -allowProvisioningUpdates build-for-testing 2>&1 \
            | grep --line-buffered -E "BUILD|error:" || true
    fi
    xcodebuild -project WebDriverAgent.xcodeproj -scheme WebDriverAgentRunner \
        -destination "id=$UDID" \
        DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="Apple Development" \
        -allowProvisioningUpdates test-without-building 2>&1 \
        | grep --line-buffered -E "ServerURLHere|Test Suite|error:"

# Tap iOS screen at coordinates via WebDriverAgent
[group('device-test')]
[script]
dt-ios-tap x y wda_url="http://169.254.202.178:8100":
    set -euo pipefail
    WDA="{{wda_url}}"

    # Get or create session
    SID=$(curl -s "$WDA/status" | python3 -c "
    import sys, json
    data = json.load(sys.stdin)
    sid = data.get('sessionId') or ''
    print(sid)
    " 2>/dev/null)

    if [[ -z "$SID" ]]; then
        # Pin Vauchi as the session bundle so WDA brings the app to
        # foreground. Empty `capabilities: {}` returned a SpringBoard-
        # bound session right after `devicectl process launch`, making
        # downstream tap/screenshot operations target the launcher
        # rather than Vauchi. Same fix the runner shipped today
        # (`vauchi-gui-test.sh wda_new_session` — `_private!1218`).
        SID=$(curl -s -X POST "$WDA/session" -H 'Content-Type: application/json' \
            -d '{"capabilities":{"alwaysMatch":{"bundleId":"app.vauchi.ios"}}}' | python3 -c "import sys,json; print(json.load(sys.stdin)['value']['sessionId'])")
    fi

    echo "Tapping ({{x}}, {{y}}) via WDA session $SID..."
    RESP_FILE=$(mktemp)
    trap 'rm -f "$RESP_FILE"' EXIT
    if ! curl -s --fail-with-body -X POST "$WDA/session/$SID/actions" -H 'Content-Type: application/json' \
        -d "{\"actions\":[{\"type\":\"pointer\",\"id\":\"finger1\",\"parameters\":{\"pointerType\":\"touch\"},\"actions\":[{\"type\":\"pointerMove\",\"duration\":0,\"x\":{{x}},\"y\":{{y}}},{\"type\":\"pointerDown\",\"button\":0},{\"type\":\"pause\",\"duration\":50},{\"type\":\"pointerUp\",\"button\":0}]}]}" > "$RESP_FILE"; then
        echo "ERROR: WDA tap returned an HTTP error:" >&2
        cat "$RESP_FILE" >&2
        exit 1
    fi
    echo "Done."

# Take iOS screenshot via WebDriverAgent (returns PNG)
[group('device-test')]
[script]
dt-wda-screenshot file="screenshot-ios.png" wda_url="http://169.254.202.178:8100":
    set -euo pipefail
    WDA="{{wda_url}}"

    SID=$(curl -s "$WDA/status" | python3 -c "
    import sys, json
    data = json.load(sys.stdin)
    sid = data.get('sessionId') or ''
    print(sid)
    " 2>/dev/null)

    if [[ -z "$SID" ]]; then
        # Pin Vauchi as the session bundle so WDA brings the app to
        # foreground. Empty `capabilities: {}` returned a SpringBoard-
        # bound session right after `devicectl process launch`, making
        # downstream tap/screenshot operations target the launcher
        # rather than Vauchi. Same fix the runner shipped today
        # (`vauchi-gui-test.sh wda_new_session` — `_private!1218`).
        SID=$(curl -s -X POST "$WDA/session" -H 'Content-Type: application/json' \
            -d '{"capabilities":{"alwaysMatch":{"bundleId":"app.vauchi.ios"}}}' | python3 -c "import sys,json; print(json.load(sys.stdin)['value']['sessionId'])")
    fi

    curl -s "$WDA/session/$SID/screenshot" | python3 -c "
    import sys, json, base64
    data = json.load(sys.stdin)
    img = base64.b64decode(data['value'])
    sys.stdout.buffer.write(img)
    " > "{{file}}"
    if [[ ! -s "{{file}}" ]]; then
        echo "ERROR: WDA returned empty screenshot data — file not written or 0-byte." >&2
        echo "       Possible causes: WDA session expired, base64 payload empty, network-link broken." >&2
        exit 1
    fi
    echo "Screenshot saved to {{file}}"

# Real-device usability gate — golden-path flows on physical hardware + evidence
# PLATFORM: ios | android | linux | all (just rejects a variadic after a
# default parameter, so PLATFORM is required; pass `all` explicitly).
[group('device-test')]
device-gate PLATFORM *FLAGS:
    scripts/scripts/device-gate.sh {{PLATFORM}} {{FLAGS}}
