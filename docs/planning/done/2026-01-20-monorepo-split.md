# Proposal: Split Code Monorepo into Separate Repositories

## Goal

Extract components from the `code/` monorepo into dedicated repositories, rename `code/` to `core/`, resulting in a cleaner multi-repo architecture.

## Current State

```
vauchi/
├── code/                    # Rust monorepo (Cargo workspace)
│   ├── Cargo.toml           # Workspace root
│   ├── vauchi-core/         # Core library (crypto, protocols, data)
│   ├── vauchi-relay/        # WebSocket relay server
│   ├── vauchi-cli/          # CLI for testing
│   ├── vauchi-tui/          # Terminal UI
│   ├── vauchi-desktop/      # Tauri + SolidJS
│   ├── vauchi-mobile/       # UniFFI bindings (iOS/Android)
│   └── vauchi-e2e-tests/    # E2E testing infrastructure
├── docs/
├── features/
├── ios/
├── android/
├── dev-tools/
└── infra/
```

## Proposed Structure

```
vauchi/
├── core/                    # RENAMED from code/, keeps core + mobile
│   ├── Cargo.toml           # Workspace with core + mobile
│   ├── vauchi-core/         # Core library
│   └── vauchi-mobile/       # UniFFI bindings (stays with core)
├── relay/                   # NEW REPO: vauchi-relay
│   ├── Cargo.toml
│   └── src/
├── cli/                     # NEW REPO: vauchi-cli
│   ├── Cargo.toml
│   └── src/
├── tui/                     # NEW REPO: vauchi-tui
│   ├── Cargo.toml
│   └── src/
├── desktop/                 # NEW REPO: vauchi-desktop
│   ├── Cargo.toml
│   ├── src-tauri/
│   └── ui/
├── e2e/                     # NEW REPO: vauchi-e2e-tests
│   ├── Cargo.toml
│   ├── src/
│   └── tests/
├── docs/
├── features/
├── ios/
├── android/
├── dev-tools/
└── infra/
```

## Dependency Graph

```
                    ┌─────────────────────┐
                    │        core/        │
                    │  ┌───────────────┐  │
                    │  │  vauchi-core  │  │
                    │  └───────┬───────┘  │
                    │          │          │
                    │  ┌───────▼───────┐  │
                    │  │ vauchi-mobile │──┼──► ios/, android/
                    │  └───────────────┘  │
                    └──────────┬──────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
        ▼                      ▼                      ▼
   ┌─────────┐           ┌─────────┐           ┌─────────┐
   │  relay  │           │   cli   │           │ desktop │
   └─────────┘           └────┬────┘           └─────────┘
                              │
                              ▼
                         ┌─────────┐
                         │   tui   │
                         └─────────┘

                         ┌─────────┐
                         │   e2e   │  (depends on cli, relay)
                         └─────────┘
```

## GitLab Repository Structure

| Current | New | GitLab Path |
|---------|-----|-------------|
| `code/` (all) | `core/` | `gitlab.com/vauchi/core` (core + mobile) |
| - | `relay/` | `gitlab.com/vauchi/relay` |
| - | `cli/` | `gitlab.com/vauchi/cli` |
| - | `tui/` | `gitlab.com/vauchi/tui` |
| - | `desktop/` | `gitlab.com/vauchi/desktop` |
| - | `e2e/` | `gitlab.com/vauchi/e2e` |

## Benefits

| Benefit | Description |
|---------|-------------|
| **Separation of Concerns** | Each component has clear boundaries |
| **Independent Releases** | Relay can release without desktop changes |
| **Smaller CI Times** | Only affected repos run CI |
| **Focused PRs** | Changes scoped to specific component |
| **Clearer Ownership** | Contributors can focus on one area |
| **Dependency Clarity** | Explicit cross-repo dependencies |

## Challenges

| Challenge | Mitigation |
|-----------|------------|
| **Cross-repo Dependencies** | Use crates.io or git dependencies |
| **CI Complexity** | Downstream CI triggers on core changes |
| **Local Development** | Workspace overlay or path overrides |
| **Version Coordination** | Semantic versioning + compatibility matrix |
| **More Repos to Manage** | Automation via `just` commands |

## Implementation Plan

### Phase 1: Preparation
1. Ensure all tests pass in current monorepo
2. Document all inter-crate dependencies
3. Create new GitLab repositories (empty)
4. Update `just setup` to clone new repos

### Phase 2: Extract Relay
1. Copy `code/vauchi-relay/` to new `relay/` repo
2. Update Cargo.toml to use git dependency for core
3. Set up CI/CD for relay repo
4. Verify relay builds and tests pass
5. Remove `vauchi-relay/` from code repo

