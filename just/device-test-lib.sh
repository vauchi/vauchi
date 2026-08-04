#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Shared functions for device-test just recipes.
# Sourced by device-test.just recipes — not executed directly.

# Colors
RED='\033[0;31m'
# Exported to recipes that source this helper.
# shellcheck disable=SC2034
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
BLUE='\033[0;34m'
NC='\033[0m'

dt_set_xcode_auth_args() {
    DT_XCODE_AUTH_ARGS=()
    if [[ -n "${VAUCHI_ASC_KEY_PATH:-}" \
       && -n "${VAUCHI_ASC_KEY_ID:-}" \
       && -n "${VAUCHI_ASC_ISSUER_ID:-}" ]]; then
        # Consumed by device-test.just after sourcing this library.
        # shellcheck disable=SC2034
        DT_XCODE_AUTH_ARGS=(
            -authenticationKeyPath "$VAUCHI_ASC_KEY_PATH"
            -authenticationKeyID "$VAUCHI_ASC_KEY_ID"
            -authenticationKeyIssuerID "$VAUCHI_ASC_ISSUER_ID"
        )
    fi
}

# Resolve the core directory.
# Priority: explicit argument > worktree of current branch > core/
dt_resolve_core_dir() {
    local explicit="${1:-}"

    if [[ -n "$explicit" ]]; then
        # Explicit path provided
        if [[ ! -d "$explicit" ]]; then
            printf "%b\n" "${RED}ERROR: Core directory not found: $explicit${NC}" >&2
            exit 1
        fi
        echo "$explicit"
        return
    fi

    # Auto-detect: check if vauchi-mobile-swift symlink points to a worktree
    local spm_symlink="vauchi-mobile-swift/VauchiMobileFFI.xcframework"
    if [[ -L "$spm_symlink" ]]; then
        local target
        target=$(readlink "$spm_symlink")
        # Extract core dir from symlink target
        # e.g., /Users/.../core/.worktrees/feature-foo/target/xcframework-build/...
        if [[ "$target" == *"core/.worktrees/"* ]]; then
            local worktree_dir
            worktree_dir=$(echo "$target" | sed 's|/target/xcframework-build/.*||')
            if [[ -d "$worktree_dir" ]]; then
                echo "$worktree_dir"
                return
            fi
        fi
    fi

    # Check if core/ has a non-main branch checked out with a worktree
    if [[ -d "core" ]]; then
        local current_branch
        current_branch=$(git -C core branch --show-current 2>/dev/null || echo "main")
        if [[ "$current_branch" != "main" && -d "core/.worktrees/$current_branch" ]]; then
            echo "core/.worktrees/$current_branch"
            return
        fi
    fi

    # Default to core/
    echo "core"
}

# Check that all prerequisites are available
dt_check_prerequisites() {
    dt_check_prerequisites_ios
    dt_check_prerequisites_android
}

# Check iOS prerequisites
dt_check_prerequisites_ios() {
    local missing=()

    if [[ "$(uname)" != "Darwin" ]]; then
        printf "%b\n" "${RED}ERROR: Device testing requires macOS${NC}" >&2
        exit 1
    fi

    if ! command -v xcodebuild &>/dev/null; then
        missing+=("xcodebuild (Xcode)")
    fi
    if ! command -v xcrun &>/dev/null; then
        missing+=("xcrun (Xcode CLI tools)")
    fi
    if ! command -v cargo &>/dev/null; then
        missing+=("cargo (Rust toolchain)")
    fi

    # Check iOS targets
    if ! rustup target list --installed 2>/dev/null | grep -q "aarch64-apple-ios"; then
        printf "%b\n" "${YELLOW}Installing iOS Rust target...${NC}"
        rustup target add aarch64-apple-ios
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf "%b\n" "${RED}ERROR: Missing prerequisites:${NC}" >&2
        for m in "${missing[@]}"; do
            echo "  - $m" >&2
        done
        exit 1
    fi
}

