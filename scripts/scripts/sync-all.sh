#!/bin/bash
# Sync all Vauchi repositories
# Pulls latest changes from all repos in the workspace

set -e

# Configuration
WORKSPACE="${WORKSPACE:-$(pwd)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
header() { echo -e "${BLUE}=== $1 ===${NC}"; }

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Sync all Vauchi repositories by pulling latest changes.

Options:
    -w, --workspace DIR    Workspace directory (default: current directory)
    -f, --fetch-only       Only fetch, don't pull
    -s, --status           Show status of all repos
    -h, --help             Show this help message

Examples:
    $(basename "$0")                          # Pull all repos in current directory
    $(basename "$0") -w ~/dev/vauchi          # Pull repos in specified workspace
    $(basename "$0") -s                       # Show status only
EOF
}

sync_repo() {
    local repo=$1
    local mode=$2
    local dir="$WORKSPACE/$repo"

    if [[ ! -d "$dir/.git" ]]; then
        return 1
    fi

    header "$repo"
    cd "$dir"

    case $mode in
        status)
            git status -sb
            ;;
        fetch)
            git fetch --all --prune
            git status -sb
            ;;
        pull)
            # Check for uncommitted changes
            if ! git diff --quiet || ! git diff --cached --quiet; then
                warn "Uncommitted changes, fetching only"
                git fetch --all --prune
                git status -sb
            else
                git pull --rebase 2>/dev/null || git pull
            fi
            ;;
    esac

    echo ""
    cd - > /dev/null
}

# Parse arguments
MODE="pull"

while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        -f|--fetch-only)
            MODE="fetch"
            shift
            ;;
        -s|--status)
            MODE="status"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Verify workspace
if [[ ! -d "$WORKSPACE" ]]; then
    error "Workspace not found: $WORKSPACE"
    exit 1
fi

# Find all git repos in workspace
info "Syncing repos in: $WORKSPACE"
info "Mode: $MODE"
echo ""

REPOS=()
for dir in "$WORKSPACE"/*/; do
    if [[ -d "${dir}.git" ]]; then
        REPOS+=("$(basename "$dir")")
    fi
done

if [[ ${#REPOS[@]} -eq 0 ]]; then
    error "No git repositories found in workspace"
    exit 1
fi

# Sync each repo
for repo in "${REPOS[@]}"; do
    sync_repo "$repo" "$MODE" || warn "Skipping $repo (not a git repo)"
done

info "Sync complete!"
