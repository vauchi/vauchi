#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Shared functions for device-test just recipes.
# Sourced by device-test.just recipes — not executed directly.

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Resolve the core directory.
# Priority: explicit argument > worktree of current branch > core/
dt_resolve_core_dir() {
    local explicit="${1:-}"

    if [[ -n "$explicit" ]]; then
        # Explicit path provided
        if [[ ! -d "$explicit" ]]; then
            echo -e "${RED}ERROR: Core directory not found: $explicit${NC}" >&2
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
        echo -e "${RED}ERROR: Device testing requires macOS${NC}" >&2
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
        echo -e "${YELLOW}Installing iOS Rust target...${NC}"
        rustup target add aarch64-apple-ios
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}ERROR: Missing prerequisites:${NC}" >&2
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
        echo -e "${YELLOW}Installing Android Rust target...${NC}"
        rustup target add aarch64-linux-android
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}ERROR: Missing prerequisites:${NC}" >&2
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
        echo -e "${RED}ERROR: Android NDK not found${NC}" >&2
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
        echo -e "${RED}ERROR: NDK toolchain not found at $toolchain${NC}" >&2
        exit 1
    fi

    export CC_aarch64_linux_android="$toolchain/aarch64-linux-android24-clang"
    export AR_aarch64_linux_android="$toolchain/llvm-ar"
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$toolchain/aarch64-linux-android24-clang"
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
            | grep -oE '"UniqueDeviceID"\s*:\s*"[^"]*"' \
            | head -1 \
            | sed 's/.*"\([^"]*\)"$/\1/')
    fi

    # Fall back to xcrun devicectl
    if [[ -z "$device_id" ]]; then
        device_id=$(xcrun devicectl list devices 2>/dev/null \
            | grep -E "^\s" \
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
        echo -e "${RED}ERROR: No iOS device detected${NC}" >&2
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
            | grep -E "^\S+\s+device$" \
            | head -1 \
            | awk '{print $1}')
    fi

    if [[ -z "$serial" ]]; then
        echo -e "${RED}ERROR: No Android device detected${NC}" >&2
        echo "Connect an Android device via USB and enable USB debugging." >&2
        echo "Alternatively, set ANDROID_SERIAL environment variable." >&2
        exit 1
    fi

    echo "$serial"
}