# Check Android prerequisites
dt_check_prerequisites_android() {
    local missing=()

    if ! command -v adb &>/dev/null; then
        missing+=("adb (Android SDK platform-tools)")
    fi
    if ! command -v cargo &>/dev/null; then
        missing+=("cargo (Rust toolchain)")
    fi

    # Check Android target
    if ! rustup target list --installed 2>/dev/null | grep -q "aarch64-linux-android"; then
        printf "%b\n" "${YELLOW}Installing Android Rust target...${NC}"
        rustup target add aarch64-linux-android
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf "%b\n" "${RED}ERROR: Missing prerequisites:${NC}" >&2
        for m in "${missing[@]}"; do
            echo "  - $m" >&2
        done
        exit 1
    fi
}

# Set up Android NDK environment variables for cross-compilation
dt_setup_android_ndk() {
    local ndk_home="${ANDROID_NDK_HOME:-}"

    # Auto-detect NDK
    if [[ -z "$ndk_home" || ! -d "$ndk_home" ]]; then
        for ndk_path in \
            "$HOME/Library/Android/sdk/ndk"/* \
            "$HOME/Android/Sdk/ndk"/* \
            "/opt/android-ndk" \
            ; do
            if [[ -d "$ndk_path" ]]; then
                ndk_home="$ndk_path"
                break
            fi
        done
    fi

    if [[ ! -d "$ndk_home" ]]; then
        printf "%b\n" "${RED}ERROR: Android NDK not found${NC}" >&2
        echo "Set ANDROID_NDK_HOME or install NDK via Android Studio" >&2
        exit 1
    fi

    echo "  Using NDK: $ndk_home"

    # Determine toolchain path
    local toolchain
    if [[ "$(uname)" == "Darwin" ]]; then
        toolchain="$ndk_home/toolchains/llvm/prebuilt/darwin-x86_64/bin"
    else
        toolchain="$ndk_home/toolchains/llvm/prebuilt/linux-x86_64/bin"
    fi

    if [[ ! -d "$toolchain" ]]; then
        printf "%b\n" "${RED}ERROR: NDK toolchain not found at $toolchain${NC}" >&2
        exit 1
    fi

    export CC_aarch64_linux_android="$toolchain/aarch64-linux-android24-clang"
    export AR_aarch64_linux_android="$toolchain/llvm-ar"
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$toolchain/aarch64-linux-android24-clang"
}

# Build a versioned SwiftPM mirror around the freshly packaged local
# XCFramework. SwiftPM still resolves the package's semantic version even when
# its manifest selects a path-based binary target, so merely placing the local
# package in the Xcode workspace is insufficient.
dt_provision_ios_local_spm() {
    local workspace_root="$1"
    local spm_dir="$workspace_root/vauchi-platform-swift"
    local spm_framework="$spm_dir/VauchiPlatformFFI.xcframework"
    local device_binary
    local version
    local artifact_id
    local mirror
    local mirror_ready
    local mirror_json

    device_binary="$spm_framework/ios-arm64/VauchiPlatformFFI.framework/VauchiPlatformFFI"
    version=$(sed -n 's/^let version = "\([^"]*\)".*/\1/p' \
        "$spm_dir/Package.swift")
    if [[ -z "$version" || ! -f "$device_binary" ]]; then
        printf '%b\n' \
            "${RED}ERROR: Packaged local iOS binding is incomplete${NC}" >&2
        return 1
    fi

    artifact_id=$(git hash-object "$device_binary" | cut -c1-16)
    mirror="$HOME/.cache/vauchi-platform-swift-device-mirror"
    # SwiftPM derives a mirror's package identity from the file:// URL's last
    # path component; Xcode 26 / Swift 6.3 rejects the override unless it
    # equals the original identity ("vauchi-platform-swift"). Keep the
    # version+artifact as a parent dir (reproducible per-artifact cache key,
    # a77218f) and name the mirror leaf to match the identity.
    mirror="$mirror/v${version}-${artifact_id}/vauchi-platform-swift"
    mirror_ready="$mirror/.device-mirror-ready"

    if [[ ! -f "$mirror_ready" ]]; then
        printf '%b\n' \
            "${YELLOW}Provisioning local SwiftPM device mirror...${NC}"
        rm -rf "$mirror"
        mkdir -p "$(dirname "$mirror")"
        git clone --quiet --single-branch --branch "v$version" "$spm_dir" "$mirror"

        cp "$spm_dir/Sources/VauchiPlatform/vauchi_platform.swift" \
            "$mirror/Sources/VauchiPlatform/vauchi_platform.swift"
        rm -rf "$mirror/VauchiPlatformFFI.xcframework"
        cp -RL "$spm_framework" "$mirror/VauchiPlatformFFI.xcframework"

        git -C "$mirror" add -f \
            Sources/VauchiPlatform/vauchi_platform.swift \
            VauchiPlatformFFI.xcframework
        git -C "$mirror" -c user.email=device-test@vauchi.local \
            -c user.name=device-test commit --quiet \
            -m "device-test: bundle local xcframework v$version"
        git -C "$mirror" tag -d "v$version" >/dev/null
        git -C "$mirror" tag "v$version"
        touch "$mirror_ready"
    fi

    if ! git -C "$mirror" cat-file -e \
        "v$version:VauchiPlatformFFI.xcframework/ios-arm64/VauchiPlatformFFI.framework/VauchiPlatformFFI"
    then
        printf '%b\n' \
            "${RED}ERROR: Local SwiftPM mirror is missing its device binary${NC}" >&2
        return 1
    fi

    mirror_json=$(printf '%s\n' \
        '{' \
        '  "version": 1,' \
        '  "object": [{' \
        '    "original": "https://gitlab.com/vauchi/vauchi-platform-swift.git",' \
        "    \"mirror\": \"file://$mirror\"" \
        '  }]' \
        '}')

    DT_IOS_SPM_PROJECT_CONFIG="$workspace_root/ios/.swiftpm/configuration/mirrors.json"
    DT_IOS_SPM_PROJECT_CONFIG_EXISTED=0
    DT_IOS_SPM_PROJECT_CONFIG_BACKUP=""
    if [[ -f "$DT_IOS_SPM_PROJECT_CONFIG" ]]; then
        DT_IOS_SPM_PROJECT_CONFIG_EXISTED=1
        DT_IOS_SPM_PROJECT_CONFIG_BACKUP=$(mktemp \
            "${TMPDIR:-/tmp}/vauchi-project-spm-mirrors.XXXXXX")
        cp "$DT_IOS_SPM_PROJECT_CONFIG" "$DT_IOS_SPM_PROJECT_CONFIG_BACKUP"
    fi
    mkdir -p "$(dirname "$DT_IOS_SPM_PROJECT_CONFIG")"
    printf '%s' "$mirror_json" > "$DT_IOS_SPM_PROJECT_CONFIG"

    DT_IOS_SPM_USER_CONFIG="$HOME/Library/org.swift.swiftpm/configuration/mirrors.json"
    DT_IOS_SPM_USER_CONFIG_EXISTED=0
    DT_IOS_SPM_USER_CONFIG_BACKUP=""
    if [[ -f "$DT_IOS_SPM_USER_CONFIG" ]]; then
        DT_IOS_SPM_USER_CONFIG_EXISTED=1
        DT_IOS_SPM_USER_CONFIG_BACKUP=$(mktemp \
            "${TMPDIR:-/tmp}/vauchi-spm-mirrors.XXXXXX")
        cp "$DT_IOS_SPM_USER_CONFIG" "$DT_IOS_SPM_USER_CONFIG_BACKUP"
    fi
    mkdir -p "$(dirname "$DT_IOS_SPM_USER_CONFIG")"
    printf '%s' "$mirror_json" > "$DT_IOS_SPM_USER_CONFIG"

    DT_IOS_SPM_CACHE_PATH="$workspace_root/ios/.device-spm-packages/$artifact_id"
    export DT_IOS_SPM_CACHE_PATH
}

