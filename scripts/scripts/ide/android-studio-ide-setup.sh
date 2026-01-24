#!/bin/bash
# Android Studio IDE Setup Script for Vauchi
#
# This script prepares the development environment for building Vauchi
# with Android Studio. Run this once after cloning the repository.
#
# Usage:
#   ./_dev-tools/scripts/ide/android-studio-ide-setup.sh
#
# Prerequisites:
#   - Rust toolchain (https://rustup.rs)
#   - Android Studio with NDK installed via SDK Manager
#
# After running this script:
#   1. Open the android/ folder in Android Studio
#   2. Sync Gradle
#   3. Build and run

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CODE_DIR="$WORKSPACE_ROOT/core"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "\n${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

echo -e "${YELLOW}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         Vauchi Android Studio Setup                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check Rust
print_step "Checking Rust installation..."
if ! command -v rustc &> /dev/null; then
    print_error "Rust is not installed"
    echo "Install Rust from https://rustup.rs"
    exit 1
fi
RUST_VERSION=$(rustc --version)
print_success "Rust found: $RUST_VERSION"

# Check cargo
if ! command -v cargo &> /dev/null; then
    print_error "Cargo is not installed"
    exit 1
fi
print_success "Cargo found"

# Check rustup
if ! command -v rustup &> /dev/null; then
    print_warning "rustup not found - cannot install Android targets automatically"
else
    print_success "rustup found"
fi

# Install Android targets
print_step "Installing Android Rust targets..."
TARGETS_NEEDED=false
for target in aarch64-linux-android x86_64-linux-android; do
    if ! rustup target list --installed | grep -q "^$target$"; then
        TARGETS_NEEDED=true
        echo "Installing $target..."
        rustup target add $target
    else
        print_success "$target already installed"
    fi
done

# Check for Android NDK
print_step "Checking Android NDK..."

find_ndk() {
    local ndk_path="$1"
    if [ -d "$ndk_path/toolchains/llvm/prebuilt/linux-x86_64/bin" ]; then
        echo "$ndk_path"
        return 0
    fi
    return 1
}

NDK_HOME=""
if [ -n "$ANDROID_NDK_HOME" ] && find_ndk "$ANDROID_NDK_HOME" >/dev/null 2>&1; then
    NDK_HOME="$ANDROID_NDK_HOME"
elif [ -d "$HOME/Android/Sdk/ndk" ]; then
    for ndk in $(ls -d "$HOME/Android/Sdk/ndk/"* 2>/dev/null | sort -V -r); do
        if find_ndk "$ndk" >/dev/null 2>&1; then
            NDK_HOME="$ndk"
            break
        fi
    done
fi

if [ -z "$NDK_HOME" ]; then
    print_error "Android NDK not found"
    echo ""
    echo "Please install the NDK via Android Studio:"
    echo "  1. Open Android Studio"
    echo "  2. Go to Tools > SDK Manager"
    echo "  3. Select 'SDK Tools' tab"
    echo "  4. Check 'NDK (Side by side)' and click Apply"
    echo ""
    echo "Or set ANDROID_NDK_HOME environment variable if NDK is installed elsewhere."
    exit 1
fi
print_success "Android NDK found: $NDK_HOME"

# Build native libraries
print_step "Building native libraries..."
echo "This may take a few minutes on first build..."
cd "$CODE_DIR"
if ./scripts/build-android.sh; then
    print_success "Native libraries built successfully"
else
    print_error "Native library build failed"
    exit 1
fi

# Verify outputs
print_step "Verifying build outputs..."

ANDROID_DIR="$WORKSPACE_ROOT/android"
JNILIBS_DIR="$ANDROID_DIR/app/src/main/jniLibs"
KOTLIN_DIR="$ANDROID_DIR/app/src/main/kotlin/uniffi/vauchi_mobile"

if [ -f "$JNILIBS_DIR/arm64-v8a/libvauchi_mobile.so" ]; then
    print_success "ARM64 library: $(ls -lh "$JNILIBS_DIR/arm64-v8a/libvauchi_mobile.so" | awk '{print $5}')"
else
    print_error "ARM64 library not found"
fi

if [ -f "$JNILIBS_DIR/x86_64/libvauchi_mobile.so" ]; then
    print_success "x86_64 library: $(ls -lh "$JNILIBS_DIR/x86_64/libvauchi_mobile.so" | awk '{print $5}')"
else
    print_error "x86_64 library not found"
fi

if [ -f "$KOTLIN_DIR/vauchi_mobile.kt" ]; then
    print_success "Kotlin bindings generated"
else
    print_error "Kotlin bindings not found"
fi

# Summary
echo ""
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                  Setup Complete!                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "Next steps:"
echo "  1. Open Android Studio"
echo "  2. Select 'Open' and navigate to: $ANDROID_DIR"
echo "  3. Wait for Gradle sync to complete"
echo "  4. Click 'Run' to build and deploy to device/emulator"
echo ""
echo "To rebuild native libraries after Rust code changes:"
echo "  cd $CODE_DIR && ./scripts/build-android.sh"
echo ""
echo "For development tips, see: $ANDROID_DIR/CLAUDE.md"
echo ""