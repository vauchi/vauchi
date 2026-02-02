---
name: just-recipes
description: Complete reference of all just commands across the vauchi workspace. Use when running builds, tests, deployments, or any just recipe.
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi Just Recipes

Aliases: `b` = build, `t` = test, `c` = check, `f` = fmt

## Daily (Most Used)

| Recipe | What It Runs | Purpose |
|--------|-------------|---------|
| `just check` | `fmt-check` + `lint` + `test` | Run all checks |
| `just build` | `cd core && cargo build --workspace` | Build core workspace |
| `just test` | `cd core && cargo test --workspace` | Run all tests |
| `just fmt` | `cd core && cargo fmt --all` | Format code |
| `just lint` | `cd core && cargo clippy --workspace -- -D warnings` | Clippy lints |
| `just commit` | `./scripts/scripts/commit-interactive.sh` | Interactive commit across repos |

## Extended

| Recipe | What It Runs | Purpose |
|--------|-------------|---------|
| `just test-crate <name>` | `cd core && cargo test -p <name>` | Test specific crate |
| `just build-release` | `cd core && cargo build --workspace --release` | Release build |
| `just audit` | `cargo audit && cargo deny check` | Security audit |
| `just fix` | `cargo fmt --all && cargo clippy --fix --allow-dirty` | Auto-fix lints |
| `just watch` | `cargo watch -x "test --workspace"` | Watch + test |
| `just coverage` | `cargo llvm-cov --workspace --html` | Coverage report |
| `just docs` | `cargo doc --workspace --no-deps --open` | Generate docs |
| `just install-hooks` | Copy scripts/hooks/ to .git/hooks/ | Git hooks |

## Git Multi-Repo (`just git ...`)

| Recipe | Purpose |
|--------|---------|
| `just git status` | Show status across all repos (default) |
| `just git main` | Stash + checkout main + pull (all repos) |
| `just git fetch` | Fetch all repos |
| `just git branches` | Show branches across repos |
| `just git clean-branches` | Delete merged branches |
| `just git pull-all` | Pull all repos (with rebase) |
| `just git push-all` | Push repos with unpushed commits |
| `just git checkout-main` | Checkout main in all repos |

## Apps

| Recipe | Purpose |
|--------|---------|
| `just run cli <args>` | Run CLI |
| `just run tui` | Run TUI |
| `just run desktop` | Run desktop (release) |
| `just run desktop-dev` | Run desktop dev mode |
| `just run relay` | Run relay server |
| `just run android` | Build + install Android |
| `just run ios` | Build + install iOS |
| `just relay` | `cd relay && cargo run` |
| `just tui` | `cd tui && cargo run` |
| `just desktop-dev` | `cd desktop && cargo tauri dev` |

## Setup

| Recipe | Purpose |
|--------|---------|
| `just setup` | Clone all repos + create tmp/cache dirs |
| `just install-dev-deps` | Install toolchain (brew, rustup, cargo tools, targets) |
| `just clean` | Remove all build artifacts + node_modules + caches |
| `just clean-rust` | Remove only Rust target directories |

## Mobile

| Recipe | Purpose |
|--------|---------|
| `just bindings` | Generate UniFFI mobile bindings |
| `just build-android [mode]` | Build Android native libs (debug/release) |
| `just build-ios [mode]` | Build iOS framework (macOS only) |
| `just android [mode]` | Build Android APK |
| `just check-ios` | iOS: xcodegen + build + test |
| `just check-android` | Android: lint + build + test |
| `just check-mobile` | Both iOS + Android checks |

## E2E Testing

### Core E2E

| Recipe | Purpose |
|--------|---------|
| `just e2e` | List available E2E tests |
| `just e2e-run <name>` | Run E2E test (use 'all' for everything) |
| `just e2e-smoke` | Fast smoke tests |
| `just e2e-release` | Full E2E suite |
| `just e2e-integration` | Integration tests only |
| `just e2e-coverage` | Show coverage against Gherkin features |

### YAML Scenarios