dt_restore_ios_spm_config() {
    if [[ "${DT_IOS_SPM_PROJECT_CONFIG_EXISTED:-0}" -eq 1 ]]; then
        cp "$DT_IOS_SPM_PROJECT_CONFIG_BACKUP" "$DT_IOS_SPM_PROJECT_CONFIG"
    elif [[ -n "${DT_IOS_SPM_PROJECT_CONFIG:-}" ]]; then
        rm -f "$DT_IOS_SPM_PROJECT_CONFIG"
    fi

    if [[ "${DT_IOS_SPM_USER_CONFIG_EXISTED:-0}" -eq 1 ]]; then
        cp "$DT_IOS_SPM_USER_CONFIG_BACKUP" "$DT_IOS_SPM_USER_CONFIG"
    elif [[ -n "${DT_IOS_SPM_USER_CONFIG:-}" ]]; then
        rm -f "$DT_IOS_SPM_USER_CONFIG"
    fi

    if [[ -n "${DT_IOS_SPM_USER_CONFIG_BACKUP:-}" ]]; then
        rm -f "$DT_IOS_SPM_USER_CONFIG_BACKUP"
    fi
    if [[ -n "${DT_IOS_SPM_PROJECT_CONFIG_BACKUP:-}" ]]; then
        rm -f "$DT_IOS_SPM_PROJECT_CONFIG_BACKUP"
    fi
}

