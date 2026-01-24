#!/bin/bash
# Setup Vauchi development workspace
# Clones all Vauchi repositories as siblings in a workspace directory

set -e

# Configuration
GITLAB_BASE="${GITLAB_BASE:-git@gitlab.com:vauchi}"
WORKSPACE="${WORKSPACE:-$(pwd)/vauchi-workspace}"

# Repository list (public repos - mirrored to GitHub)
PUBLIC_REPOS=(
    "core"
    "relay"
    "cli"
    "tui"
    "desktop"
    "e2e"
    "features"
    "android"
    "ios"
    "dev-tools"
)

# Private repos (require access, cloned with _ prefix)
PRIVATE_REPOS=(
    "assets"
    "docs"
    "website"
    "strategy"
    "infra"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Setup Vauchi development workspace by cloning all repositories.

Options:
    -w, --workspace DIR    Workspace directory (default: ./vauchi-workspace)
    -a, --all              Include private repos (infra, strategy)
    -p, --public-only      Only clone public repos (default)
    -h, --help             Show this help message

Examples:
    $(basename "$0")                          # Clone public repos to ./vauchi-workspace
    $(basename "$0") -w ~/dev/vauchi          # Clone to custom directory
    $(basename "$0") -a                       # Include private repos
EOF
}

clone_repo() {
    local repo=$1
    local local_name=${2:-$repo}
    local dest="$WORKSPACE/$local_name"

    if [[ -d "$dest" ]]; then
        warn "$local_name already exists, skipping"
        return 0
    fi

    info "Cloning $repo → $local_name..."
    if git clone "$GITLAB_BASE/$repo.git" "$dest" 2>/dev/null; then
        info "Cloned $local_name successfully"
    else
        warn "Failed to clone $repo (may not have access or repo doesn't exist)"
        return 1
    fi
}

# Parse arguments
INCLUDE_PRIVATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        -a|--all)
            INCLUDE_PRIVATE=true
            shift
            ;;
        -p|--public-only)
            INCLUDE_PRIVATE=false
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

# Main
info "Setting up Vauchi workspace at: $WORKSPACE"
mkdir -p "$WORKSPACE"

# Clone public repos
info "Cloning public repositories..."
for repo in "${PUBLIC_REPOS[@]}"; do
    clone_repo "$repo" || true
done

# Clone private repos if requested (with _ prefix)
if [[ "$INCLUDE_PRIVATE" == "true" ]]; then
    info "Cloning private repositories (with _ prefix)..."
    for repo in "${PRIVATE_REPOS[@]}"; do
        clone_repo "$repo" "_$repo" || true
    done
fi

# Create workspace root symlinks
info "Creating workspace symlinks..."
if [[ -d "$WORKSPACE/_docs" ]]; then
    # CLAUDE.md -> _docs/MAIN-CLAUDE.md
    if [[ -f "$WORKSPACE/_docs/MAIN-CLAUDE.md" ]]; then
        ln -sf _docs/MAIN-CLAUDE.md "$WORKSPACE/CLAUDE.md"
        info "Created CLAUDE.md symlink"
    fi
    # CONTRIBUTING.md -> _docs/CONTRIBUTING.md
    if [[ -f "$WORKSPACE/_docs/CONTRIBUTING.md" ]]; then
        ln -sf _docs/CONTRIBUTING.md "$WORKSPACE/CONTRIBUTING.md"
        info "Created CONTRIBUTING.md symlink"
    fi
fi

# Create tmp and cache directories
mkdir -p "$WORKSPACE/tmp" "$WORKSPACE/cache"
echo '*
!.gitignore' > "$WORKSPACE/tmp/.gitignore"
echo '*
!.gitignore' > "$WORKSPACE/cache/.gitignore"

# Summary
echo ""
info "Workspace setup complete!"
echo ""
echo "Workspace structure:"
ls -1 "$WORKSPACE" 2>/dev/null | sed 's/^/  /'
echo ""
echo "Next steps:"
echo "  cd $WORKSPACE/code"
echo "  cargo build"
echo ""
echo "See _dev-tools/README.md for more workflows."
