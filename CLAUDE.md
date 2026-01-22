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

- **TDD**: Red→Green→Refactor. Test FIRST. Tests trace to `features/*.feature`
- **Structure**: `src/` = prod, `tests/` = tests (siblings)
- **Crypto**: `ring` only. Never mock crypto
- **Coverage**: 90%+ for vauchi-core
- **Planning**: Feature done → move `docs/planning/todo/` doc to `done/`
- **Docs naming**: All files in `docs/` must be prefixed with date: `YYYY-MM-DD-<name>.md`

## PLANNING WORKFLOW (MANDATORY)

When planning significant work (new features, infrastructure, multi-file changes):

1. **Create planning doc** in `docs/planning/proposals/` with format `YYYY-MM-DD-<name>.md`
2. **User reviews** - if accepted, move to `docs/planning/todo/` with numbered prefix
3. **Update roadmap** - add entry to `docs/planning/roadmap.md`
4. **Implementation done** - move doc from `todo/` to `ready-for-review/`
5. **User approves** - move doc from `ready-for-review/` to `done/`

**Alert threshold**: If `proposals/` has 5+ unreviewed docs, alert the user.

```
docs/planning/
├── roadmap.md         # Entry point - single source of truth
├── proposals/         # Draft plans awaiting review
├── todo/              # Accepted plans in progress
├── ready-for-review/  # Implementation done, awaiting approval
└── done/              # Completed and approved (reference)
```

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
