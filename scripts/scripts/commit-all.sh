#!/bin/bash
# Commit and push all Vauchi repositories
# Usage: ./commit-all.sh "commit message"

set -e

# Configuration
WORKSPACE="${WORKSPACE:-$(cd "$(dirname "$0")/../.." && pwd)}"

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
Usage: $(basename "$0") [OPTIONS] "commit message"

Commit and push changes across all Vauchi repositories.

Options:
    -w, --workspace DIR    Workspace directory (default: parent of dev-tools)
    -n, --dry-run          Show what would be committed without committing
    -p, --no-push          Commit but don't push
    -h, --help             Show this help message

Examples:
    $(basename "$0") "Fix typo in docs"
    $(basename "$0") -n "Test commit"           # Dry run
    $(basename "$0") -p "Local commit only"     # No push
EOF
}

commit_repo() {
    local repo=$1
    local message=$2
    local dry_run=$3
    local no_push=$4
    local dir="$WORKSPACE/$repo"

    if [[ ! -d "$dir/.git" ]]; then
        return 1
    fi

    cd "$dir"

    # Check for changes
    if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
        echo "  No changes"
        return 0
    fi

    header "$repo"
    git status -s

    if [[ "$dry_run" == "true" ]]; then
        echo "  (dry run - would commit)"
        return 0
    fi

    # Stage and commit
    git add -A

    # Commit with co-author
    git commit -m "$message

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>" || {
        warn "Nothing to commit in $repo"
        return 0
    }

    # Push unless disabled
    if [[ "$no_push" != "true" ]]; then
        git push || {
            error "Failed to push $repo"
            return 1
        }
        info "Pushed $repo"
    else
        info "Committed $repo (not pushed)"
    fi

    cd - > /dev/null
}

# Parse arguments
DRY_RUN=false
NO_PUSH=false
MESSAGE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--workspace)
            WORKSPACE="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -p|--no-push)
            NO_PUSH=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            MESSAGE="$1"
            shift
            ;;
    esac
done

# Validate
if [[ -z "$MESSAGE" ]]; then
    error "Commit message required"
    usage
    exit 1
fi

if [[ ! -d "$WORKSPACE" ]]; then
    error "Workspace not found: $WORKSPACE"
    exit 1
fi

# Find all git repos
info "Workspace: $WORKSPACE"
info "Message: $MESSAGE"
[[ "$DRY_RUN" == "true" ]] && info "Mode: DRY RUN"
[[ "$NO_PUSH" == "true" ]] && info "Mode: NO PUSH"
echo ""

REPOS=()
for dir in "$WORKSPACE"/*/; do
    if [[ -d "${dir}.git" ]]; then
        REPOS+=("$(basename "$dir")")
    fi
done

if [[ ${#REPOS[@]} -eq 0 ]]; then
    error "No git repositories found"
    exit 1
fi

# Process each repo
COMMITTED=0
FAILED=0

for repo in "${REPOS[@]}"; do
    if commit_repo "$repo" "$MESSAGE" "$DRY_RUN" "$NO_PUSH"; then
        ((COMMITTED++))
    else
        ((FAILED++))
    fi
    echo ""
done

# Summary
echo ""
info "Done: $COMMITTED repos processed, $FAILED failed"
