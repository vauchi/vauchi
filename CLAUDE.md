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
- **Task Tracking**: Use markdown-plan `.plan.md` companion files for structured task DAGs. See `.claude/rules/markdown-plan.md`
- **Plan-Code Sync**: Never mark a plan item `[x]` on `main` unless implementing code is also on `main`. Plan and code must land atomically in the same MR.
- **Public docs**: `docs/` contains end-user and community developer documentation (mkdocs site)

## Test Quality & Pre-Push Rules (MANDATORY)

See `.claude/rules/test-quality-rules.md` for CC-01 through CC-18.
See `.claude/rules/testing-best-practices.md` for test design principles.

## Tool Usage (MANDATORY)

**Always use `just` recipes instead of raw commands.** See `.claude/rules/just-commands.md` for the full reference.

| Instead of... | Use... |
|---------------|--------|
| `cargo build` / `test` / `fmt` / `clippy` | `just build` / `test` / `fmt` / `lint` `[repo]` |
| `cargo fmt && cargo clippy && cargo test` | `just check [repo]` |
| `cargo test -p <crate>` | `just test-crate <crate>` |
| `glab mr create` / `glab ci status` | `just gitlab mr-create` / `just gitlab pipeline-status` `[repo]` |
| Raw `git -C <repo>` for multi-repo ops | `just git status` / `just git main` / `just git sync` |
| `grep -r` across repos | `just grep <pattern> [glob]` |
| Searching by domain concept | `just concept <name>` |

Repo arg: omit = auto-detect or all, explicit = `just test core`, `desktop` = both rust + ui.

## PROBLEM WORKFLOW (MANDATORY)

**All significant work MUST follow the Problem to Solution Flow.**
Use `/problem-workflow` to create and advance problem records.
See: `_private/docs/2026-01-23-problem-to-solution-flow.md`

Lifecycle: `intake → investigating → planning → implementing → testing → done`

Every problem record must have: **status**, **priority** (critical/high/medium/low), **owner**, **goals** (measurable success criteria). Critical/high problems require a **containment** action before investigation. Each phase has explicit **transition gates** (see SSOT doc). Rejected solutions go in `### Rejected Approaches` inside `implementation-plan.md`. Track Gherkin promotion with `promoted_to:` links.

**Alert threshold**: If `_private/docs/planning/proposals/` has 5+ unreviewed docs, alert the user.
**Staleness threshold**: Flag problems with no update for 14 days (intake) or 30 days (other phases).

## Commands

See `.claude/rules/just-commands.md` for the full command reference, or run `just help`.

## Repository Organisation

See `.claude/rules/repo-organization.md` for the full directory tree and repo tables.

## Shell Commands

- Before running commands in sub-repos, always verify the correct working directory. Multi-repo work requires explicit directory management — use `git -C <dir>` or verify `pwd` before executing.
- Before suggesting tool installations, check what is already installed (e.g., `which <tool>`, `<tool> --version`) and focus on PATH/environment configuration issues first.
- When asked about pricing, hardware, or real-world information, use web search immediately rather than answering from codebase analysis.

## Rust / Cargo

- When modifying `Cargo.toml`, keep git dependency branch references pointing to `main` unless explicitly told otherwise. Do not change branch refs to feature branches.

## Dependencies

`vauchi-core` → cli, tui, desktop, e2e (git dep). `vauchi-protocol` → relay (git dep, shared types only). Downstream uses `branch = "main"` pinning; local dev uses `.cargo/config.toml` path overrides.

## Drift Detection

Use `just drift` to detect cross-layer inconsistencies (missing tests, orphan code, stale docs, naming drift). Run it:

- **After completing a feature** — verify nothing was missed across layers
- **Before creating an MR** — catch drift before CI does
- **When investigating test coverage gaps** — find untested code or orphan tests
- **When refactoring** — ensure renames propagated across all layers

```bash
just drift                  # Human-readable audit, fail on high severity
just drift medium           # Stricter: fail on medium+ severity
just drift-ci               # JSON output (for scripts/CI)
```

Severity levels: `high` (missing tests for features, orphan code), `medium` (missing docs, naming inconsistencies), `low` (minor gaps).

## Exploration

When you need to understand a topic in this codebase, use:

```bash
just tell-me-about "iOS tests"
just tell-me-about "recovery feature"
just tell-me-about "crypto implementation"
```

This uses a local LLM (ollama + qwen2:0.5b) to generate search terms and summarize findings.

## GitLab Workflows

- Always use `just gitlab mr-create [repo]` for MR creation.
- Use the `/create-mr` skill for multi-repo MR workflows.

## Git Workflow (MANDATORY)

All repos have protected `main` branches — no direct pushes, merge via MR only, force push disabled.

See `.claude/rules/commit-conventions.md` for commit format, branch naming, and workflow.
See `docs/developers/contributing.md` for the full contributing guide including MR templates.
