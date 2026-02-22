<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# CLAUDE.md

Privacy-focused updatable contact cards via in-person exchange. E2E encrypted, decentralized.

## Quick Start

```bash
git clone git@gitlab.com:vauchi/vauchi.git
cd vauchi
just setup    # Clone all repos
just build    # Build Rust workspace
just check    # Run all checks
```

## MANDATORY

- **Principles**: All work must align with [docs/about/principles.md](docs/about/principles.md)
- **Visibility**: Follow `VISIBILITY_POLICY.md` for public vs private content
- **TDD**: Red→Green→Refactor. Test FIRST. Tests trace to `features/*.feature`
- **Structure**: `src/` = prod, `tests/` = tests (siblings)
- **Crypto**: `ring` primary; `chacha20poly1305` and `argon2` are spec-mandated exceptions. Never mock crypto
- **Coverage**: 90%+ for vauchi-core
- **Planning**: Feature done → move `_private/docs/planning/todo/` doc to `done/`
- **Public docs**: `docs/` contains end-user and community developer documentation (mkdocs site)

## Test Quality Rules (MANDATORY)

These rules constrain AI code generation to produce verifiable, high-quality output.

- **CC-01 Test Is the Specification**: Never generate production code without a failing test first. Test commit (`test:`) before implementation commit (`feat:`/`fix:`/`refactor:`). Push back if asked to skip.
- **CC-02 Small Atomic Commits**: One behavior per commit. If a feature requires N behaviors, that's N red-green cycles. Flag if a change would touch > 5 production files in one commit.
- **CC-03 Assertions Must Be Specific**: Every test must verify a specific behavioral property.
  - **Forbidden**: `assert!(result.is_ok())` without value check, `assert!(output.contains("generic"))`, `assert!(collection.len() > 0)`, tautological asserts on unsigned types, `if let Ok(x) = result { assert!(...) }` (silently skips Err), zero-assertion tests.
  - **Required**: Assert the specific value, assert error conditions explicitly, assert both positive and negative cases in security code, assert specific absence (not just container size).
- **CC-04 Property-Based Tests for Complex Functions**: Include `proptest` tests for crypto operations, serialization roundtrips, data transformations, parsers, and any function with non-trivial input spaces. Tools: Rust=`proptest`, TS=`fast-check`, Kotlin=`kotest-property`.
- **CC-05 Cross-Boundary Contract Consideration**: When modifying core API, vauchi-protocol types, or UniFFI exports, list all consumers and document contract impact.
- **CC-06 No Real-Time Waits in Tests**: Never use `sleep()` or equivalent for synchronization. Use mockable time, polling with short timeouts, or explicit event synchronization. Exception: load tests simulating real-world timing.
- **CC-07 Behavior-Describing Test Names**: Follow `test_<subject>_<scenario>_<expected_outcome>`. Name must accurately describe what is verified.
- **CC-08 Plans Must Include Test Strategy**: Every implementation plan must address: unit tests, property-based tests, contract tests, affected existing tests, and mutation testing impact.
- **CC-09 Counterexamples Become Regression Tests**: When a property-based test finds a counterexample, capture the exact input as a permanent `test_<fn>_regression_<description>` test.
- **CC-10 Snapshot Updates Require Review**: Never bulk-update snapshots without reviewing each change. Flag if > 10 snapshots change from one code change. Snapshot updates go in a separate commit.
- **CC-11 Test Failure Paths**: For every function, test at least one failure path: invalid input, missing dependency, boundary conditions, and network errors for network code.
- **CC-12 Beware Test-Code Correlation Trap**: Write the test FIRST, commit it, verify it fails, THEN write code. Never "write tests for this function" after the function exists. Mutation testing is the automated defense.
- **CC-13 Stateful Property Tests for Lifecycles**: For domain objects with state machines (identity, contacts, exchange, sync, backup), write stateful property tests that verify invariants across random operation sequences.
- **CC-14 Adversarial Test Data for Security Boundaries**: For functions processing user input or external data, include parameterized tests with adversarial payloads (empty, max-length, unicode, RTL, null bytes, injection payloads, corrupted data, tampered signatures).

## Pre-Push Rules (MANDATORY)

These rules prevent the most common CI failures. Derived from post-mortem analysis of pipeline history (2026-02-20).

