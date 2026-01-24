#!/bin/bash
# Common variables and utilities for dev scripts
#
# Source this file at the beginning of dev scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Determine workspace root and code directory
# This file is in _dev-tools/scripts/dev/
_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$_COMMON_DIR/../../.." && pwd)"
CODE_DIR="$PROJECT_ROOT/code"

# Directories for test data and caches
# ./tmp - ephemeral test data, cleaned before test runs
# ./cache - persistent caches (AVDs, simulator data), cleaned by cleanup command
TMP_DIR="$PROJECT_ROOT/tmp"
CACHE_DIR="$PROJECT_ROOT/cache"

# Subdirectories
ANDROID_CACHE_DIR="$CACHE_DIR/android"
ANDROID_AVD_DIR="$ANDROID_CACHE_DIR/avd"
IOS_CACHE_DIR="$CACHE_DIR/ios"
IOS_DERIVED_DATA_DIR="$IOS_CACHE_DIR/DerivedData"

# Test data directories (in tmp, cleaned before runs)
TEST_DATA_DIR="$TMP_DIR/test-data"

# Platform directories
ANDROID_DIR="$PROJECT_ROOT/android"
IOS_DIR="$PROJECT_ROOT/ios"

# Ensure directories exist
ensure_dirs() {
    mkdir -p "$TMP_DIR" "$CACHE_DIR"
    mkdir -p "$ANDROID_AVD_DIR" "$IOS_DERIVED_DATA_DIR"
    mkdir -p "$TEST_DATA_DIR"
}

# Clean tmp directory (call before test runs)
clean_tmp() {
    if [ -d "$TMP_DIR" ]; then
        echo "Cleaning tmp directory..."
        rm -rf "$TMP_DIR"/*
        # Preserve .gitignore
        echo '# Ignore everything in tmp except this file
*
!.gitignore' > "$TMP_DIR/.gitignore"
    fi
    mkdir -p "$TEST_DATA_DIR"
}

# Clean cache directory (call from cleanup commands)
clean_cache() {
    if [ -d "$CACHE_DIR" ]; then
        echo "Cleaning cache directory..."
        rm -rf "$CACHE_DIR"/*
        # Preserve .gitignore
        echo '# Ignore everything in cache except this file
*
!.gitignore' > "$CACHE_DIR/.gitignore"
    fi
    mkdir -p "$ANDROID_AVD_DIR" "$IOS_DERIVED_DATA_DIR"
}

# Clean everything
clean_all() {
    clean_tmp
    clean_cache
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored status
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

print_info() { print_status "$BLUE" "$1"; }
print_success() { print_status "$GREEN" "$1"; }
print_warning() { print_status "$YELLOW" "$1"; }
print_error() { print_status "$RED" "$1"; }

# OS Detection
detect_os() {
    case "$(uname -s)" in
        Darwin)
            echo "macos"
            ;;
        Linux)
            echo "linux"
            ;;
        MINGW*|MSYS*|CYGWIN*|Windows_NT)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

OS_TYPE=$(detect_os)
IS_MACOS=$([[ "$OS_TYPE" == "macos" ]] && echo true || echo false)
IS_LINUX=$([[ "$OS_TYPE" == "linux" ]] && echo true || echo false)
IS_WINDOWS=$([[ "$OS_TYPE" == "windows" ]] && echo true || echo false)

# Get local IP address for network connections
get_local_ip() {
    case "$OS_TYPE" in
        macos)
            # Get primary interface IP (en0 for Wi-Fi, en1 for Ethernet)
            ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1"
            ;;
        linux)
            hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1 2>/dev/null | awk '{print $7}' || echo "127.0.0.1"
            ;;
        windows)
            # WSL or Git Bash
            ip route get 1 2>/dev/null | awk '{print $7}' || hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1"
            ;;
        *)
            echo "127.0.0.1"
            ;;
    esac
}

# Print connection info for remote development
print_connection_info() {
    local service_name="$1"
    local port="$2"
    local local_ip=$(get_local_ip)

    echo ""
    print_info "═══════════════════════════════════════════════════════════════"
    print_info "  Remote Connection Info for $service_name"
    print_info "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  Local IP Address: $local_ip"
    if [ -n "$port" ]; then
        echo "  Port: $port"
        echo "  Full Address: $local_ip:$port"
    fi
    echo ""
    echo "  Ensure your firewall allows incoming connections on this port."
    echo ""
    print_info "═══════════════════════════════════════════════════════════════"
    echo ""
}
