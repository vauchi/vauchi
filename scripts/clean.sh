#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[clean]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[clean]${NC} $1"; }

remove_if_exists() {
    local path="$1"
    if [[ -e "$path" ]]; then
        log_info "Removing $path"
        rm -rf "$path"
    fi
}

# Rust artifacts (code/)
log_info "Cleaning Rust artifacts..."
remove_if_exists "$WORKSPACE_ROOT/code/target"

# Android artifacts
log_info "Cleaning Android artifacts..."
remove_if_exists "$WORKSPACE_ROOT/android/.gradle"
remove_if_exists "$WORKSPACE_ROOT/android/build"
remove_if_exists "$WORKSPACE_ROOT/android/app/build"
remove_if_exists "$WORKSPACE_ROOT/android/.idea"
remove_if_exists "$WORKSPACE_ROOT/android/local.properties"

# iOS artifacts
log_info "Cleaning iOS artifacts..."
remove_if_exists "$WORKSPACE_ROOT/ios/.build"
remove_if_exists "$WORKSPACE_ROOT/ios/DerivedData"
remove_if_exists "$WORKSPACE_ROOT/ios/Frameworks"
remove_if_exists "$WORKSPACE_ROOT/ios/Vauchi.xcodeproj/xcuserdata"
remove_if_exists "$WORKSPACE_ROOT/ios/Vauchi.xcodeproj/project.xcworkspace/xcuserdata"
find "$WORKSPACE_ROOT/ios" -name "*.xcuserstate" -delete 2>/dev/null || true
find "$WORKSPACE_ROOT/ios" -name ".DS_Store" -delete 2>/dev/null || true

# Desktop (Tauri) artifacts
log_info "Cleaning desktop artifacts..."
remove_if_exists "$WORKSPACE_ROOT/code/vauchi-desktop/target"
remove_if_exists "$WORKSPACE_ROOT/code/vauchi-desktop/node_modules"
remove_if_exists "$WORKSPACE_ROOT/code/vauchi-desktop/dist"

# Website artifacts
log_info "Cleaning website artifacts..."
remove_if_exists "$WORKSPACE_ROOT/website/node_modules"
remove_if_exists "$WORKSPACE_ROOT/website/dist"
remove_if_exists "$WORKSPACE_ROOT/website/.cache"

# General cleanup
log_info "Cleaning general artifacts..."
find "$WORKSPACE_ROOT" -name ".DS_Store" -delete 2>/dev/null || true
find "$WORKSPACE_ROOT" -name "*.pyc" -delete 2>/dev/null || true
find "$WORKSPACE_ROOT" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

log_info "Done!"