- **CC-15 Run Checks Before Pushing**: Before every `git push`, run the repo's check command (`just check`, `cargo fmt && cargo clippy`, `swiftformat . && swiftlint`) and fix all failures. Never push code that hasn't passed local linting and formatting.
- **CC-16 Cross-Repo Push Order**: When a feature spans multiple repos, only push the **upstream** repo first (e.g., `core/` before `cli/`, `android/`, `ios/`). Mark downstream MRs as **Draft** and note in the description that they depend on the upstream MR being merged and bindings published. Do not push consumer branches that call APIs not yet on `main`.
- **CC-17 Verify Assertions in Every Test**: Before committing a test file, verify every `#[test]` function contains at least one `assert*!`, `prop_assert*!`, `.expect()`, or `#[should_panic]`. Zero-assertion tests are rejected by CI.
- **CC-18 Never Retry Without Fixing**: If a pipeline fails, read the job log and fix the root cause before re-running. Never retry the same commit expecting a different result.

## PROBLEM WORKFLOW (MANDATORY)

**All significant work MUST follow the Problem to Solution Flow.**
Use `/problem-workflow` to create and advance problem records.
See: `_private/docs/2026-01-23-problem-to-solution-flow.md`

Lifecycle: `intake → investigating → planning → implementing → testing → done`

**Alert threshold**: If `_private/docs/planning/proposals/` has 5+ unreviewed docs, alert the user.

## Commands

```bash
just setup                  # Clone all repos, set up workspace
just check                  # Format, lint, test
just build                  # Build Rust workspace
just test                   # Run all tests
just fmt                    # Format code
just lint                   # Run clippy
just commit                 # Interactive commit across repos
just help                   # Show all commands
```

## Repository Organisation

