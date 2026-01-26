# CLAUDE.md

Privacy-focused updatable contact cards via in-person QR exchange. E2E encrypted, decentralized.

## Quick Start

```bash
git clone git@gitlab.com:vauchi/vauchi.git
cd vauchi
just setup    # Clone all repos
just build    # Build Rust workspace
just check    # Run all checks
```

## MANDATORY

- **Principles**: All work must align with `PRINCIPLES.md`
- **Visibility**: Follow `VISIBILITY_POLICY.md` for public vs private content
- **TDD**: Red→Green→Refactor. Test FIRST. Tests trace to `features/*.feature`
- **Structure**: `src/` = prod, `tests/` = tests (siblings)
- **Crypto**: `ring` only. Never mock crypto
- **Coverage**: 90%+ for vauchi-core
- **Planning**: Feature done → move `docs/planning/todo/` doc to `done/`
- **Docs naming**: All files in `docs/` must be prefixed with date: `YYYY-MM-DD-<name>.md`
  - Exceptions: `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `roadmap.md`, `diagrams/*`, problem artifacts

## PROBLEM WORKFLOW (MANDATORY)

**All significant work MUST follow the Problem to Solution Flow.**
See: `docs/2026-01-23-problem-to-solution-flow.md`

### Core Principle

Every task starts as a **Problem**. Ideas are restated as problems. A Problem flows through the system and accumulates artifacts until solved.

### Problem Lifecycle

```
intake → investigating → planning → implementing → testing → done (or archived)
```

### Workflow Steps

1. **Create Problem Record** in `docs/problems/YYYY-MM-DD-problem-slug/`
2. **Discussion** - Is it actually a problem? If no → archive with learnings
3. **Investigation** - Research the problem, identify solutions
   - External knowledge needed? → Create `docs/knowledge/YYYY-MM-DD-topic.md`
   - Write investigation document
4. **Validate Solutions** against `PRINCIPLES.md`:
   - Core Principles (Privacy, Trust, Quality)
   - Culture (Process Principles)
   - Current Implementation (Technical Principles)
   - Existing Features (UX Principles)
5. **Archive rejected solutions** with reasoning (never discard without documenting why)
6. **Implementation Planning** - How to test? Tools needed? Code or docs?
7. **Write Gherkin Feature** → `features/*.feature`
8. **Write E2E Tests** → `e2e/tests/`
9. **Implement in Strict TDD** - Red → Green → Refactor
10. **All tests green** → Write Retrospective
11. **Spawn child problems** from retrospective learnings
12. **Move to done** when complete

### On Errors/Regressions

If unforeseen errors occur during implementation:
1. Write **Post-Mortem** analyzing root cause
2. **Distill new Problem descriptions** from post-mortem
3. New problems feed back into the workflow

### Directory Structure

```
docs/
├── knowledge/                    # External research (shared)
├── problems/                     # Problem records with all artifacts
│   └── YYYY-MM-DD-slug/
│       ├── README.md             # Status, description, links
│       ├── investigation.md
│       ├── rejected-solutions.md
│       ├── implementation-plan.md
│       ├── retrospective.md
│       └── post-mortem.md        # If needed
└── planning/
    ├── proposals/                # Draft plans awaiting review
    ├── todo/                     # Accepted plans in progress
    ├── ready-for-review/         # Implementation done, awaiting approval
    ├── done/                     # Completed (reference)
    ├── investigations/           # Shared investigations
    ├── retrospectives/           # Shared retrospectives
    ├── post-mortems/             # Shared post-mortems
    └── archived/                 # Not valid / deferred
```

**Alert threshold**: If `proposals/` has 5+ unreviewed docs, alert the user.

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
│── core/                        ← Rust workspace: vauchi-core + vauchi-mobile (UniFFI)
│── relay/                       ← WebSocket relay server (standalone Rust)
│── cli/                         ← Command-line interface
│── tui/                         ← Terminal user interface
│── desktop/                     ← Tauri + SolidJS desktop app
│
├── android/                     ← Kotlin/Compose native app
├── ios/                         ← SwiftUI native app
├── vauchi-mobile-android/       ← Generated Kotlin bindings + JNI libs (SPM distribution)
├── vauchi-mobile-swift/         ← Generated Swift bindings + XCFramework (Gradle distribution)
│
├── e2e/                         ← End-to-end tests
├── features/                    ← Gherkin specs (shared across all platforms)
│
├── docs/                        ← Architecture, planning, TDD rules
├── scripts/                     ← Dev tools, hooks, utilities
├── website/                     ← Landing page source
├── assets/                      ← Brand assets, logos
└── _private/                    ← Sensitive content (see below)
```

Each subdirectory is its own Git repo hosted at `gitlab.com/vauchi/<name>`.

### Repo Categories

**Core & Servers** — Rust crates:

| Repo | Purpose |
|------|---------|
| `core/` | Rust workspace containing `vauchi-core` (crypto, storage, protocol) and `vauchi-mobile` (UniFFI bindings) |
| `relay/` | WebSocket relay server (standalone) |

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

**Support:**

| Repo | Purpose |
|------|---------|
| `docs/` | Architecture, planning, TDD rules |
| `scripts/` | Dev tools, hooks, utilities |
| `website/` | Landing page source |
| `assets/` | Brand assets, logos |

### Private Content (`_private/`)

Only truly sensitive content lives in `_private/`:

| Subdir | Purpose |
|--------|---------|
| `infra/` | Deployment configs, server IPs, runner tokens |
| `strategy/` | Business strategy, funding plans |

See `VISIBILITY_POLICY.md` for what goes where.

## Dependencies

```
core/vauchi-core (standalone, no workspace deps)
    ↑ (git dependency)
relay/, cli/, tui/, desktop/, e2e/
```

All downstream repos use git dependencies with tag-based version pinning.
Local development uses `.cargo/config.toml` path overrides.

## Exploration

When you need to understand a topic in this codebase, use:

```bash
just tell-me-about "iOS tests"
just tell-me-about "recovery feature"
just tell-me-about "crypto implementation"
```

This uses a local LLM (ollama + qwen2:0.5b) to generate search terms and summarize findings.

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
git push -u origin feature/my-feature
glab mr create --title "feat: My feature" --target-branch main
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
git push -u origin feature/my-feature    # Push branch
glab mr create --title "feat: ..."       # Create MR
       --target-branch main
glab mr view                             # View current MR
glab mr checkout 42                      # Check out MR locally
```
