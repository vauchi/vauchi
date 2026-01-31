# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Mobile build & check recipes

# ═══════════════════════════════════════════════════════════════════
# MOBILE BUILDS
# ═══════════════════════════════════════════════════════════════════

# Build Android native libraries
[group('mobile')]
build-android mode="debug":
    ./core/scripts/build-android.sh {{mode}}

# Build Android APK
[group('mobile')]
[working-directory('android')]
android mode="debug": (build-android mode)
    ./gradlew assemble{{mode}}

# Build iOS framework (macOS only)
[group('mobile')]
build-ios mode="debug":
    BUILD_MODE={{mode}} ./ios/build-ios.sh

# Generate UniFFI mobile bindings
[group('mobile')]
bindings:
    ./core/scripts/build-bindings.sh

# ═══════════════════════════════════════════════════════════════════
# MOBILE CHECKS (pre-MR validation)
# ═══════════════════════════════════════════════════════════════════

# Run iOS checks (lint, build, test) — mirrors CI pipeline
[group('mobile')]
[script('bash')]
check-ios:
    set -e
    cd ios
    echo "=== iOS: Generating Xcode project ==="
    xcodegen generate
    echo ""
    echo "=== iOS: Building (Debug) ==="
    xcodebuild -project Vauchi.xcodeproj -scheme Vauchi -configuration Debug \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
      -clonedSourcePackagesDirPath .spm-packages build
    echo ""
    echo "=== iOS: Running tests ==="
    xcodebuild -project Vauchi.xcodeproj -scheme Vauchi -configuration Debug \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
      -clonedSourcePackagesDirPath .spm-packages test
    echo ""
    echo "=== iOS checks passed ==="

# Run Android checks (lint, build, test) — mirrors CI pipeline
[group('mobile')]
[script('bash')]
check-android:
    set -e
    cd android
    echo "=== Android: Lint ==="
    ./gradlew lint
    echo ""
    echo "=== Android: Building (Debug) ==="
    ./gradlew assembleDebug
    echo ""
    echo "=== Android: Running tests ==="
    ./gradlew test
    echo ""
    echo "=== Android checks passed ==="

# Run all mobile checks (iOS + Android)
[group('mobile')]
check-mobile: check-ios check-android