This is a **multi-repo project** under the [`vauchi` GitLab group](https://gitlab.com/vauchi). The root repo (`vauchi/vauchi`) is the workspace orchestrator — running `just setup` clones all sub-repos as sibling directories.

```
vauchi/                          ← root repo (this file, justfile, CI config)
│
│── core/                        ← Rust workspace: vauchi-core + vauchi-mobile + vauchi-protocol
│── relay/                       ← WebSocket relay server (uses vauchi-protocol)
│── cli/                         ← Command-line interface
│── tui/                         ← Terminal user interface
│── desktop/                     ← Tauri + SolidJS desktop app
│
├── android/                     ← Kotlin/Compose native app
├── ios/                         ← SwiftUI native app
├── vauchi-mobile-android/       ← Generated Kotlin bindings + JNI libs (Gradle distribution)
├── vauchi-mobile-swift/         ← Generated Swift bindings + XCFramework (SPM distribution)
│
├── e2e/                         ← End-to-end tests
├── features/                    ← Gherkin specs (shared across all platforms)
├── locales/                     ← Locale JSON files (public, translatable)
├── themes/                      ← Theme definitions (public, community-contributed)
│
├── docs/                        ← Architecture, planning, TDD rules
├── scripts/                     ← Dev tools, hooks, utilities
├── drift-detector/              ← Traceability & cross-layer drift detection (MCP + CI)
├── website/                     ← Landing page source
├── assets/                      ← Brand assets, logos
├── gitlab-profile/              ← GitLab group profile page
└── _private/                    ← Sensitive content (see below)
```

Each subdirectory is its own Git repo hosted at `gitlab.com/vauchi/<name>`.

### Repo Categories

**Core & Servers** — Rust crates:

| Repo | Purpose |
|------|---------|
| `core/` | Rust workspace containing `vauchi-core` (crypto, storage, protocol), `vauchi-mobile` (UniFFI bindings), and `vauchi-protocol` (shared message types) |
| `relay/` | WebSocket relay server (uses `vauchi-protocol` for shared types) |

**Clients** — platform apps:

| Repo | Purpose |
|------|---------|
| `cli/` | Command-line interface |
| `tui/` | Terminal user interface |
| `desktop/` | Tauri + SolidJS desktop app |
| `android/` | Kotlin/Compose native app |
| `ios/` | SwiftUI native app |

**Mobile Bindings** — generated by `core/` CI on merge:

| Repo | Purpose |
|------|---------|
| `vauchi-mobile-swift/` | Swift bindings + XCFramework (consumed by `ios/` via SPM) |
| `vauchi-mobile-android/` | Kotlin bindings + JNI libs (consumed by `android/` via Gradle) |

These repos are **not manually edited**. `core/` CI builds UniFFI bindings for all targets and pushes the artifacts to these repos when merging to `main`.

**Testing & Specs:**

| Repo | Purpose |
|------|---------|
| `e2e/` | End-to-end tests |
| `features/` | Gherkin specs (shared across all platforms) |

**Content:**

| Repo | Purpose |
|------|---------|
| `locales/` | Locale JSON files (en, de, fr, es — 754 keys). Own repo (`vauchi/locales`), loaded at runtime by `i18n::init()` |
| `themes/` | Theme definitions (12 themes). Own repo (`vauchi/themes`), loaded at runtime by `load_themes_from_json()` |

**Support:**

| Repo | Purpose |
|------|---------|
| `docs/` | Public documentation website (mkdocs) — user guides, contributing, security |
| `scripts/` | Dev tools, hooks, utilities |
| `drift-detector/` | Traceability matrix & cross-layer drift detection tool (MCP server + CI gate) |
| `gitlab-profile/` | GitLab group profile page (`.gitlab/README.md`) |
| `website/` | Landing page source |
| `assets/` | Brand assets, logos |

### Private Content (`_private/`)

Internal content that is not public-facing lives in `_private/`:

| Subdir | Purpose |
|--------|---------|
| `docs/` | Problem records, planning, roadmap, internal strategy docs |
| `features/` | Brainstorming ideas (prose). Draft Gherkin scenarios live in problem records until promoted to public `features/` |
| `infra/` | Deployment configs, server IPs, runner tokens |
| `strategy/` | Business strategy, funding plans |

See `VISIBILITY_POLICY.md` for what goes where.

## Shell Commands

- Before running commands in sub-repos, always verify the correct working directory. Multi-repo work requires explicit directory management — use `git -C <dir>` or verify `pwd` before executing.
- Before suggesting tool installations, check what is already installed (e.g., `which <tool>`, `<tool> --version`) and focus on PATH/environment configuration issues first.
- When asked about pricing, hardware, or real-world information, use web search immediately rather than answering from codebase analysis.

## Rust / Cargo

- When modifying `Cargo.toml`, keep git dependency branch references pointing to `main` unless explicitly told otherwise. Do not change branch refs to feature branches.

## Dependencies

```
core/vauchi-core (standalone, no workspace deps)
    ↑ (git dependency)
cli/, tui/, desktop/, e2e/

core/vauchi-protocol (shared message types, serde-only)
    ↑ (git dependency)
relay/
```

`relay/` depends on `vauchi-protocol` for shared message types but does **not** depend on `vauchi-core`.

Downstream repos use git dependencies with branch-based pinning (`branch = "main"`).
Local development uses `.cargo/config.toml` path overrides to point at local checkouts.

## Exploration

When you need to understand a topic in this codebase, use:

```bash
just tell-me-about "iOS tests"
just tell-me-about "recovery feature"
just tell-me-about "crypto implementation"
```

This uses a local LLM (ollama + qwen2:0.5b) to generate search terms and summarize findings.

## GitLab Workflows

- Always use `git push -o merge_request.create` for MR creation — never use `glab` CLI.
- Use the `/create-mr` skill for multi-repo MR workflows.

## Git Workflow (MANDATORY)

All repos have protected `main` branches — no direct pushes, merge via MR only, force push disabled.

### The Three Steps

**1. Create a branch**

```bash
git checkout -b feature/my-feature
```

Branch naming: `{type}/{short-description}`

| Type | Use Case |
|------|----------|
| `feature/` | New functionality |
| `bugfix/` | Bug fixes |
| `refactor/` | Code restructuring |
| `investigation/` | Research/exploration |

**2. Do the work — commit often**

- If changing code: **strict TDD** — Red → Green → Refactor. No exceptions.
- Commit atomically — each commit should be a single logical change.
- Commit message format:

```
{type}: {Short description}

{Longer description if needed}

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

**3. Create a Merge Request**

```bash
git push -u origin feature/my-feature \
  -o merge_request.create \
  -o merge_request.target=main \
  -o merge_request.title="feat: My feature"
```

MR description must include:

```markdown
## Summary
- Bullet points of changes

## Related MRs
- vauchi/other-repo!123 - Description  ← list cross-repo MR dependencies

## Test Plan
- [ ] Tests pass
- [ ] Manual testing done

## Checklist
- [ ] Follows TDD
- [ ] Documentation updated
- [ ] Feature file updated (if applicable)
```

CI (security scans + tests) must pass before merge. Use GitLab MR reference format: `{group}/{project}!{mr_number}`.

### Multi-Repo Features

When work spans multiple repositories, **keep branch names in sync** across all affected repos:

```bash
# Same branch name in every repo touched
git -C features checkout -b feature/remote-content-updates
git -C core checkout -b feature/remote-content-updates
git -C docs checkout -b feature/remote-content-updates
```

Each MR must list the related MRs it depends on in the **Related MRs** section so reviewers can see the full picture.

### Git Commands Reference

```bash
git checkout -b feature/my-feature       # Create branch
git push -u origin feature/my-feature \  # Push branch + create MR
  -o merge_request.create \
  -o merge_request.target=main \
  -o merge_request.title="feat: ..."
```

