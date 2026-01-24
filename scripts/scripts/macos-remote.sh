#!/bin/bash
# macOS Remote Development Script
# Connects to remote macOS for iOS development

set -e

# Configuration - edit these or set as environment variables
MACOS_VM_IP="${MACOS_VM_IP:-192.168.200.230}"
MACOS_VM_USER="${MACOS_VM_USER:-user}"
MACOS_VM_PORT="${MACOS_VM_PORT:-22}"
PROJECT_PATH="${PROJECT_PATH:-/Volumes/Workspace/vauchi}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
  echo -e "${BLUE}macOS Remote Development Script${NC}"
  echo ""
  echo "Usage: $0 <command> [args]"
  echo ""
  echo "Commands:"
  echo "  ssh              Open SSH session to macOS VM"
  echo "  status           Check VM connectivity"
  echo "  simulator        Launch iOS Simulator"
  echo "  simulator-list   List available simulators"
  echo "  simulator-boot <name|udid>  Boot specific simulator"
  echo "  xcode            Open Xcode with project"
  echo "  stop             Stop Simulator and Xcode"
  echo "  sync             Rsync project to macOS"
  echo "  build-ios        Build iOS (Rust libs + bindings + XCFramework)"
  echo "  run <cmd>        Run arbitrary command on macOS"
  echo ""
  echo "Environment variables:"
  echo "  MACOS_VM_IP      VM IP address (current: $MACOS_VM_IP)"
  echo "  MACOS_VM_USER    SSH username (current: $MACOS_VM_USER)"
  echo "  MACOS_VM_PORT    SSH port (current: $MACOS_VM_PORT)"
  echo "  PROJECT_PATH     Remote project path (current: $PROJECT_PATH)"
  echo ""
  echo "Setup:"
  echo "  1. Edit this script or export environment variables"
  echo "  2. Ensure SSH key is copied: ssh-copy-id \$MACOS_VM_USER@\$MACOS_VM_IP"
  echo "  3. Test with: $0 status"
}

ssh_cmd() {
  ssh -p "$MACOS_VM_PORT" "$MACOS_VM_USER@$MACOS_VM_IP" "$@"
}

check_config() {
  if [[ "$MACOS_VM_IP" == "192.168.122.XXX" ]] || [[ "$MACOS_VM_USER" == "your_user" ]]; then
    echo -e "${RED}Error: Please configure MACOS_VM_IP and MACOS_VM_USER${NC}"
    echo ""
    echo "Edit this script or set environment variables:"
    echo "  export MACOS_VM_IP=192.168.122.xxx"
    echo "  export MACOS_VM_USER=yourusername"
    exit 1
  fi
}

cmd_status() {
  echo -e "${BLUE}Checking macOS connectivity...${NC}"
  if ssh_cmd "echo 'Connected successfully'" 2>/dev/null; then
    echo -e "${GREEN}✓ SSH connection working${NC}"
    echo ""
    echo -e "${BLUE}System info:${NC}"
    ssh_cmd "sw_vers && echo '' && xcrun simctl list devices booted 2>/dev/null | head -5 || echo 'No simulators running'"
  else
    echo -e "${RED}✗ Cannot connect to $MACOS_VM_USER@$MACOS_VM_IP:$MACOS_VM_PORT${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Ensure macOS is running and accessible"
    echo "  2. Enable SSH on Mac: System Preferences > Sharing > Remote Login"
    echo "  3. Copy SSH key: ssh-copy-id $MACOS_VM_USER@$MACOS_VM_IP"
    exit 1
  fi
}

cmd_ssh() {
  echo -e "${BLUE}Connecting to macOS...${NC}"
  ssh -p "$MACOS_VM_PORT" "$MACOS_VM_USER@$MACOS_VM_IP"
}

cmd_simulator() {
  echo -e "${BLUE}Launching iOS Simulator...${NC}"
  ssh_cmd "open -a Simulator"
  echo -e "${GREEN}✓ Simulator launched${NC}"
}

cmd_simulator_list() {
  echo -e "${BLUE}Available simulators:${NC}"
  ssh_cmd "xcrun simctl list devices available"
}

cmd_simulator_boot() {
  local device="$1"
  if [[ -z "$device" ]]; then
    echo -e "${RED}Error: Please specify simulator name or UDID${NC}"
    echo "Usage: $0 simulator-boot 'iPhone 15'"
    exit 1
  fi
  echo -e "${BLUE}Booting simulator: $device${NC}"
  ssh_cmd "xcrun simctl boot '$device' 2>/dev/null || echo 'Already booted or not found'"
  ssh_cmd "open -a Simulator"
  echo -e "${GREEN}✓ Done${NC}"
}

cmd_xcode() {
  echo -e "${BLUE}Opening Xcode with project...${NC}"
  ssh_cmd "cd $PROJECT_PATH/ios && open -a Xcode *.xcodeproj 2>/dev/null || open -a Xcode *.xcworkspace 2>/dev/null || echo 'No Xcode project found'"
}

cmd_stop() {
  echo -e "${BLUE}Stopping Simulator and Xcode...${NC}"
  ssh_cmd "xcrun simctl shutdown all 2>/dev/null; killall Simulator Xcode 2>/dev/null || true"
  echo -e "${GREEN}✓ Simulator and Xcode closed${NC}"
}

cmd_sync() {
  echo -e "${BLUE}Syncing project to macOS...${NC}"
  local local_path
  local_path="$(cd "$(dirname "$0")/../.." && pwd)"

  rsync -avz --progress \
    --exclude '.git' \
    --exclude 'target' \
    --exclude 'node_modules' \
    --exclude '.build' \
    --exclude 'DerivedData' \
    -e "ssh -p $MACOS_VM_PORT" \
    "$local_path/" \
    "$MACOS_VM_USER@$MACOS_VM_IP:$PROJECT_PATH/"

  echo -e "${GREEN}✓ Sync complete${NC}"
}

cmd_build_ios() {
  echo -e "${BLUE}Building iOS project on remote macOS...${NC}"
  ssh_cmd "cd $PROJECT_PATH && ./ios/build-ios.sh"
}

cmd_run() {
  ssh_cmd "$@"
}

# Main
if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

check_config

case "$1" in
ssh)
  cmd_ssh
  ;;
status)
  cmd_status
  ;;
simulator)
  cmd_simulator
  ;;
simulator-list)
  cmd_simulator_list
  ;;
simulator-boot)
  cmd_simulator_boot "$2"
  ;;
xcode)
  cmd_xcode
  ;;
stop)
  cmd_stop
  ;;
sync)
  cmd_sync
  ;;
build-ios)
  cmd_build_ios
  ;;
run)
  shift
  cmd_run "$@"
  ;;
-h | --help | help)
  usage
  ;;
*)
  echo -e "${RED}Unknown command: $1${NC}"
  usage
  exit 1
  ;;
esac
