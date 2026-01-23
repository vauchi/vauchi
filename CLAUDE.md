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
- **TDD**: Red→Green→Refactor. Test FIRST. Tests trace to `features/*.feature`
- **Structure**: `src/` = prod, `tests/` = tests (siblings)
- **Crypto**: `ring` only. Never mock crypto
- **Coverage**: 90%+ for vauchi-core
- **Planning**: Feature done → move `docs/planning/todo/` doc to `done/`
- **Docs naming**: All files in `docs/` must be prefixed with date: `YYYY-MM-DD-<name>.md`

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

## Other Directories

| Dir | Purpose |
|-----|---------|
| features/ | Gherkin specs (shared across platforms) |
| android/ | Kotlin/Compose app |
| ios/ | SwiftUI app |
| docs/ | Architecture, planning, TDD rules |
| dev-tools/ | Dev scripts, hooks, utilities |

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

## Commits

All tests green. Update `docs/planning/` and other relevant documentation in `docs`. Check `features/` for features references. Use changeset.
