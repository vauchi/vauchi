#!/bin/bash
# E2E Testing - Common Utilities
#
# Shared functions and variables for E2E orchestration.
# Source this file at the beginning of e2e scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

set -e

# ═══════════════════════════════════════════════════════════════
# Path Setup
# ═══════════════════════════════════════════════════════════════

# Determine script locations
E2E_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_DIR="$(cd "$E2E_LIB_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$E2E_DIR/../../.." && pwd)"

# Load configuration
if [ -f "$E2E_DIR/config.env" ]; then
    source "$E2E_DIR/config.env"
fi

# Directories
TMP_DIR="$PROJECT_ROOT/tmp"
CACHE_DIR="$PROJECT_ROOT/cache"
SCREENSHOTS_DIR="$PROJECT_ROOT/${E2E_SCREENSHOTS_DIR:-tmp/e2e-screenshots}"
LOGS_DIR="$PROJECT_ROOT/${E2E_LOGS_DIR:-tmp/e2e-logs}"

# ═══════════════════════════════════════════════════════════════
# Colors
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ═══════════════════════════════════════════════════════════════
# Logging Functions
# ═══════════════════════════════════════════════════════════════

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "${CYAN}▸${NC} $*"; }

log_header() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $*${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

log_subheader() {
    echo ""
    echo -e "${BOLD}─── $* ───${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# Directory Management
# ═══════════════════════════════════════════════════════════════

ensure_dirs() {
    mkdir -p "$SCREENSHOTS_DIR" "$LOGS_DIR"
}

clean_screenshots() {
    rm -rf "$SCREENSHOTS_DIR"/*
    mkdir -p "$SCREENSHOTS_DIR"
}

clean_logs() {
    rm -rf "$LOGS_DIR"/*
    mkdir -p "$LOGS_DIR"
}

# ═══════════════════════════════════════════════════════════════
# SSH Utilities (for macOS VM)
# ═══════════════════════════════════════════════════════════════

# Run command on macOS VM via SSH
ssh_mac() {
    ssh -p "${MACOS_SSH_PORT:-2222}" \
        -o "ConnectTimeout=5" \
        -o "StrictHostKeyChecking=no" \
        -o "BatchMode=yes" \
        "${MACOS_SSH_USER:-user}@${MACOS_SSH_HOST:-localhost}" \
        "$@"
}

# Copy file from macOS VM
scp_from_mac() {
    local remote_path="$1"
    local local_path="$2"
    scp -P "${MACOS_SSH_PORT:-2222}" \
        -o "ConnectTimeout=5" \
        -o "StrictHostKeyChecking=no" \
        "${MACOS_SSH_USER:-user}@${MACOS_SSH_HOST:-localhost}:${remote_path}" \
        "$local_path"
}

# Copy file to macOS VM
scp_to_mac() {
    local local_path="$1"
    local remote_path="$2"
    scp -P "${MACOS_SSH_PORT:-2222}" \
        -o "ConnectTimeout=5" \
        -o "StrictHostKeyChecking=no" \
        "$local_path" \
        "${MACOS_SSH_USER:-user}@${MACOS_SSH_HOST:-localhost}:${remote_path}"
}

# Check if macOS VM is reachable
check_ssh_mac() {
    if ssh_mac "echo ok" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Process Management
# ═══════════════════════════════════════════════════════════════

# Array to track background processes
declare -a BG_PIDS=()

# Register a background process for cleanup
register_bg_pid() {
    BG_PIDS+=("$1")
}

# Kill all registered background processes
cleanup_bg_processes() {
    for pid in "${BG_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    wait 2>/dev/null || true
}

# Setup cleanup trap
setup_cleanup_trap() {
    trap 'cleanup_bg_processes; exit' EXIT INT TERM
}

# ═══════════════════════════════════════════════════════════════
# Timestamp Utilities
# ═══════════════════════════════════════════════════════════════

timestamp() {
    date "+%Y%m%d_%H%M%S"
}

timestamp_iso() {
    date -Iseconds
}

# ═══════════════════════════════════════════════════════════════
# QR Code Utilities
# ═══════════════════════════════════════════════════════════════

# Decode QR code from image (requires zbar-tools)
decode_qr() {
    local image_path="$1"

    if ! command -v zbarimg &>/dev/null; then
        log_error "zbarimg not found. Install zbar-tools: apt install zbar-tools"
        return 1
    fi

    zbarimg -q --raw "$image_path" 2>/dev/null
}

# Check if QR tools are available
check_qr_tools() {
    if command -v zbarimg &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Network Utilities
# ═══════════════════════════════════════════════════════════════

# Get local IP address
get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || \
    ip route get 1 2>/dev/null | awk '{print $7}' || \
    echo "127.0.0.1"
}

# Check if a port is in use
port_in_use() {
    local port="$1"
    if ss -ltn | grep -q ":$port "; then
        return 0
    else
        return 1
    fi
}

# Wait for port to become available
wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if nc -z "$host" "$port" 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    return 1
}

# ═══════════════════════════════════════════════════════════════
# Status Formatting
# ═══════════════════════════════════════════════════════════════

status_ok() {
    echo -e "${GREEN}✓${NC} $*"
}

status_fail() {
    echo -e "${RED}✗${NC} $*"
}

status_warn() {
    echo -e "${YELLOW}!${NC} $*"
}

status_pending() {
    echo -e "${BLUE}○${NC} $*"
}

# ═══════════════════════════════════════════════════════════════
# Confirmation Prompt
# ═══════════════════════════════════════════════════════════════

confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-y}"

    local yn
    if [ "$default" = "y" ]; then
        read -p "$prompt [Y/n] " yn
        yn="${yn:-y}"
    else
        read -p "$prompt [y/N] " yn
        yn="${yn:-n}"
    fi

    case "$yn" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}
