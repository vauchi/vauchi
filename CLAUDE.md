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

1. **Create Problem Record** in `docs/planning/problems/YYYY-MM-DD-problem-slug/`
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
└── planning/
    ├── problems/                 # Problem records with all artifacts
    │   └── YYYY-MM-DD-slug/
    │       ├── README.md         # Status, description, links
    │       ├── investigation.md
    │       ├── rejected-solutions.md
    │       ├── implementation-plan.md
    │       ├── retrospective.md
    │       └── post-mortem.md    # If needed
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

## Repository Structure

| Repo | Purpose |
|------|---------|
| core/ | Core library (vauchi-core) + mobile bindings (vauchi-mobile) |
| relay/ | WebSocket relay server (standalone) |
| cli/ | Command-line interface |
| tui/ | Terminal user interface |
| desktop/ | Tauri + SolidJS desktop app |
| e2e/ | End-to-end tests |

## Other Repositories

| Repo | Purpose | URL |
|------|---------|-----|
| docs/ | Architecture, planning, TDD rules | [gitlab.com/vauchi/docs](https://gitlab.com/vauchi/docs) |
| scripts/ | Dev tools, hooks, utilities | [gitlab.com/vauchi/scripts](https://gitlab.com/vauchi/scripts) |
| website/ | Landing page source | [gitlab.com/vauchi/website](https://gitlab.com/vauchi/website) |
| features/ | Gherkin specs (shared across platforms) | [gitlab.com/vauchi/features](https://gitlab.com/vauchi/features) |
| assets/ | Brand assets, logos | [gitlab.com/vauchi/assets](https://gitlab.com/vauchi/assets) |
| android/ | Kotlin/Compose app | [gitlab.com/vauchi/android](https://gitlab.com/vauchi/android) |
| ios/ | SwiftUI app | [gitlab.com/vauchi/ios](https://gitlab.com/vauchi/ios) |

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

### Branch Protection

All repos have protected `main` branches:
- **Direct push to main**: Blocked (no one)
- **Merge via MR**: Maintainers only
- **Force push**: Disabled

### Branch Naming

```
{type}/{short-description}
```

| Type | Use Case |
|------|----------|
| `feature/` | New functionality |
| `bugfix/` | Bug fixes |
| `refactor/` | Code restructuring |
| `investigation/` | Research/exploration |

### Workflow

```
1. Create branch    → git checkout -b feature/my-feature
2. Make changes     → Follow TDD, commit atomically
3. Push branch      → git push -u origin feature/my-feature
4. Create MR        → glab mr create --title "feat: ..." --target-branch main
5. CI passes        → Security scans + tests must pass
6. Review & merge   → Maintainer merges, branch deleted
```

### Commit Messages

```
{type}: {Short description}

{Longer description if needed}

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`

### Cross-Repo Changes

When work spans multiple repositories, create a branch with the **same name** in each repo and link the MRs together.

**Example:** A feature touching `features/`, `_private/`, and `core/`:

```bash
# Same branch name in all repos
git -C features checkout -b feature/remote-content-updates
git -C _private checkout -b feature/remote-content-updates
git -C core checkout -b feature/remote-content-updates
```

**In each MR description, add a "Related MRs" section:**

```markdown
## Related MRs

- vauchi/features!42 - Gherkin specs
- vauchi/private!15 - Infrastructure changes
- vauchi/core!78 - Implementation
```

Use GitLab MR reference format: `{group}/{project}!{mr_number}`

### MR Description Template

```markdown
## Summary
- Bullet points of changes

## Related MRs
- vauchi/other-repo!123 - Description

## Test Plan
- [ ] Tests pass
- [ ] Manual testing done

## Checklist
- [ ] Follows TDD
- [ ] Documentation updated
- [ ] Feature file updated (if applicable)
```

### Commands

```bash
# Create and push branch
git checkout -b feature/my-feature
git push -u origin feature/my-feature

# Create MR (requires glab auth)
glab mr create --title "feat: My feature" --target-branch main

# View MR
glab mr view

# Check out MR locally
glab mr checkout 42
```
