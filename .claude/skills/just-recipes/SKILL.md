---
name: just-recipes
description: Complete reference of all just commands across the vauchi workspace. Use when running builds, tests, deployments, or any just recipe.
model: haiku
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi Just Recipes

Aliases: `b` = build, `t` = test, `c` = check, `f` = fmt

## Repo Targeting

All daily commands accept an optional `[repo]` argument:

- **Omit** → auto-detect from pwd (inside sub-repo) or run all (from workspace root)
- **Explicit name** → `just test core`, `just lint relay`, `just check desktop`
- **`all`** → `just test all` runs across all applicable repos
- **`desktop`** → expands to both `desktop-rust` and `desktop-ui`

**Valid repo names:** `core`, `cli`, `relay`, `tui`, `e2e`, `desktop` (or `desktop-rust`/`desktop-ui`), `android`, `ios`, `docs`, `locales`, `themes`, `features`, `website`, `scripts`

**Toolchain dispatch per repo:**

| Repo | Toolchain | build | test | fmt | lint | fix |
|------|-----------|-------|------|-----|------|-----|
| core, cli, relay, tui, e2e, desktop-rust | rust | cargo build | cargo nextest | cargo fmt | cargo clippy | cargo fmt + clippy --fix |
| desktop-ui | npm | npm run build | playwright | prettier | eslint + stylelint | prettier |
| android | gradle | gradlew assembleDebug | gradlew test | — | gradlew lint | — |
| ios | xcode | xcodebuild build | xcodebuild test | swiftformat | swiftlint + swiftformat --lint | swiftformat + swiftlint --fix |
| docs | mkdocs | mkdocs build --strict | mkdocs build --strict | — | markdownlint | — |
| locales, themes | python | — | — | — | python3 validate.py | — |
| features | gherkin | — | — | — | advisory only | — |
| scripts | shell | — | — | — | shellcheck | — |
| website | html | — | — | — | htmlhint | — |

## Daily (Most Used)

| Recipe | Purpose |
|--------|---------|
| `just check [repo]` | Run fmt-check → lint → test |
| `just build [repo]` | Build (dispatches per toolchain) |
| `just test [repo]` | Run tests (dispatches per toolchain) |
| `just fmt [repo]` | Format code |
| `just fmt-check [repo]` | Check formatting (no changes) |
| `just lint [repo]` | Run lints |
| `just fix [repo]` | Auto-fix formatting + lints |
| `just commit` | Interactive commit across repos |

## Extended

| Recipe | Purpose |
|--------|---------|
| `just test-crate <name>` | Test specific crate in core workspace |
| `just build-release` | Release build (core) |
| `just audit [repo]` | Security audit (Rust repos: cargo audit + cargo deny) |
| `just watch` | Watch + test (core) |
| `just coverage` | Coverage report (core) |
| `just docs` | Generate Rust docs |
| `just install-hooks` | Install git hooks across repos |

## GitLab (`just gitlab ...`)

All recipes require `glab` auth. Error immediately if not authenticated.

### MR Operations

| Recipe | Purpose |
|--------|---------|
| `just gitlab mr-list [repo]` | List open merge requests |
| `just gitlab mr-view <id> [repo]` | View MR details |
| `just gitlab mr-create [repo]` | Create MR from current branch (pushes + fills from commits) |
| `just gitlab mr-approve <id> [repo]` | Approve MR |
| `just gitlab mr-merge <id> [repo]` | Merge MR |
| `just gitlab mr-close <id> [repo]` | Close MR |

### Pipeline Operations

| Recipe | Purpose |
|--------|---------|
| `just gitlab pipeline-status [repo]` | Pipeline status for current branch |
| `just gitlab pipeline-list [repo]` | List recent pipelines |
| `just gitlab pipeline-jobs <id> [repo]` | List jobs in a pipeline |
| `just gitlab pipeline-log <job_id> [repo]` | View job log output |
| `just gitlab pipeline-retry <id> [repo]` | Retry failed pipeline |
| `just gitlab pipeline-cancel <id> [repo]` | Cancel running pipeline |

### Issue Operations

| Recipe | Purpose |
|--------|---------|
| `just gitlab issue-list [repo]` | List open issues |
| `just gitlab issue-view <id> [repo]` | View issue details |
| `just gitlab issue-create <title> [repo]` | Create issue |
| `just gitlab issue-close <id> [repo]` | Close issue |

## Git Multi-Repo (`just git ...`)

| Recipe | Purpose |
|--------|---------|
| `just git status` | Show status across all repos (default) |
| `just git main` | Stash + checkout main + pull (all repos) |
| `just git fetch` | Fetch all repos |
| `just git branches` | Show branches across repos |
| `just git cleanup` | Preview merged branch cleanup (dry run) |
| `just git cleanup run` | Delete merged branches + prune stale refs |
| `just git pull-all` | Pull all repos (with rebase) |
| `just git push-all` | Push repos with unpushed commits |
| `just git checkout-main` | Checkout main in all repos |
| `just git stash-clear` | Clear stashes across all repos |

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
├── just/gitlab.just      # GitLab MR/pipeline/issue ops (mod)
├── just/apps.just        # App runners
├── just/setup.just       # Setup + clean
├── just/mobile.just      # Mobile builds
├── just/e2e.just         # E2E testing
├── just/deploy.just      # Deployment
├── just/runners.just     # CI runners
└── just/dev.just         # Dev multi-instance
```
