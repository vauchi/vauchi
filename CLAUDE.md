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

## Crates (`code/`)

| Crate | Purpose |
|-------|---------|
| vauchi-core | Crypto, protocols, data models |
| vauchi-relay | WebSocket relay server |
| vauchi-cli | CLI for testing |
| vauchi-tui | Terminal UI |
| vauchi-mobile | UniFFI bindings (iOS/Android) |
| vauchi-desktop | Tauri + SolidJS |

## Workspace

| Dir | Purpose |
|-----|---------|
| code/ | Rust monorepo |
| features/ | Gherkin specs (shared across platforms) |
| android/ | Kotlin/Compose app |
| ios/ | SwiftUI app |
| docs/ | Architecture, planning, TDD rules |
| dev-tools/ | Dev scripts, hooks, utilities |

## Exploration

When you need to understand a topic in this codebase, use:

```bash
just tell-me-about "iOS tests"
just tell-me-about "recovery feature"
just tell-me-about "crypto implementation"
```

This uses a local LLM (ollama + qwen2:0.5b) to generate search terms and summarize findings.

## Commits

All tests green. Update `features/` for features, crate README for API changes.
