---
name: ci-pipeline
description: GitLab CI structure, shared templates, jobs per repo, common failure modes, and pipeline debugging. Use when investigating CI failures or modifying pipelines.
model: haiku
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
| `timeouts.yml` | Timeout definitions (10m/30m/1h/2h) — standalone for non-Rust repos |
| `coverage.yml` | llvm-cov coverage with Pushgateway metrics |
| `mutation.yml` | cargo-mutants nightly testing with progress tracking |
| `benchmark.yml` | Criterion benchmark caching and comparison |
| `perf.yml` | Duplicate/unused dependency checks, binary size tracking |
| `file-size.yml` | Rust source file line count enforcement |
| `freshness.yml` | Core dependency staleness advisory |
| `design-drift.yml` | Component implementation coverage against design specs |
| `plan-sync.yml` | Auto-update plans post-merge with debounce |
| `test-quality.yml` | Zero-assertion scanner, test-to-code ratio, metrics dashboard |
| `badges.yml` | Pipeline status and coverage badge generation |

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
| `.linux-runner` | Self-hosted shell executor | 16 CPU, 20GB RAM, Arch Linux |
| `.macos-runner` | Self-hosted shell executor | 8 CPU, 16GB RAM |
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
5. `trigger:swift` + `trigger:android` — triggers distribution repos via native `trigger:` keyword

### Relay (`relay/.gitlab-ci.yml`)
- Lint + test + security + Docker build
- Container scanning on main/tags
- `build:docker` pushes to CI_REGISTRY_IMAGE

### CLI, TUI (`cli/`, `tui/`)
- Standard trio: `lint:format`, `lint:clippy`, `test:unit`, `security:audit`
- Minimal pipelines

### Desktop (ARCHIVED)
The Tauri desktop app (`desktop/`) has been archived and replaced by native platform frontends (macos, windows, linux-gtk, linux-qt, web-demo). Its CI pipeline is no longer active.

### Android (`android/.gitlab-ci.yml`)
- Gradle-based: `lint`, `build:debug/release`, `test:unit`
- `update:bindings-version` — triggered by upstream, creates MR to bump dependency

### iOS (`ios/.gitlab-ci.yml`)
- Xcode + SPM: `lint:swiftlint`, `lint:swiftformat`, `lint:xcodegen`
- `build:debug` (simulator), `test:unit`, `test:snapshots`
- `update:bindings-version` — triggered by upstream, creates MR with auto-merge

### Distribution Repos
**vauchi-platform-swift**: `validate:package` → `update:version` (triggered) → `notify:ios-app`
**vauchi-platform-kotlin**: `build:aar` → `update:bindings` (triggered) → `notify:android-app`

## Mobile Distribution Flow

```
core tag v*.*.* →
  build iOS/Android bindings →
    publish to GitLab packages →
      trigger vauchi-platform-swift + vauchi-platform-kotlin →
        download + update + commit + tag →
          trigger ios + android apps →
            auto-create MR to bump dependency
```

**Uses native GitLab `trigger:` keyword** to pass `UPSTREAM_VERSION` variable (CI_JOB_TOKEN lacks `api` scope for Pipeline API).

## Branch Protection & CI Push Access

All repos inherit a group-level rule: **push = No one**, merge = Maintainers, force push = disabled.

**Binding repos have a project-level override** because CI must push generated bindings to main:

| Repo | Push | Force Push | Reason |
|------|------|------------|--------|
| `vauchi-platform-swift` | Maintainers | **true** | CI force-pushes bindings |
| `vauchi-platform-kotlin` | Maintainers | false | CI pushes bindings |
| All other repos | No one | false | MR-only (inherited) |

**Do not remove** the project-level rules on binding repos — the release pipeline will break.

The CI bot (`group_122552022_bot_*`, Maintainer level 40) authenticates via `PROJECT_ACCESS_TOKEN` (group-level variable) for all push operations. `CI_JOB_TOKEN` is not used for pushes because: (1) CI_JOB_TOKEN pushes don't trigger new pipelines (core auto-tag), and (2) CI_JOB_TOKEN from upstream-triggered pipelines lacks write access to the triggered repo (app bindings-version bumps).

See `_private/docs/development/2026-02-25-branch-protection-config.md` for full details.

## CI Job Token Allowlists

| Repo | Allows Triggers From |
|------|---------------------|
| `vauchi-platform-swift` | `core`, `ios`, `vauchi-platform-swift` |
| `vauchi-platform-kotlin` | `core`, `android`, `vauchi-platform-kotlin` |
| `ios` | `ios`, `vauchi-platform-swift` |
| `android` | `android`, `vauchi-platform-kotlin` |
| `desktop` | `vauchi` (root), `core`, `desktop` | **ARCHIVED** (ADR-027) — allowlist kept for historical pipelines |
| `cli` | `vauchi` (root), `core`, `cli` |
| `tui` | `vauchi` (root), `core`, `tui` |

## Common Failure Modes

