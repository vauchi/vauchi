---
name: pre-mr-check
description: Run all CI checks locally before creating a merge request, so it passes on the first try
disable-model-invocation: true
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

Run all CI-equivalent checks locally for one or more vauchi repositories before creating a merge request. $ARGUMENTS may specify which repos to check, or leave blank to auto-detect repos with branches ahead of main.

The goal is to **make MRs pass CI on the first try** by catching every issue locally.

## Step 1: Detect Repos to Check

If no repos specified:
- Scan all sub-repos: `core relay cli tui desktop android ios e2e features docs website scripts assets themes locales _private vauchi-mobile-android vauchi-mobile-swift`
- Include the root repo (current directory)
- For each, check if the current branch is not `main` and has commits ahead of `origin/main`

## Step 2: Per-Repo Pre-Flight

For **each** repo to check, run these steps in order. Stop on first failure and report clearly.

### 2a. Rebase on main

```bash
git -C <dir> fetch origin main
git -C <dir> rebase origin/main
```

If rebase fails, stop and report the conflict. The user must resolve it.

### 2b. Read `.gitlab-ci.yml`

Read the repo's `.gitlab-ci.yml` to understand exactly which jobs run on MR pipelines. Adapt checks below to match what CI actually runs. If a job has `allow_failure: true`, still run it but report warnings instead of failures.

### 2c. REUSE Compliance (all repos)

```bash
cd <dir> && reuse lint
```

Every file must have SPDX license headers. If `reuse` is not installed, warn and skip.

### 2d. Repo-Type-Specific Checks

Detect the repo type from project files and run the appropriate checks:

---

#### Rust repos (`Cargo.toml` present): core, relay, cli, tui, e2e

1. **All-in-one**: `just check <repo>` (runs fmt-check + lint + test)
   - For `core/`: verify both `vauchi-core` and `vauchi-mobile` test
   - Pay attention to: unused imports, dead code in test modules, unnecessary `mut`, `type_complexity`, `manual_div_ceil`, and other common issues
2. **Security** (if Cargo.toml/Cargo.lock changed):
   - `just audit <repo>` (if available)

---

#### Desktop (`desktop/`): Tauri + SolidJS

1. **Frontend build** (required before Rust checks):
   ```bash
   cd desktop && npm ci && npm run build
   ```
2. **Frontend lint**: `npm run lint` + `npm run typecheck`
3. **Frontend test**: `npm test`
4. **Rust format**: `cd src-tauri && cargo fmt --check`
5. **Rust lint**: `cd src-tauri && cargo clippy --all-targets -- -D warnings`
6. **Rust test**: `cd src-tauri && cargo test`
7. **Security**: `npm audit --audit-level=moderate` + `cargo audit`

---

#### Android (`android/`): Kotlin/Compose

1. **Lint**: `./gradlew lint`
2. **Test**: `./gradlew testDebugUnitTest`
3. Set `JAVA_HOME` if needed (check for JDK 21)

---

#### iOS (`ios/`): SwiftUI

1. **SwiftLint**: `swiftlint --strict` (if installed)
2. **SwiftFormat**: `swiftformat --lint .` (if installed)
3. **Xcodegen**: `xcodegen generate && git diff --exit-code` (verify project file is up to date)
4. **Build**: `xcodebuild -scheme Vauchi -destination 'platform=iOS Simulator,...' build`
5. **Test**: `xcodebuild test` (skip snapshot tests)

---

#### Features (`features/`): Gherkin specs

1. **Doc naming**: Check all `.md` files follow `YYYY-MM-DD-name.md` convention (except `README.md`, `CLAUDE.md`)
2. **Structure**: Every `.feature` file must have a `Feature:` line and not be empty
3. **Gherkin lint**: `npx @cucumber/gherkin-utils` (if available, allow failure)

---

#### Scripts (`scripts/`): Shell scripts

1. **ShellCheck**: `shellcheck scripts/*.sh` (if installed)
2. **YAML lint**: `yamllint ci-templates/` (if installed, allow failure)

---

#### Docs (`docs/`): Documentation (mkdocs site)

1. **Mkdocs build**: `mkdocs build --strict` (if mkdocs installed)
2. **Markdown lint**: `markdownlint '**/*.md' --ignore node_modules --ignore site`

---

## Step 3: Summary Report

After all checks complete, present a clear table:

```
Pre-MR Check Results
====================

Repo        | Rebase | REUSE | Format | Lint | Tests | Security
------------|--------|-------|--------|------|-------|--------
core/       |   OK   |  OK   |   OK   |  OK  |  OK   | OK
relay/      |   OK   |  OK   |   OK   | WARN |  OK   | SKIP
desktop/    |   OK   |  OK   |   OK   |  OK  |  OK   | WARN
...

PASS: Ready to create MR
  or
FAIL: Fix the issues above before creating MR
```

- **OK**: Check passed
- **WARN**: Check failed but has `allow_failure: true` in CI (won't block MR)
- **FAIL**: Check failed and will block the MR pipeline
- **SKIP**: Tool not installed or not applicable

## Important Notes

- Run checks **in the same order CI does** to catch dependency issues
- For Rust: `cargo clippy --all-targets` catches issues in tests, benches, and examples that `cargo clippy` alone misses
- Shared test utilities (`tests/common/`) need `#[allow(dead_code)]` since each test binary compiles them independently
- The `core/` repo runs clippy with `-D warnings` (deny all warnings) — this is the strictest level
- After fixing issues, re-run just the failing checks to verify before pushing
