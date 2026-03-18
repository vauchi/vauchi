<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# CLAUDE.md

Privacy-focused updatable contact cards via in-person exchange. E2E encrypted, decentralized.

## Quick Start

```bash
just setup    # Clone all repos (first time only)
just session-init  # Sync, fetch, show MR/branch/uncommitted dashboard (every session)
just build    # Build Rust workspace
just check    # Run all checks
```

## MANDATORY

- **Principles**: All work must align with [docs/about/principles.md](docs/docs/about/principles.md)
- **Visibility**: See `.claude/rules/visibility-boundary.md`
- **TDD, Structure, Crypto, Coverage**: See `.claude/rules/tdd-and-code-rules.md`
- **Test Quality & Design**: CC-01 through CC-19 in `.claude/rules/test-quality-rules.md`
- **Session Hygiene**: See `.claude/rules/session-hygiene.md` — `session-init` at start, `session-end` before ending, always push before switching machines
- **Task Tracking & Plan-Code Sync**: See `.claude/docs/markdown-plan.md`
- **File Size**: See `.claude/rules/file-size.md` — src <1000, test <1200, functions <100 lines
- **Public docs**: `docs/` is the public mkdocs site — never write plans or private content there

## Tool Usage (MANDATORY)

**Always use `just` recipes instead of raw commands.** Run `just help` for commands.
Full reference: `.claude/docs/just-commands.md`

Key mappings: `cargo build` → `just build [repo]`, `cargo test` → `just test [repo]`,
`cargo fmt && clippy && test` → `just check [repo]`, `grep -r` → `just grep <pattern>`,
`glab mr create` → `just gitlab mr-create [repo]`

**Multi-repo git, commits, branching, WIP, worktrees**: See `.claude/rules/multi-repo-awareness.md`

## Problem Workflow (MANDATORY)

All significant work follows the Problem to Solution Flow. Use `/problem-workflow`.
See: `_private/docs/2026-01-23-problem-to-solution-flow.md`

Lifecycle: `intake → investigating → planning → implementing → testing → done`

Every problem record must have: **status**, **priority**, **owner**, **goals**. Critical/high problems require **containment** before investigation. Rejected solutions go in `### Rejected Approaches`. Track Gherkin promotion with `promoted_to:` links.

**Alert threshold**: 5+ unreviewed docs in `_private/docs/planning/proposals/`.
**Staleness threshold**: 14 days (intake) or 30 days (other phases).

## Shell & Cargo Rules

- Verify correct working directory before sub-repo commands.
- Check what's installed before suggesting tool installations.
- When asked about pricing/hardware/real-world info, use web search.

## Dependencies & Repo Layout

`vauchi-core` → cli, tui, e2e, android, ios, macos, windows, linux-gtk, linux-qt, web-demo (git dep). `vauchi-platform` → UniFFI bindings for mobile/macOS (vauchi-platform-swift, vauchi-platform-kotlin). `vauchi-cabi` → C ABI exports for linux-qt, windows. `vauchi-protocol` → relay (shared types only). Downstream uses `branch = "main"` pinning; local dev uses `.cargo/config.toml` path overrides.

Repo layout: `.claude/docs/repo-organization.md`. Drift naming: `.claude/docs/drift-naming.md`.

## Drift Detection

Run `just drift` after completing features or before MRs. Levels: `high`/`medium`/`low`.

## GitLab & Git (MANDATORY)

All repos have protected `main` — merge via MR only, force push disabled.
Use `just gitlab mr-create [repo]` for MRs. Use `/create-mr` for multi-repo workflows.
Contributing guide: `docs/developers/contributing.md`.

## Reference Docs

`.claude/docs/`: `just-commands.md`, `repo-organization.md`, `commit-conventions.md`, `local-bindings.md`, `drift-naming.md`, `test-quality-rules.md`
`_private/docs/testing/`: `manual-testing.md`, `device-automation/`

## Exploration

`just tell-me-about "<topic>"` — uses local LLM to search and summarize codebase.