| Recipe | Purpose |
|--------|---------|
| `just e2e-yaml <name>` | Run YAML scenario |
| `just e2e-yaml-list` | List YAML scenarios |
| `just e2e-yaml-manual <name>` | Show manual instructions |

### Cross-Platform E2E

| Recipe | Purpose |
|--------|---------|
| `just e2e-status` | Check E2E status (all platforms) |
| `just e2e-setup` | Show E2E setup guide |
| `just e2e-scenarios` | List available scenarios |
| `just e2e-scenario [name]` | Run scenario (or 'all') |
| `just e2e-scenario-all` | Run all + show report |
| `just e2e-report` | Show latest report |
| `just e2e-clean` | Clean test data |
| `just e2e-map` | Show infrastructure diagram |

### Per-Platform E2E

| Recipe | Purpose |
|--------|---------|
| `just e2e-cli [args]` | CLI instance command |
| `just e2e-cli-test [alice] [bob]` | CLI exchange test |
| `just e2e-tui <instance>` | Launch TUI instance |
| `just e2e-tui-multi [instances]` | Launch multiple TUIs |
| `just e2e-desktop [instance]` | Launch desktop instance |
| `just e2e-desktop-dev [instance]` | Desktop dev mode |
| `just e2e-desktop-build` | Build desktop release |
| `just e2e-relay` | Start local TLS relay |
| `just e2e-relay-setup` | Setup local CA |
| `just e2e-deploy` | Deploy to all mobile devices |
| `just e2e-deploy-ios` | Deploy iOS to simulator |
| `just e2e-deploy-android` | Deploy Android APK |
| `just e2e-test-mobile` | Interactive mobile test |
| `just e2e-screenshot` | Take device screenshots |
| `just e2e-logs` | Collect device logs |

## Deployment

| Recipe | Purpose |
|--------|---------|
| `just validate` | Pre-flight checks |
| `just deploy` | Deploy relay + landing (full) |
| `just deploy-skip-push` | Deploy existing images only |
| `just deploy-version <V>` | Deploy specific version |
| `just relay-logs` | Show relay logs |
| `just deploy-mail` | Sync mail config |
| `just deploy-mail-dry` | Preview mail changes |
| `just deploy-all` | Deploy everything |

### Mail Management

| Recipe | Purpose |
|--------|---------|
| `just mail-logs` | Mail server logs |
| `just mail-status` | Mail server status |
| `just mail-add-user <email>` | Add mail user |
| `just mail-update-password <email>` | Update password |
| `just mail-list-users` | List users |

## CI Runners

| Recipe | Purpose |
|--------|---------|
| `just runners-start` | Start all (Linux VM + macOS VM + docker-local) |
| `just runners-stop` | Stop all runners |
| `just runners-status` | Show status |
| `just vm-linux-start/stop/ssh` | Linux VM lifecycle |
| `just vm-macos-start/stop/ssh` | macOS VM lifecycle |
| `just docker-runner-start/stop/status/logs/restart` | Docker runner |

## Dev (Multi-Instance)

| Recipe | Purpose |
|--------|---------|
| `just dev-relay` | Start local relay (memory storage) |
| `just dev-relay-tls` | Local relay with TLS |
| `just dev-relay-tls-setup` | Setup local CA |
| `just dev-cli [args]` | CLI with isolated data |
| `just dev-tui <instance>` | TUI with isolated data |
| `just dev-clean` | Clean test data |

## Tools

| Recipe | Purpose |
|--------|---------|
| `just sync-locales` | Validate locale files |
| `just sync-locales-strict` | Strict locale validation (CI) |
| `just vrt-gallery` | Generate VRT gallery |
| `just tell-me-about <topic>` | Explore codebase with local LLM |
| `just help` | Show full help menu |

## Justfile Structure

```
justfile                  # Root (imports below)
├── just/git.just         # Git multi-repo (mod)
├── just/apps.just        # App runners
├── just/setup.just       # Setup + clean
├── just/mobile.just      # Mobile builds
├── just/e2e.just         # E2E testing
├── just/deploy.just      # Deployment
├── just/runners.just     # CI runners
└── just/dev.just         # Dev multi-instance
```