### Phase 3: Extract CLI
1. Copy `code/vauchi-cli/` to new `cli/` repo
2. Update dependencies (core from git)
3. Set up CI/CD
4. Remove from code repo

### Phase 4: Extract TUI
1. Copy `code/vauchi-tui/` to new `tui/` repo
2. Update dependencies
3. Set up CI/CD
4. Remove from code repo

### Phase 5: Extract Desktop
1. Copy `code/vauchi-desktop/` to new `desktop/` repo
2. Update Rust dependencies
3. Keep Tauri + SolidJS structure
4. Set up CI/CD
5. Remove from code repo

### Phase 6: Extract E2E
1. Copy `code/vauchi-e2e-tests/` to new `e2e/` repo
2. Update dependencies (needs cli, relay paths)
3. Set up CI/CD
4. Remove from code repo

### Phase 7: Rename and Cleanup
1. Rename `code/` to `core/` (keeps vauchi-core + vauchi-mobile)
2. Update all references in main repo
3. Update `just` commands
4. Update documentation
5. Archive old `code` repo on GitLab

## Cargo.toml Changes

### core/Cargo.toml (workspace with core + mobile)
```toml
[workspace]
members = ["vauchi-core", "vauchi-mobile"]
resolver = "2"

[workspace.package]
version = "0.1.0"
edition = "2021"
```

### relay/Cargo.toml
```toml
[package]
name = "vauchi-relay"
version = "0.1.0"

[dependencies]
# Strict version pinning via git tag
vauchi-core = { git = "https://gitlab.com/vauchi/core.git", tag = "v0.1.0" }
```

### Local Development Override
```toml
# .cargo/config.toml (in each repo)
[patch."https://gitlab.com/vauchi/core.git"]
vauchi-core = { path = "../core" }
```

## Just Commands Updates

```just
# Setup all repos
setup:
    git clone git@gitlab.com:vauchi/vauchi.git
    cd vauchi && git clone git@gitlab.com:vauchi/core.git
    cd vauchi && git clone git@gitlab.com:vauchi/relay.git
    cd vauchi && git clone git@gitlab.com:vauchi/cli.git
    cd vauchi && git clone git@gitlab.com:vauchi/tui.git
    cd vauchi && git clone git@gitlab.com:vauchi/desktop.git
    cd vauchi && git clone git@gitlab.com:vauchi/e2e.git
    # ... existing repos (docs, features, ios, android, dev-tools, infra)

# Build all
build:
    cd core && cargo build          # builds core + mobile
    cd relay && cargo build
    cd cli && cargo build
    cd tui && cargo build
    cd desktop && cargo tauri build

# Test all
test:
    cd core && cargo test           # tests core + mobile
    cd relay && cargo test
    cd cli && cargo test
    cd tui && cargo test
    cd e2e && cargo test --ignored
```

## CI/CD Strategy

### Core Repo CI
```yaml
# On push to core (includes mobile)
- Run core + mobile tests
- Build UniFFI bindings
- Trigger downstream repos (relay, cli, tui, desktop, e2e)
```

### Downstream Repo CI
```yaml
# On push to relay/cli/tui/etc
- Pull latest core (or specified version)
- Run tests
- Build artifacts
```

## Migration Checklist

- [ ] Create GitLab repos: core, relay, cli, tui, desktop, e2e
- [ ] Extract relay with working CI
- [ ] Extract cli with working CI
- [ ] Extract tui with working CI
- [ ] Extract desktop with working CI
- [ ] Extract e2e with working CI
- [ ] Rename code → core (keeping vauchi-core + vauchi-mobile)
- [ ] Update main repo references
- [ ] Update just commands
- [ ] Update documentation
- [ ] Verify all builds work
- [ ] Verify local development workflow
- [ ] Archive old code repo

## Decisions

1. **crates.io publishing?** - **NO** - Use git dependencies only
2. **Version pinning?** - **YES** - Strict version pinning via git tags/commits
3. **mobile placement?** - **YES** - Mobile stays with core (just UniFFI bindings)

## Alternatives Considered

### Keep Monorepo
- **Pro**: Simpler dependency management, atomic commits
- **Con**: All CI runs on every change, harder to release independently

### Git Submodules
- **Pro**: Single checkout, version pinning
- **Con**: Submodule complexity, merge conflicts

### Cargo Workspace with Multiple Repos
- **Pro**: Local path dependencies work
- **Con**: Workspace can't span multiple git repos easily

## Recommendation

Proceed with full split. The benefits of independent releases and focused CI outweigh the management overhead, especially as the project grows.

Start with **relay** extraction as it has the simplest dependency (only core) and is independently deployable.
