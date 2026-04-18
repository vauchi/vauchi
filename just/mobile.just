# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Mobile build & check recipes

# ═══════════════════════════════════════════════════════════════════
# MOBILE BUILDS
# ═══════════════════════════════════════════════════════════════════

# Build Android native libraries
# NOTE: Requires core/scripts/build-android.sh — see platform-bindings skill
[group('mobile')]
[script]
build-android mode="debug":
    set -e
    SCRIPT="./core/scripts/build-android.sh"
    if [ ! -f "$SCRIPT" ]; then
        echo "ERROR: $SCRIPT not found"
        echo "Android build scripts are not yet implemented."
        echo "Use 'just bindings' for UniFFI binding generation instead."
        exit 1
    fi
    "$SCRIPT" {{mode}}

# Build Android APK
[group('mobile')]
[working-directory('android')]
android mode="debug": (build-android mode)
    ./gradlew assemble{{ capitalize(mode) }}

# Build iOS framework (macOS only)
# NOTE: Requires ios/build-ios.sh — see platform-bindings skill
[group('mobile')]
[script]
build-ios mode="debug":
    set -e
    SCRIPT="./ios/build-ios.sh"
    if [ ! -f "$SCRIPT" ]; then
        echo "ERROR: $SCRIPT not found"
        echo "iOS build scripts are not yet implemented."
        echo "Use 'just bindings' for UniFFI binding generation instead."
        exit 1
    fi
    BUILD_MODE={{mode}} "$SCRIPT"

# Generate UniFFI mobile bindings
[group('mobile')]
bindings:
    ./core/scripts/build-bindings.sh

# Generate bindings AND wire them into local platform builds
[group('mobile')]
bindings-local: bindings
    ./scripts/wire-bindings-local.sh

# Revert to published (remote) bindings
[group('mobile')]
bindings-remote:
    ./scripts/wire-bindings-remote.sh

# Build and install iOS app on a connected device using local bindings
# Uses the build keychain for code signing (avoids login keychain prompts)
[group('mobile')]
[script]
build-ios-device mode="debug":
    set -e
    # Unlock the build keychain for code signing
    security unlock-keychain -p "build" ~/Library/Keychains/build.keychain-db
    security set-keychain-settings -t 300 ~/Library/Keychains/build.keychain-db

    # Detect build source: workspace (local bindings) or project (remote)
    if [ -d "ios/Vauchi.xcworkspace" ]; then
        SRC="-workspace Vauchi.xcworkspace"
        echo "── iOS: Building from workspace (local bindings) ──"
    else
        SRC="-project Vauchi.xcodeproj"
        echo "── iOS: Building from project (remote bindings) ──"
    fi

    MODE="{{ capitalize(mode) }}"
    cd ios
    xcodebuild $SRC -scheme Vauchi \
      -destination 'generic/platform=iOS' \
      -configuration "$MODE" \
      -derivedDataPath build \
      build

    echo ""
    echo "── iOS: Installing on device ──"
    APP_PATH="build/Build/Products/${MODE}-iphoneos/Vauchi.app"
    if [ ! -d "$APP_PATH" ]; then
        echo "ERROR: $APP_PATH not found"
        exit 1
    fi
    DEVICE_LIST=$(xcrun devicectl list devices 2>&1 || true)
    DEVICE_ID=$(echo "$DEVICE_LIST" | grep 'available' | head -1 | sed -n 's/.*\([0-9A-F]\{8\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{4\}-[0-9A-F]\{12\}\).*/\1/p')
    if [ -z "$DEVICE_ID" ]; then
        echo "ERROR: No connected iOS device found"
        echo "$DEVICE_LIST"
        exit 1
    fi
    echo "  Device: $DEVICE_ID"
    xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
    echo "── iOS: Installed ──"

# ═══════════════════════════════════════════════════════════════════
# MOBILE CHECKS (pre-MR validation)
# ═══════════════════════════════════════════════════════════════════

# Run iOS checks (lint, build, test) — mirrors CI pipeline
[group('mobile')]
[script]
check-ios:
    set -e
    cd ios
    echo "── iOS: Generating Xcode project ──"
    xcodegen generate
    echo ""
    echo "── iOS: Building (Debug) ──"
    xcodebuild -project Vauchi.xcodeproj -scheme Vauchi -configuration Debug \
      -destination 'platform=iOS Simulator,name={{ ios_simulator }}' \
      -clonedSourcePackagesDirPath .spm-packages -skipPackageUpdates build
    echo ""
    echo "── iOS: Running tests ──"
    xcodebuild -project Vauchi.xcodeproj -scheme Vauchi -configuration Debug \
      -destination 'platform=iOS Simulator,name={{ ios_simulator }}' \
      -clonedSourcePackagesDirPath .spm-packages -skipPackageUpdates test
    echo ""
    echo "── iOS checks passed ──"

# Run Android checks (lint, build, test) — mirrors CI pipeline
[group('mobile')]
[script]
check-android:
    set -e
    cd android
    echo "── Android: Lint ──"
    ./gradlew lint
    echo ""
    echo "── Android: Building (Debug) ──"
    ./gradlew assembleDebug
    echo ""
    echo "── Android: Running tests ──"
    ./gradlew test
    echo ""
    echo "── Android checks passed ──"

# Run all mobile checks (iOS + Android)
[group('mobile')]
check-mobile: check-ios check-android
