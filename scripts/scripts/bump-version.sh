#!/bin/bash
# Bump version across all components
# Usage: ./bump-version.sh 0.2.0
#
# Updates:
# - All Cargo.toml files in code/
# - Android versionName in build.gradle.kts
# - iOS CFBundleShortVersionString in Info.plist

set -e

if [[ -z "$1" ]]; then
    echo "Usage: $0 <new-version>"
    echo "Example: $0 0.2.0"
    exit 1
fi

NEW_VERSION="$1"

# Validate version format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Error: Invalid version format. Use semantic versioning (e.g., 0.2.0, 1.0.0-beta.1)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Bumping version to $NEW_VERSION"
echo "=============================="

# ============================================================
# Update Rust Cargo.toml files
# ============================================================
echo ""
echo "Updating Rust crates..."

CARGO_FILES=$(find "$ROOT_DIR/code" -name "Cargo.toml" -not -path "*/target/*")

for file in $CARGO_FILES; do
    if grep -q '^version = ' "$file"; then
        # Check if this is a workspace member (has [package] section)
        if grep -q '^\[package\]' "$file"; then
            # Use portable sed syntax
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/^version = \"[^\"]*\"/version = \"$NEW_VERSION\"/" "$file"
            else
                sed -i "s/^version = \"[^\"]*\"/version = \"$NEW_VERSION\"/" "$file"
            fi
            echo "  Updated: $file"
        fi
    fi
done

# ============================================================
# Update Android version
# ============================================================
echo ""
echo "Updating Android..."

ANDROID_GRADLE="$ROOT_DIR/android/app/build.gradle.kts"
if [[ -f "$ANDROID_GRADLE" ]]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/versionName = \"[^\"]*\"/versionName = \"$NEW_VERSION\"/" "$ANDROID_GRADLE"
    else
        sed -i "s/versionName = \"[^\"]*\"/versionName = \"$NEW_VERSION\"/" "$ANDROID_GRADLE"
    fi
    echo "  Updated: $ANDROID_GRADLE"

    # Also increment versionCode
    CURRENT_CODE=$(grep -oP 'versionCode = \K\d+' "$ANDROID_GRADLE" 2>/dev/null || echo "1")
    NEW_CODE=$((CURRENT_CODE + 1))
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/versionCode = [0-9]*/versionCode = $NEW_CODE/" "$ANDROID_GRADLE"
    else
        sed -i "s/versionCode = [0-9]*/versionCode = $NEW_CODE/" "$ANDROID_GRADLE"
    fi
    echo "  Incremented versionCode to $NEW_CODE"
else
    echo "  (Android gradle file not found, skipping)"
fi

# ============================================================
# Update iOS version
# ============================================================
echo ""
echo "Updating iOS..."

IOS_PLIST="$ROOT_DIR/ios/Vauchi/Info.plist"
if [[ -f "$IOS_PLIST" ]]; then
    if command -v /usr/libexec/PlistBuddy &> /dev/null; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$IOS_PLIST"
        echo "  Updated: $IOS_PLIST"

        # Increment build number
        CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$IOS_PLIST" 2>/dev/null || echo "1")
        NEW_BUILD=$((CURRENT_BUILD + 1))
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$IOS_PLIST"
        echo "  Incremented CFBundleVersion to $NEW_BUILD"
    else
        echo "  (PlistBuddy not available, iOS update skipped)"
    fi
else
    echo "  (iOS plist not found, skipping)"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "=============================="
echo "Version bump complete!"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff"
echo "  2. Update CHANGELOG.md"
echo "  3. Commit: git commit -am 'Bump version to $NEW_VERSION'"
echo "  4. Tag: git tag -a v$NEW_VERSION -m 'Release v$NEW_VERSION'"
echo "  5. Push: git push && git push --tags"
