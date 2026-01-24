#!/usr/bin/env bash
# Validates that new/changed markdown files follow YYYY-MM-DD-<name>.md naming convention

set -euo pipefail

# Files exempt from the naming convention
EXCEPTIONS=(
    "README.md"
    "CLAUDE.md"
    "CONTRIBUTING.md"
    "roadmap.md"
)

# Directories exempt from naming convention (contents don't need date prefix)
EXEMPT_DIRS=(
    "diagrams"           # Numbered for ordering (01-xxx.md, 02-xxx.md)
    "problems"           # Problem artifacts (investigation.md, etc.) inside dated dirs
)

# Date pattern: YYYY-MM-DD-
DATE_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}-'

errors=0

is_exception() {
    local filename="$1"
    for exception in "${EXCEPTIONS[@]}"; do
        if [[ "$filename" == "$exception" ]]; then
            return 0
        fi
    done
    return 1
}

is_exempt_dir() {
    local filepath="$1"
    for dir in "${EXEMPT_DIRS[@]}"; do
        if [[ "$filepath" == *"/$dir/"* ]]; then
            return 0
        fi
    done
    return 1
}

check_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")

    # Skip non-markdown files
    if [[ ! "$filename" =~ \.md$ ]]; then
        return 0
    fi

    # Skip exceptions
    if is_exception "$filename"; then
        return 0
    fi

    # Skip files in exempt directories
    if is_exempt_dir "$filepath"; then
        return 0
    fi

    # Check if filename matches date prefix pattern
    if [[ ! "$filename" =~ $DATE_PATTERN ]]; then
        echo "ERROR: $filepath does not follow YYYY-MM-DD-<name>.md convention"
        return 1
    fi

    return 0
}

echo "Checking markdown file naming convention..."

# Determine which files to check
if [[ -n "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}" ]]; then
    # In MR pipeline: check files changed vs target branch
    echo "Checking files changed in merge request..."
    git fetch origin "$CI_MERGE_REQUEST_TARGET_BRANCH_NAME" --depth=1 2>/dev/null || true
    changed_files=$(git diff --name-only --diff-filter=A "origin/$CI_MERGE_REQUEST_TARGET_BRANCH_NAME"...HEAD -- '*.md' 2>/dev/null || echo "")
elif [[ -n "${CI_COMMIT_BEFORE_SHA:-}" && "$CI_COMMIT_BEFORE_SHA" != "0000000000000000000000000000000000000000" ]]; then
    # In push pipeline: check files changed in push
    echo "Checking files changed in push..."
    changed_files=$(git diff --name-only --diff-filter=A "$CI_COMMIT_BEFORE_SHA"...HEAD -- '*.md' 2>/dev/null || echo "")
else
    # Fallback: check files added in last commit
    echo "Checking files added in last commit..."
    changed_files=$(git diff --name-only --diff-filter=A HEAD~1...HEAD -- '*.md' 2>/dev/null || echo "")
fi

if [[ -z "$changed_files" ]]; then
    echo "No new markdown files to check."
    exit 0
fi

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if ! check_file "$file"; then
        ((errors++))
    fi
done <<< "$changed_files"

if [[ $errors -gt 0 ]]; then
    echo ""
    echo "Found $errors file(s) with invalid naming."
    echo "All new markdown files must be named: YYYY-MM-DD-<name>.md"
    echo "Exceptions: ${EXCEPTIONS[*]}"
    exit 1
fi

echo "All new files follow the naming convention."
exit 0
