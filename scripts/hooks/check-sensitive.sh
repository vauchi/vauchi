#!/usr/bin/env bash
# Pre-commit hook: Check for sensitive content in public directories
#
# This hook prevents accidental commits of:
# - API tokens and secrets
# - Private keys
# - Server IPs and hostnames
# - Content marked as confidential

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Directories to scan (public directories only)
PUBLIC_DIRS="docs scripts assets website core cli tui desktop relay e2e features android ios"

# Patterns that indicate sensitive content
SENSITIVE_PATTERNS=(
    # Tokens
    'glpat-[a-zA-Z0-9_-]{20,}'           # GitLab PAT
    'ghp_[a-zA-Z0-9]{36,}'               # GitHub PAT
    'sk-[a-zA-Z0-9]{32,}'                # OpenAI/Stripe keys
    'xox[baprs]-[a-zA-Z0-9-]+'           # Slack tokens

    # Private keys
    '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'

    # Markers
    'CONFIDENTIAL'
    'DO NOT SHARE'
    'INTERNAL ONLY'
    'SECRET[:=]'

    # Infrastructure (project-specific)
    'bold-hopper-vps'
    'fufadmin@'
)

# Files/patterns to ignore
IGNORE_PATTERNS=(
    'check-sensitive.sh'        # This file
    'VISIBILITY_POLICY.md'      # Policy doc with examples
    '*.example'                 # Example files
    'test_*.rs'                 # Test files
    '*_test.go'
    '*.test.ts'
)

# Build ignore regex
build_ignore_regex() {
    local regex=""
    for pattern in "${IGNORE_PATTERNS[@]}"; do
        if [[ -n "$regex" ]]; then
            regex="$regex|"
        fi
        # Convert glob to regex
        local converted="${pattern//\*/.*}"
        converted="${converted//\?/.}"
        regex="$regex($converted)"
    done
    echo "$regex"
}

IGNORE_REGEX=$(build_ignore_regex)

# Get staged files in public directories
get_staged_files() {
    local files=""
    for dir in $PUBLIC_DIRS; do
        if [[ -d "$dir" ]]; then
            staged=$(git diff --cached --name-only --diff-filter=ACM -- "$dir" 2>/dev/null || true)
            files="$files $staged"
        fi
    done
    echo "$files"
}

# Check a file for sensitive patterns
check_file() {
    local file="$1"
    local found=0

    # Skip if file matches ignore pattern
    if [[ "$file" =~ $IGNORE_REGEX ]]; then
        return 0
    fi

    # Skip binary files
    if file "$file" | grep -q "binary"; then
        return 0
    fi

    for pattern in "${SENSITIVE_PATTERNS[@]}"; do
        if grep -qE "$pattern" "$file" 2>/dev/null; then
            if [[ $found -eq 0 ]]; then
                echo -e "${RED}SENSITIVE CONTENT DETECTED${NC} in $file:"
                found=1
            fi
            grep -nE "$pattern" "$file" 2>/dev/null | head -3 | while read -r line; do
                echo -e "  ${YELLOW}$line${NC}"
            done
        fi
    done

    return $found
}

main() {
    local exit_code=0
    local files
    files=$(get_staged_files)

    if [[ -z "${files// }" ]]; then
        exit 0
    fi

    for file in $files; do
        if [[ -f "$file" ]]; then
            if ! check_file "$file"; then
                exit_code=1
            fi
        fi
    done

    if [[ $exit_code -ne 0 ]]; then
        echo ""
        echo -e "${RED}Commit blocked.${NC} Sensitive content detected."
        echo ""
        echo "Options:"
        echo "  1. Move sensitive content to _private/"
        echo "  2. Add file to .sensitive-ignore (if false positive)"
        echo "  3. Use --no-verify to bypass (not recommended)"
        echo ""
        echo "See VISIBILITY_POLICY.md for guidelines."
    fi

    exit $exit_code
}

main
