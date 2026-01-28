<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Changesets

This project uses [Changesets](https://github.com/changesets/changesets) for version management and changelog generation.

## Quick Start

### Adding a Changeset

When you make a change that should be released, run:

```bash
npx changeset add
# or
just changeset
```

This will prompt you to:
1. Select which packages are affected
2. Choose the type of change (major/minor/patch)
3. Write a summary of the change

### Changeset Types

| Type | When to use |
|------|-------------|
| **major** | Breaking changes (API changes, protocol changes) |
| **minor** | New features, backward-compatible |
| **patch** | Bug fixes, performance improvements |

### Examples

**Bug fix:**
```bash
npx changeset add
# Select: vauchi-core
# Type: patch
# Summary: Fix race condition in device linking
```

**New feature:**
```bash
npx changeset add
# Select: vauchi-core, vauchi-mobile
# Type: minor
# Summary: Add contact groups feature
```

**Breaking change:**
```bash
npx changeset add
# Select: vauchi-core
# Type: major
# Summary: Change contact card serialization format
```

## CI Integration

The CI pipeline automatically:
1. Checks for changesets on PRs
2. Creates a "Version Packages" PR when changesets are merged to main
3. Publishes releases when the version PR is merged

## Manual Release

To manually release:

```bash
# Update versions based on changesets
npm run changeset:version

# Tag and publish (done by CI usually)
npm run changeset:publish
```

## Rust Crate Sync

Changesets primarily manages the npm packages, but we sync Rust crate versions automatically:

1. When `changeset version` runs, it updates package.json versions
2. A post-version script syncs those versions to Cargo.toml files
3. Android/iOS versions are also updated

See `_dev-tools/scripts/sync-rust-versions.mjs` for details.
