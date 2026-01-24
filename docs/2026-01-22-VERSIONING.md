# Versioning Strategy

This document describes the versioning strategy for the Vauchi project.

## Overview

Vauchi follows [Semantic Versioning 2.0.0](https://semver.org/) (SemVer) for all components:

```
MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]
```

- **MAJOR**: Breaking changes to public API or protocol
- **MINOR**: New features, backward-compatible
- **PATCH**: Bug fixes, backward-compatible
- **PRERELEASE**: Optional (e.g., `alpha.1`, `beta.2`, `rc.1`)
- **BUILD**: Optional build metadata

## Component Versioning

### Rust Crates (`code/`)

All Rust crates in the workspace share a synchronized version:

| Crate | Type | Notes |
|-------|------|-------|
| `vauchi-core` | Library | Core version, drives all others |
| `vauchi-relay` | Binary | Matches core |
| `vauchi-cli` | Binary | Matches core |
| `vauchi-tui` | Binary | Matches core |
| `vauchi-mobile` | Library | Matches core |
| `vauchi-desktop` | Application | Matches core |

**Version Bump Process:**

The recommended way is to use changesets (see [Changesets](#changesets) section):
```bash
just changeset  # Add a changeset describing your change
```

For manual version bumps without changesets:
```bash
# Update all Cargo.toml files
./dev-tools/scripts/bump-version.sh 0.2.0

# Or use cargo-release (if installed)
cd code && cargo release --workspace 0.2.0
```

### Mobile Apps

| Platform | Version Format | Notes |
|----------|---------------|-------|
| Android | `versionCode` + `versionName` | versionCode increments, versionName matches core |
| iOS | `CFBundleVersion` + `CFBundleShortVersionString` | Build number + version string |

**Android (`android/app/build.gradle.kts`):**
```kotlin
versionCode = 10      // Increment each release
versionName = "0.1.0" // Match vauchi-core
```

**iOS (`ios/Vauchi/Info.plist`):**
```xml
<key>CFBundleShortVersionString</key>
<string>0.1.0</string>  <!-- Match vauchi-core -->
<key>CFBundleVersion</key>
<string>10</string>     <!-- Increment each build -->
```

## Version Synchronization

### When to Bump Versions

| Change Type | Version Bump | Example |
|-------------|--------------|---------|
| Breaking API change | MAJOR | Removing a public function |
| Protocol change (incompatible) | MAJOR | Changing message format |
| New feature | MINOR | Adding contact groups |
| New crate export | MINOR | Exposing new module |
| Bug fix | PATCH | Fixing encryption edge case |
| Performance improvement | PATCH | Optimizing ratchet |
| Documentation only | NONE | README updates |
| CI/tooling changes | NONE | GitHub Actions updates |

### Breaking Changes

A change is breaking if it:
- Removes or renames a public API
- Changes the signature of a public function
- Changes serialization format in incompatible ways
- Changes protocol message format incompatibly
- Changes minimum supported Rust version (MSRV)
- Changes mobile SDK API in incompatible ways

### Protocol Versioning

The Double Ratchet and X3DH protocol implementations include version fields:

```rust
// In message headers
pub struct RatchetMessage {
    pub protocol_version: u8,  // Increment on incompatible changes
    // ...
}
```

Protocol version changes require:
1. MAJOR version bump
2. Migration guide in release notes
3. Backward compatibility period (if possible)

## Changesets

We use [Changesets](https://github.com/changesets/changesets) to manage version bumps and generate changelogs automatically.

### Adding a Changeset

When you make a change that should be released, add a changeset:

```bash
# Using just
just changeset

# Or using npx directly
npx changeset add
```

This will prompt you to:
1. Select which packages are affected
2. Choose the type of change (major/minor/patch)
3. Write a summary of the change

### Changeset Workflow

1. **Developer adds a changeset** with their PR
2. **PR is merged** to main
3. **CI creates a "Version Packages" PR** that:
   - Consumes all pending changesets
   - Bumps versions in package.json and Cargo.toml
   - Updates CHANGELOG.md
4. **Maintainer merges** the Version Packages PR
5. **CI creates a release** with the new tag

### Example Changeset

A changeset file (`.changeset/cool-feature.md`) looks like:

```markdown
---
"vauchi-desktop-ui": minor
---

Add contact groups feature with drag-and-drop organization
```

### CI Integration

- **GitHub Actions**: Uses `changesets/action` to automatically create Version PRs
- **GitLab CI**: Uses custom jobs to check for changesets and version packages

See `.github/workflows/release.yml` or `.gitlab-ci.yml` for details.

## Release Process

### Pre-release Versions

```
0.1.0-alpha.1  → Early development
0.1.0-beta.1   → Feature complete, testing
0.1.0-rc.1     → Release candidate
0.1.0          → Stable release
```

### Release Checklist

1. **Prepare**
   - [ ] All tests passing
   - [ ] CHANGELOG.md updated
   - [ ] Version bumped in all Cargo.toml
   - [ ] Mobile app versions updated
   - [ ] Documentation updated

2. **Tag & Release**
   ```bash
   git tag -a v0.1.0 -m "Release v0.1.0"
   git push origin v0.1.0
   ```

3. **Publish**
   - [ ] GitHub/GitLab release created
   - [ ] Mobile apps submitted to stores
   - [ ] Crates published to crates.io (if public)

### CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/):

```markdown
## [0.2.0] - 2025-02-01

### Added
- Contact groups feature (#123)

### Changed
- Improved sync performance by 50%

### Fixed
- Race condition in device linking (#456)

### Security
- Updated ring to 0.17.8

### Breaking
- Renamed `Contact.name` to `Contact.display_name`
```

## Compatibility Matrix

### Supported Versions

| Component | Supported Versions | EOL Policy |
|-----------|-------------------|------------|
| vauchi-core | Latest 2 MINOR | 6 months after next MINOR |
| Mobile apps | Latest 2 MINOR | 6 months after next MINOR |
| Protocol | Latest 2 MAJOR | 12 months after next MAJOR |

### Cross-Version Compatibility

| Client A | Client B | Compatible? |
|----------|----------|-------------|
| 0.1.x | 0.1.x | Yes |
| 0.1.x | 0.2.x | Yes (minor) |
| 0.x.x | 1.x.x | Migration required |

## Tooling

### Changesets CLI

```bash
# Add a changeset for your changes
just changeset
# or: npx changeset add

# Check status of pending changesets
just changeset-status
# or: npx changeset status

# Version packages (usually done by CI)
just changeset-version
# or: npm run changeset:version
```

### Automated Version Checks

The CI pipeline includes:
- Changeset presence check on PRs
- Automatic Version Packages PR creation
- Version consistency check across Cargo.toml files
- Tag format validation

### Version Bump Script

```bash
#!/bin/bash
# dev-tools/scripts/bump-version.sh
NEW_VERSION="$1"

# Update all Cargo.toml
find code -name "Cargo.toml" -exec sed -i "s/^version = .*/version = \"$NEW_VERSION\"/" {} \;

# Update Android
sed -i "s/versionName = .*/versionName = \"$NEW_VERSION\"/" android/app/build.gradle.kts

# Update iOS (requires different sed syntax on macOS)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" ios/Vauchi/Info.plist
```

## FAQ

**Q: When do I need to bump the version?**
A: Whenever making changes that affect users. Internal refactoring or CI changes typically don't require version bumps.

**Q: Who can release versions?**
A: Project maintainers. Releases are created through GitHub/GitLab with signed tags.

**Q: How do I know if my change is breaking?**
A: If you change any public API, serialization format, or protocol behavior, assume it's breaking. When in doubt, bump MAJOR.