# Detect connected iOS device UDID
dt_detect_ios_device() {
    local device_id="${IOS_DEVICE_ID:-}"

    # Use env var override if set
    if [[ -n "$device_id" ]]; then
        echo "$device_id"
        return
    fi

    # Try pymobiledevice3 first (more reliable)
    if command -v pymobiledevice3 &>/dev/null; then
        device_id=$(pymobiledevice3 usbmux list 2>/dev/null \
            | grep -oE '"UniqueDeviceID"[[:space:]]*:[[:space:]]*"[^"]*"' \
            | head -1 \
            | sed 's/.*"\([^"]*\)"$/\1/')
    fi

    # Fall back to xcrun devicectl
    if [[ -z "$device_id" ]]; then
        device_id=$(xcrun devicectl list devices 2>/dev/null \
            | grep -E "^[[:space:]]" \
            | grep -v "Simulator" \
            | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
            | head -1)
    fi

    # Fall back to system_profiler
    if [[ -z "$device_id" ]]; then
        device_id=$(system_profiler SPUSBDataType 2>/dev/null \
            | grep -A5 "iPhone\|iPad" \
            | grep "Serial Number" \
            | head -1 \
            | sed 's/.*Serial Number: //' \
            | tr -d '[:space:]')
    fi

    if [[ -z "$device_id" ]]; then
        printf "%b\n" "${RED}ERROR: No iOS device detected${NC}" >&2
        echo "Connect an iPhone/iPad via USB and trust the computer." >&2
        echo "Alternatively, set IOS_DEVICE_ID environment variable." >&2
        exit 1
    fi

    echo "$device_id"
}

# Detect connected Android device serial
dt_detect_android_device() {
    local serial="${ANDROID_SERIAL:-}"

    if [[ -z "$serial" ]]; then
        serial=$(adb devices 2>/dev/null \
            | grep -E "^[^[:space:]]+[[:space:]]+device$" \
            | head -1 \
            | awk '{print $1}')
    fi

    if [[ -z "$serial" ]]; then
        printf "%b\n" "${RED}ERROR: No Android device detected${NC}" >&2
        echo "Connect an Android device via USB and enable USB debugging." >&2
        echo "Alternatively, set ANDROID_SERIAL environment variable." >&2
        exit 1
    fi

    echo "$serial"
}
