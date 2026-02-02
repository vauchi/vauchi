---
name: ci-pipeline
description: GitLab CI structure, shared templates, jobs per repo, common failure modes, and pipeline debugging. Use when investigating CI failures or modifying pipelines.
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi CI Pipeline Reference

## Shared Templates (`scripts/ci-templates/`)

All repos include templates from `vauchi/scripts` via:

```yaml
include:
  - project: 'vauchi/scripts'
    ref: main
    file: '/ci-templates/rust-base.yml'
```

### Template Index

| Template | Purpose |
|----------|---------|
| `rust-base.yml` | Rust CI foundation: cache, runners, lint/test/build jobs |
| `security.yml` | SAST, cargo-audit, cargo-deny, secret detection |
| `mr-rules.yml` | Change-based rules (skip jobs when files unchanged) |
| `release.yml` | Tag-based release automation |
| `downstream.yml` | Cross-repo pipeline triggering |
| `reuse.yml` | SPDX license header compliance |
| `lint-docs.yml` | Markdown + Gherkin linting, doc naming validation |
| `timeouts.yml` | Timeout definitions (10m/30m/1h/2h) |

## Change-Based Rules (mr-rules.yml)

Jobs skip when irrelevant files haven't changed:

| Rule Template | Triggers On |
|--------------|-------------|
| `.validation-rust` | `**/*.rs`, `**/Cargo.{toml,lock}`, `rust-toolchain.toml` |
| `.validation-deps` | `**/Cargo.{toml,lock}` only |
| `.validation-mobile` | UniFFI binding changes |
| `.validation-reuse` | All files (must check everything) |
| `.validation-full` | Always run on MR |

All use `compare_to: refs/heads/$CI_DEFAULT_BRANCH`.

## Cache Strategy

```yaml
.rust-cache:        # Full (pull-push), key: Cargo.lock, fallback keys
.rust-cache-readonly: # Lint jobs (pull only)
.rust-cache-minimal:  # Format checks (minimal)
```

Cached paths: `.cargo/registry/`, `.cargo/bin/`, `target/`

Fallback keys prevent cold rebuilds on Cargo.lock changes.

## Runner Types

| Template | Runner | Resources |
|----------|--------|-----------|
| `.linux-runner` | Self-hosted QEMU VM | 4 CPU, 8GB RAM, 150GB |
| `.macos-runner` | Self-hosted QEMU VM | 8 CPU, 16GB RAM |
| `.docker-runner` | Docker executor | Shared |
| `.self-hosted` | Base: sccache + git HTTPS | CI_JOB_TOKEN auth |

## Per-Repo Pipeline Summary

### Root (`.gitlab-ci.yml`)
- **Stages**: lint, security
- **Jobs**: `reuse-lint`, `secret_detection`
- Minimal — delegates to sub-repos

### Core (`core/.gitlab-ci.yml`) — Most Complex
**MR Pipeline** (change-based):
- `lint:format`, `lint:clippy`
- `test:core` (coverage with llvm-cov)
- `test:mobile` (coverage for UniFFI bindings)
- `security:audit`, `security:licenses`

**Release Pipeline** (tag `v*.*.*`):
1. `release:verify` — confirm tag on main
2. `build:ios` (macOS), `build:android` (Linux+NDK), `build:validate-bindings`
3. `package:xcframework` (macOS), `package:android` (Linux)
4. `publish:packages`, `publish:core`, `publish:mobile`, `release:create`
5. `trigger:downstream` — triggers swift + android distribution repos

### Relay (`relay/.gitlab-ci.yml`)
- Lint + test + security + Docker build
- Container scanning on main/tags
- `build:docker` pushes to CI_REGISTRY_IMAGE

### CLI, TUI (`cli/`, `tui/`)
- Standard trio: `lint:format`, `lint:clippy`, `test:unit`, `security:audit`
- Minimal pipelines

### Desktop (`desktop/.gitlab-ci.yml`)
- Hybrid Node/Rust pipeline
- `build:frontend-dist` (Vite) needed before Clippy (Tauri's `generate_context!`)
- `test:visual-regression` with Playwright (allow_failure)
- `security:npm-audit` for frontend deps

### Android (`android/.gitlab-ci.yml`)
- Gradle-based: `lint`, `build:debug/release`, `test:unit`
- `update:bindings-version` — triggered by upstream, creates MR to bump dependency

### iOS (`ios/.gitlab-ci.yml`)
- Xcode + SPM: `lint:swiftlint`, `lint:swiftformat`, `lint:xcodegen`
- `build:debug` (simulator), `test:unit`, `test:snapshots`
- `update:bindings-version` — triggered by upstream, creates MR with auto-merge

### Distribution Repos
**vauchi-mobile-swift**: `validate:package` → `update:version` (triggered) → `notify:ios-app`
**vauchi-mobile-android**: `build:aar` → `update:bindings` (triggered) → `notify:android-app`

## Mobile Distribution Flow

```
core tag v*.*.* →
  build iOS/Android bindings →
    publish to GitLab packages →
      trigger vauchi-mobile-swift + vauchi-mobile-android →
        download + update + commit + tag →
          trigger ios + android apps →
            auto-create MR to bump dependency
```

**Uses Pipeline Trigger API** (not GitLab `trigger:` keyword) to pass `UPSTREAM_VERSION` variable.

## Common Failure Modes

| Failure | Cause | Fix |
|---------|-------|-----|
| Cold Cargo rebuild (15-25 min) | Cargo.lock changed, cache miss | Fallback cache keys handle this |
| sccache missing | Linux runner without sccache | Auto-installs via cargo-binstall |
| Clippy fails on git dep | Core version ahead of downstream | `allow_failure: true` + manual retry |
| `build:frontend-dist` missing | Tauri clippy needs built frontend | Job dependency via `needs:` |
| macOS no iOS runtime | Xcode not updated on runner | `before_script` checks + error message |
| Maven analyzer fails | Android test-only deps | `DS_EXCLUDED_ANALYZERS: "gemnasium-maven"` |
| Snapshot baselines missing | First run | `allow_failure: true` |
| Version mismatch at publish | Tag != Cargo.toml version | Auto-creates MR to sync |
| Downstream trigger fails | Missing trigger token | `allow_failure: true` (non-blocking) |

## Timeout Reference

| Template | Duration | Use |
|----------|----------|-----|
| `.timeout-quick` | 10 min | Lint, format |
| `.timeout-standard` | 30 min | Tests, build |
| `.timeout-long` | 1 hour | Coverage, cross-compile |
| `.timeout-extended` | 2 hours | iOS/Android multi-arch |

## Key Settings

- All jobs: `interruptible: true` (auto-cancel on new commits)
- Retry: `max: 1` on runner system failures only
- GIT_DEPTH: 1 (shallow clone)
- RUST_BACKTRACE: 1

## Reading Job Logs

```bash
# Via glab (must cd into correct repo)
cd core && glab ci view

# Via API (more reliable)
glab api "projects/vauchi%2Fcore/pipelines" | jq '.[0]'
glab api "projects/vauchi%2Fcore/pipelines/:id/jobs" | jq '.[] | {name, status}'
glab api "projects/vauchi%2Fcore/jobs/:job_id/trace" > job.log
```
