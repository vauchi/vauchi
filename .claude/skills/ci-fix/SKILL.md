---
name: ci-fix
description: Diagnose and fix CI pipeline failures. Use when pipelines fail — fetches logs, classifies root cause, applies fix. Invoke with `/ci-fix` or `/ci-fix <repo>`.
model: sonnet
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# CI Pipeline Fix Workflow

You are diagnosing and fixing CI pipeline failures in the vauchi multi-repo workspace.

## Step 1: Survey

If a specific repo was provided as argument, focus on that repo. Otherwise, scan all repos:

```bash
just gitlab metrics-status
```

Identify repos with `failed` pipeline status.

## Step 2: For each failing repo

### 2a. Get pipeline and failed job details

```bash
just gitlab pipeline-status <repo>
```

If that doesn't show enough detail:

```bash
# Get pipeline ID from the output above, then:
glab api "projects/vauchi%2F<repo>/pipelines/<pipeline_id>/jobs" \
  | jq '.[] | select(.status=="failed") | {name, id, web_url}'
```

### 2b. Fetch job logs

```bash
glab api "projects/vauchi%2F<repo>/jobs/<job_id>/trace" | tail -100
```

Read the last ~100 lines. Look for:
- The actual error message (not just "exit status 1")
- What command failed
- What file/dependency is involved

### 2c. Classify the failure

| Category | Signature | Typical Fix |
|----------|-----------|-------------|
| **Artifact gap** | `No such file or directory` in a downstream job | Expand `artifacts.paths`, add `needs` deps |
| **C FFI cross-compile** | `fatal error: 'X.h' file not found` for non-native target | Feature-gate the C dep in Cargo.toml |
| **Missing tool** | `command not found: X` | Install in `before_script` or fix runner |
| **Dep resolution** | `failed to select a version for X` | Fix Cargo.toml version constraints |
| **Test failure** | `FAILED` / `assertion failed` | Fix the code or test |
| **Flaky/timeout** | Works locally, fails in CI | Check resources, timeouts, race conditions |

## Step 3: Fix

Read the relevant CI config and source files. Apply the minimum change that fixes the root cause.

**Key files per repo:**
- CI config: `<repo>/.gitlab-ci.yml`
- Shared templates: `scripts/ci-templates/*.yml`
- Cargo config: `<repo>/Cargo.toml`, `<repo>/.cargo/config.toml`
- Build scripts: `<repo>/build.rs`, `<repo>/CMakeLists.txt`

**Rules:**
- Never add `allow_failure: true` as a fix for test/build failures (only for known infra gaps)
- Never add `retry: 2` to mask flaky tests — fix the flakiness
- Always verify the fix locally before committing
- Run `just check <repo>` for Rust repos after changes

## Step 4: Verify

Run the appropriate check command:

```bash
# Rust repos
just check <repo>

# Specific compilation target
cargo check -p <crate> --no-default-features --features <features> --target <target>
```

## Step 5: Report

Output a summary table:

```
| Repo | Job | Root Cause | Fix | Status |
|------|-----|-----------|-----|--------|
```

## Common Failure Patterns (vauchi-specific)

1. **CMake artifact gap**: linux-qt `build` job must artifact entire `build/` dir, not just the binary. `test` job needs `build/` + `cabi-lib/`.

2. **WASM C FFI**: `wasm32-unknown-unknown` has no C stdlib. Crates with C build scripts (`libsqlite3-sys`, `aws-lc-sys`) fail. Fix: make the dep optional behind a feature, add feature to `default`. Consumers that target WASM use `default-features = false`.

3. **Feature unification trap**: `default-features = false` does NOT exclude non-optional deps. Only `optional = true` in Cargo.toml actually excludes a dependency.

4. **Runner tag mismatch**: `[linux]` = shared GitLab runners. `.linux-runner` = self-hosted with sccache/caching. Non-Rust repos (linux-qt, web-demo) may use `[linux]` intentionally.

5. **sccache stale state**: If compile errors are nonsensical, try `sccache --stop-server` on the runner or clear the sccache cache.