| Failure | Cause | Fix |
|---------|-------|-----|
| Cold Cargo rebuild (15-25 min) | Cargo.lock changed, cache miss | Fallback cache keys handle this |
| sccache missing | Linux runner without sccache | Auto-installs via cargo-binstall |
| Clippy fails on git dep | Core version ahead of downstream | `allow_failure: true` + manual retry |
| ~~`build:frontend-dist` missing~~ | ~~Tauri clippy needs built frontend~~ | **Obsolete** — desktop archived per ADR-027 |
| macOS no iOS runtime | Xcode not updated on runner | `before_script` checks + error message |
| Maven analyzer fails | Android test-only deps | `DS_EXCLUDED_ANALYZERS: "gemnasium-maven"` |
| Snapshot baselines missing | First run | `allow_failure: true` |
| Version mismatch at publish | Tag != Cargo.toml version | Auto-creates MR to sync |
| Downstream trigger fails | CI_JOB_TOKEN from upstream trigger lacks write access to target repo | Use `PROJECT_ACCESS_TOKEN` for push + MR API in triggered jobs |
| CMake artifact gap | `build` artifacts too narrow (only binary, not test executables) | Artifact entire `build/` dir, add `build:cabi` to test `needs` |
| WASM C FFI fail | Non-optional C dep (rusqlite, aws-lc-rs) compiled for wasm32 | Feature-gate dep (`optional = true`), `#[cfg(feature)]` on modules |
| Feature unification trap | `default-features = false` doesn't exclude non-optional deps | Must use `optional = true` in Cargo.toml |

## Timeout Reference

| Template | Duration | Use |
|----------|----------|-----|
| `.timeout-quick` | 10 min | Lint, format |
| `.timeout-standard` | 30 min | Tests, build |
| `.timeout-long` | 1 hour | Coverage, cross-compile |
| `.timeout-extended` | 2 hours | iOS/Android multi-arch |

## Version Tagging Tiers

| Tier | Tag Format | Pipeline | Publishes? | Triggers Mobile? |
|------|-----------|----------|------------|-----------------|
| Dev  | `v0.2.3-dev.N` | lint + test | No | No |
| RC   | `v0.2.3-rc.N`  | lint + test + coverage + mutation + bench + security | No | No |
| PROD | `v0.2.3`       | Full release pipeline (build + package + publish + deploy) | Yes | Yes |

### Workflow

```bash
just release-dev      # Fast feedback (creates v0.2.3-dev.1)
just release-rc       # Full quality gate (creates v0.2.3-rc.1)
just release-prod     # Full release + publish (creates v0.2.3)
just release-history  # Show promotion chain
```

### Tag Regex Rules (in shared templates)

| Template | Regex | Used For |
|----------|-------|----------|
| `.release-only` | `/^v\d+\.\d+\.\d+$/` | PROD-only jobs (publish, deploy, trigger) |
| `.dev-tag-only` | `/^v\d+\.\d+\.\d+-dev\.\d+$/` | Dev-tier jobs |
| `.rc-tag-only` | `/^v\d+\.\d+\.\d+-rc\.\d+$/` | RC-tier jobs |
| `.prerelease-tag-only` | `/^v\d+\.\d+\.\d+-(dev\|rc)\.\d+$/` | Jobs on both dev and RC |

### Per-Repo Release Support

| Repo | auto-tag | Dev/RC | Justfile | Freshness Check |
|------|----------|--------|----------|-----------------|
| core | yes | yes | `just release-dev` | N/A (is upstream) |
| cli | yes | yes | `just release-dev cli` | yes |
| tui | yes | yes | `just release-dev tui` | yes |
| ~~desktop~~ | — | — | — | — | **ARCHIVED** (ADR-027) |
| relay | yes | yes | `just release-dev relay` | N/A (no core dep) |

### Core Dev/RC Downstream Triggers

When core gets a dev or RC tag, it triggers cli/tui to run `verify:upstream-prerelease` — verifying compatibility before committing to a PROD release.

| Core Tag | Downstream Action |
|----------|-------------------|
| `v*-dev.N` | Trigger cli/tui: lint + test |
| `v*-rc.N` | Trigger cli/tui: lint + test |
| `v*.*.*` (PROD) | Existing: mobile binding chain + downstream verify |

### Safety Guards

- `auto-tag:version` rejects pre-release versions (won't auto-create dev/rc tags)
- `publish-packages.sh`, `package-xcframework.sh`, `package-android.sh` reject pre-release versions
- `update:version` (vauchi-platform-swift) and `update:bindings` (vauchi-platform-kotlin) reject pre-release versions
- Tag regex `$` anchor on all PROD jobs prevents dev/rc tags from triggering release pipeline

## Key Settings

- All jobs: `interruptible: true` (auto-cancel on new commits)
- Retry: `max: 1` on runner system failures only
- GIT_DEPTH: 1 (shallow clone)
- RUST_BACKTRACE: 1

## Reading Job Logs

```bash
# Via GitLab API (use CI_JOB_TOKEN in CI, or personal access token locally)
curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/vauchi%2Fcore/pipelines" | jq '.[0]'

curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/vauchi%2Fcore/pipelines/:id/jobs" | jq '.[] | {name, status}'

curl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/vauchi%2Fcore/jobs/:job_id/trace" > job.log
```
