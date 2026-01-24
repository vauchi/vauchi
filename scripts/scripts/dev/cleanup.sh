#!/bin/bash
# Master Cleanup Script
#
# Cleans up all test data, caches, and build artifacts.
# Use this to reset the development environment to a clean state.

set -e

# Source common variables
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  tmp         Clean tmp directory (test data)"
    echo "  cache       Clean cache directory (AVDs, DerivedData)"
    echo "  all         Clean both tmp and cache"
    echo "  android     Clean Android AVDs and emulator data"
    echo "  ios         Clean iOS simulator caches and DerivedData"
    echo "  status      Show current disk usage of tmp and cache"
    echo ""
    echo "Directories:"
    echo "  tmp:   $TMP_DIR"
    echo "  cache: $CACHE_DIR"
    echo ""
    echo "Examples:"
    echo "  $0 tmp        # Clean test data before a fresh test run"
    echo "  $0 cache      # Clean AVDs and build caches"
    echo "  $0 all        # Full cleanup"
    echo "  $0 status     # Check disk usage"
    exit 1
}

show_status() {
    echo "=== Disk Usage Status ==="
    echo ""

    if [ -d "$TMP_DIR" ]; then
        local tmp_size=$(du -sh "$TMP_DIR" 2>/dev/null | awk '{print $1}')
        echo "tmp/:   $tmp_size"
        if [ -d "$TEST_DATA_DIR" ]; then
            local test_size=$(du -sh "$TEST_DATA_DIR" 2>/dev/null | awk '{print $1}')
            echo "  test-data/: $test_size"
        fi
    else
        echo "tmp/:   (not created)"
    fi

    echo ""

    if [ -d "$CACHE_DIR" ]; then
        local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | awk '{print $1}')
        echo "cache/: $cache_size"
        if [ -d "$ANDROID_CACHE_DIR" ]; then
            local android_size=$(du -sh "$ANDROID_CACHE_DIR" 2>/dev/null | awk '{print $1}')
            echo "  android/: $android_size"
        fi
        if [ -d "$IOS_CACHE_DIR" ]; then
            local ios_size=$(du -sh "$IOS_CACHE_DIR" 2>/dev/null | awk '{print $1}')
            echo "  ios/: $ios_size"
        fi
    else
        echo "cache/: (not created)"
    fi

    echo ""
    echo "=== System Disk ==="
    df -h / | tail -1 | awk '{print "Available: " $4 " (" $5 " used)"}'
}

clean_android() {
    echo "Cleaning Android caches..."

    # Stop emulators first
    if command -v adb &>/dev/null; then
        local emulators=$(adb devices 2>/dev/null | grep "emulator-" | awk '{print $1}')
        for serial in $emulators; do
            echo "Stopping $serial..."
            adb -s "$serial" emu kill 2>/dev/null || true
        done
    fi

    # Clean cache/android
    if [ -d "$ANDROID_CACHE_DIR" ]; then
        rm -rf "$ANDROID_CACHE_DIR"/*
        mkdir -p "$ANDROID_AVD_DIR"
        echo "Cleaned: $ANDROID_CACHE_DIR"
    fi

    # Clean legacy tmp/android
    if [ -d "$TMP_DIR/android" ]; then
        rm -rf "$TMP_DIR/android"
        echo "Cleaned legacy: $TMP_DIR/android"
    fi
}

clean_ios() {
    echo "Cleaning iOS caches..."

    # Stop simulators
    if command -v xcrun &>/dev/null; then
        xcrun simctl shutdown all 2>/dev/null || true
    fi

    # Clean cache/ios
    if [ -d "$IOS_CACHE_DIR" ]; then
        rm -rf "$IOS_CACHE_DIR"/*
        mkdir -p "$IOS_DERIVED_DATA_DIR"
        echo "Cleaned: $IOS_CACHE_DIR"
    fi

    # Clean legacy tmp/ios
    if [ -d "$TMP_DIR/ios" ]; then
        rm -rf "$TMP_DIR/ios"
        echo "Cleaned legacy: $TMP_DIR/ios"
    fi

    # Clean legacy ios/.build
    if [ -d "$IOS_DIR/.build" ]; then
        rm -rf "$IOS_DIR/.build"
        echo "Cleaned legacy: $IOS_DIR/.build"
    fi
}

if [ -z "$1" ]; then
    usage
fi

case "$1" in
    tmp)
        echo "Cleaning tmp directory..."
        clean_tmp
        echo "Done."
        ;;
    cache)
        echo "Cleaning cache directory..."
        clean_cache
        echo "Done."
        ;;
    all)
        echo "Cleaning all directories..."
        clean_tmp
        clean_cache
        echo "Done."
        ;;
    android)
        clean_android
        echo "Done."
        ;;
    ios)
        clean_ios
        echo "Done."
        ;;
    status)
        show_status
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        echo ""
        usage
        ;;
esac
