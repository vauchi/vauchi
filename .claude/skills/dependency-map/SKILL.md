---
name: dependency-map
description: Cross-repo dependency graph, git vs path overrides, version pinning strategy, and mobile binding consumption. Use when modifying Cargo.toml, updating dependencies, or debugging build issues.
model: haiku
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi Dependency Map

## Core Dependency Graph

```
vauchi-core (standalone, no workspace deps)
    ↑ git dep (branch = "main")
    ├── cli/
    ├── tui/
    └── desktop/  (+ features = ["content-updates"])

vauchi-core (path dep)
    ↑
    ├── vauchi-mobile  (sibling in core/ workspace, forces network-rustls)
    └── e2e/           (path deps to both core and relay)

relay/ — INDEPENDENT (no vauchi-core dependency)
```

## Rust Repos: Git Dependencies

All downstream repos use:

```toml
vauchi-core = { git = "https://gitlab.com/vauchi/core.git", branch = "main" }
```

| Repo | Depends On | Features |
|------|-----------|----------|
| `cli/` | vauchi-core | (default) |
| `tui/` | vauchi-core | (default) |
| `desktop/src-tauri/` | vauchi-core | `content-updates` |
| `e2e/` | vauchi-core (path), vauchi-relay (path) | — |
| `relay/` | **Nothing** (independent) | — |

## Local Path Overrides (.cargo/config.toml)

For local development, repos patch git deps to sibling paths:

```toml
# Pattern used in tui/, e2e/
[patch."https://gitlab.com/vauchi/core.git"]
vauchi-core = { path = "../core/vauchi-core" }
```

### Override Locations

| Repo | Config Location | Path to Core |
|------|----------------|-------------|
| `tui/` | `tui/.cargo/config.toml` | `../core/vauchi-core` |
| `desktop/` | `desktop/src-tauri/.cargo/config.toml` | `../../core/vauchi-core` |
| `e2e/` | `e2e/.cargo/config.toml` | `../core/vauchi-core` + `../relay` |
| `cli/` | **None** — no local override | Uses git dep directly |
| `core/` | Build flags only (mold, NDK) | N/A (workspace member) |

**PITFALL**: Desktop config is nested at `src-tauri/.cargo/` — needs `../../` for relative path.

## Core Workspace Internal

```toml
# core/Cargo.toml
[workspace]
members = ["vauchi-core", "vauchi-mobile"]

# core/vauchi-mobile/Cargo.toml
vauchi-core = { path = "../vauchi-core", version = "0.1.0", default-features = false, features = ["network-rustls"] }
```

vauchi-mobile forces `network-rustls` (no OpenSSL for iOS/Android cross-compilation).

## Mobile Bindings Consumption

### iOS (SPM)

```swift
// ios/ depends on vauchi-mobile-swift via Swift Package Manager
// Package.resolved pins:
//   version: "0.1.5"
//   revision: "249089a01daa..."
//   repository: "https://gitlab.com/vauchi/vauchi-mobile-swift.git"
```

vauchi-mobile-swift's Package.swift downloads pre-built XCFramework:

```swift
.binaryTarget(
    name: "VauchiMobileFFI",
    url: "https://gitlab.com/api/v4/projects/vauchi%2Fcore/packages/generic/vauchi-mobile/{version}/VauchiMobileFFI.xcframework.zip",
    checksum: checksum
)
```

### Android (Gradle/Maven)

```kotlin
// android/app/build.gradle.kts
dependencies {
    implementation("com.vauchi:vauchi-mobile:0.1.2")
}
```

Published to GitLab Maven registry. JNA runtime required:

```kotlin
implementation("net.java.dev.jna:jna:5.14.0@aar")
```

## Desktop Frontend (npm)

```json
// desktop/ui/package.json
{
  "dependencies": {
    "solid-js": "^1.8.0",
    "qrcode": "^1.5.3"
  },
  "devDependencies": {
    "@tauri-apps/api": "^2.0.0",
    "vite": "^5.0.0",
    "typescript": "^5.0.0"
  }
}
```

Caret ranges (`^`) — allows minor/patch updates.

## Shared Locales

**Location**: `locales/` (own repo: `vauchi/locales`, cloned by `just setup`)

Files: `en.json`, `de.json`, `fr.json`, `es.json` (754 keys each)

Key format: `section.element` (e.g., `contacts.empty`, `action.save`)

Runtime loading: `i18n::init(resource_dir)` loads from JSON files at startup. `load_locale_from_bytes()` for CDN hot-reload.

Consumed by:
- **Desktop**: Bundled as Tauri resources (`desktop/src-tauri/resources/locales/`), loaded via `i18n::init()`
- **iOS/Android**: Via `init_locales(resource_dir)` UniFFI export + `get_available_locales()`
- **Core tests**: Uses `core/vauchi-core/locales/` copy

Validate: `just sync-locales`

## Version Pinning Strategy

| Repo Type | Strategy | Details |
|-----------|----------|---------|
| Rust downstream | `branch = "main"` | Always latest, no tag pinning |
| vauchi-mobile (internal) | `path = "../vauchi-core"` | Workspace sibling |
| iOS app | SPM version pin | `"0.1.5"` + commit SHA + checksum |
| Android app | Maven version pin | `"0.1.2"` |
| Distribution repos | Auto-updated by CI | Version injected via pipeline trigger |

**No semantic versioning tags on git deps** — Rust repos always track `main`.

## Common Pitfalls

1. **Editing `cli/Cargo.toml`** without a `.cargo/config.toml` — CI uses the git dep, local builds fetch from GitLab (no path override)
2. **Desktop path depth** — `src-tauri/.cargo/config.toml` needs `../../core/vauchi-core` (two levels up)
3. **Feature mismatch** — desktop enables `content-updates`, others don't. Don't assume it's available everywhere
4. **vauchi-mobile forces rustls** — if you add a dependency that pulls in OpenSSL, Android/iOS builds break
5. **E2E uses path deps** — unlike other repos, e2e directly references siblings. No git fetching
6. **Relay is independent** — don't try to add vauchi-core as a dependency to relay
