<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# KIMI.md

Privacy-focused updatable contact cards via in-person exchange.
E2E encrypted, decentralized.

This is the Kimi Code CLI equivalent of `CLAUDE.md`. It documents the
Vauchi-specific conventions, rules, and workflows for Kimi Code users.

## Quick Start

```bash
just setup         # Clone all repos (first time only)
just session-init  # Sync, fetch, show work board + dashboard (every session)
just build         # Build Rust workspace
just check         # Run all checks
just session-end   # Verify pushed, release board claims, check staleness (every session end)

# Local dev feedback loops
cargo watch -x check           # ~1s incremental with mold — fastest feedback
cargo watch -x 'nextest run'   # re-run tests on file save
```

## MANDATORY

- **Principles**: All work must align with
  [docs/about/principles.md](docs/src/about/principles.md)
- **Vocabulary**: Canonical glossary at `_private/docs/CONTEXT.md` —
  domain, CoreUI, crypto, repos, workspace terms with `_Avoid_`
  aliases. When prose drifts from these names, prose is wrong.
- **Visibility**: See `.claude/rules/visibility-boundary.md`
- **TDD, Structure, Crypto, Coverage**: See `.claude/rules/tdd-and-code-rules.md`
- **Code Comments**: See `.claude/rules/comments.md` — self-document via
  naming; keep a comment only for strange/uncommon patterns, and then
  state *why*, not *how*
- **Test Quality & Design**: See `.claude/rules/test-quality-rules.md`.
  Full reference: `.claude/docs/test-quality-rules.md`
- **Defensive Coding (ASVS)**: See `.claude/rules/defensive-coding-asvs.md`
  — OWASP ASVS 5.0-mapped checklist for input handling, file handling,
  and API/auth boundaries. Applies at design, planning, TDD, and coding
  time, not just at audit time.
- **Session Hygiene**: See `.claude/rules/session-hygiene.md`
- **Task Tracking & Plan-Code Sync**: See `.claude/docs/markdown-plan.md`
- **File Size**: See `.claude/rules/file-size.md`
- **Public docs**: `docs/` is the public mdBook site — never write
  plans or private content there

## Kimi Code Skills (Vauchi-Specific)

Invoke with `/skill:<name>` or the model may auto-invoke based on context.

| Skill | Command | When |
|-------|---------|------|
| TDD Workflow | `/skill:tdd-workflow <task>` | Implementing any code |
| Problem Workflow | `/skill:problem-workflow <problem>` | Starting significant work |
| Multi-Repo MR | `/skill:multi-repo-mr <action>` | GitLab MR operations |
| Rust Patterns | `/skill:rust-patterns <topic>` | Writing Rust code |
| Pre-MR Check | `/skill:pre-mr-check <repo>` | Before creating MRs |
| Session Hygiene | `/skill:session-hygiene <start or end>` | Session start/end |
| Just Recipes | `/skill:just-recipes <command>` | Finding the right `just` recipe |
| Security Audit | `/skill:security-audit <scope>` | Security review or audit |
| Platform Bindings | `/skill:platform-bindings <platform>` | iOS/Android/macOS/Windows/Linux |
| Device Testing | `/skill:device-testing <device>` | On-device or Maestro tests |
| Markdown Plan | `/skill:markdown-plan <task>` | Writing implementation plans |
| Create MR | `/skill:create-mr <title>` | Creating merge requests |

## Tool Usage (MANDATORY)

**Always use `just` recipes instead of raw commands.** Run `just help` for commands.
Full reference: `.claude/docs/just-commands.md`

Key mappings: `cargo build` → `just build [repo]`, `cargo test` → `just test [repo]`,
`cargo fmt && clippy && test` → `just check [repo]`, `grep -r` → `just grep <pattern>`,
`glab mr create` → `just gitlab mr-create [repo]`

**Multi-repo git, commits, branching, WIP, worktrees**: See `.claude/rules/multi-repo-awareness.md`

**Subagent budget (MANDATORY)** — each `Agent` call adds significant
per-invocation overhead. Rules:

- **Never `Agent` for ≤2 search queries.** Use `Grep` / `Read` /
  `Glob` directly. One `Grep` with a wide pattern beats two `Agent`
  calls.
- **`Agent` is appropriate when**: (a) ≥3 independent searches across
  unrelated files, (b) the result would be many KB and you need it
  digested before returning to main context, or (c) the task matches
  a specialized agent's description.
- **Never `Agent` for**: a single grep, reading one file, finding one
  symbol, listing files in a directory, or anything you could express
  as a single tool call.
- **Parallelize before delegating.** Two `Grep` calls in one message
  are cheaper than one `Agent` call.

**Tool output discipline (MANDATORY)** — a single noisy command
(`git log`, `cargo check`, `just test`, large `Read`) routinely dumps
10–40 K tokens into context. Default to narrow output; widen only when
  the narrow form was inconclusive.

- **Use `--quiet` on `just check`/`test`/`build`/`fmt`/`lint`.** The
  shared `quiet-runner.sh` captures full output to `/tmp`, prints only
  a pass/fail table on success (and dumps the full failed step's log
  on failure). Default to `--quiet`; drop it only when actively
  debugging a flaky test.
- **Branch-scoped git views**: use `just git log-branch [repo]` and
  `just git diff-main [repo]` — both already filter to "since
  origin/main" and `--stat` where appropriate. Avoid raw `git log`
  / `git diff` without limits.
- For ad-hoc git work, `git -C <dir> log --oneline -N` (default N=15)
  and `git -C <dir> diff --stat` first; widen only if inconclusive.
- `cargo check` / `just test` failures (when not in `--quiet`) → pipe
  through `tail -50`. Re-run targeted (`cargo check -p <crate>`,
  `just test-name <pat> <repo>`) instead of the full workspace.
- `Read` a large file → check `wc -l` or use `Glob` to confirm size
  first. For files >500 lines, always pass `offset` + `limit`. Default
  2000-line read is wasteful when you know which region you need.
- **Never re-read the same file in one session.**
- For wide searches, prefer one well-formed `Grep` with `-A`/`-B`
  context over multiple narrow greps that each return only a line.

## Problem Workflow (MANDATORY)

All significant work follows the Problem to Solution Flow. Use `/skill:problem-workflow`.
See: `_private/docs/reference/2026-01-23-problem-to-solution-flow.md`

Lifecycle: `backlog → intake → investigating → planning → implementing → testing → done`

Every problem record must have: **status**, **priority**, **owner**,
**goals**. Critical/high problems require **containment** before
investigation. Rejected solutions go in `### Rejected Approaches`.
Track Gherkin promotion with `promoted_to:` links.

New problems start in `_private/docs/backlog/` with **investigation only**;
no implementation plans or `plan.md` files. When scheduled, move the record to
`_private/docs/problems/` and set status `intake`.

**Alert threshold**: 5+ unreviewed problems in `_private/docs/problems/` with status `intake`.
**Staleness threshold**: 60 days (backlog), 14 days (intake), or 30 days (other phases).

## Shell & Cargo Rules

- Verify correct working directory before sub-repo commands.
- **CWD gotcha**: `just` recipes use `scripts/scripts/` (double-nested).
  Recipes fail if CWD is not the workspace root. Always run `just` from
  the root, never from a sub-repo.
- Check what's installed before suggesting tool installations.
- When asked about pricing/hardware/real-world info, use web search.
- Cargo-vet rules + portable-shell rules auto-load when relevant paths
  are touched (see `.claude/rules/cargo-vet.md`,
  `.claude/rules/portable-shell.md`).

## Dependencies & Repo Layout

| Crate | Consumers | Notes |
|-------|-----------|-------|
| `vauchi-core` | cli, tui, e2e, android, ios, macos, windows, linux-gtk, linux-qt, web-demo | Git dep, `branch = "main"` |
| `vauchi-platform` | ios, macos, android | UniFFI bindings (SPM via vauchi-platform-swift; Maven AAR from core) |
| `vauchi-cabi` | linux-qt, windows | C ABI exports |
| `vauchi-protocol` | relay | Shared types only (serde) |

Local dev uses `[patch]` blocks injected into each consumer's
`Cargo.toml` by `just setup-path-overrides`; `just check-path-overrides`
(also run on `session-init`) verifies cargo actually picked them up.
The fenced block is local-only — a pre-commit hook blocks staging the
fence or the resulting Cargo.lock churn. `vauchi-platform-kotlin` is
archived.

Repo layout: `.claude/docs/repo-organization.md`. Drift naming: `.claude/docs/drift-naming.md`.

**Claude config location**: the real `.claude/` tree lives at
`_private/.claude` (versioned in the `_private` repo); the root
`.claude` is a relative symlink to it, since Claude Code only discovers
project config at the workspace root. `just session-init` repairs the
symlink; `just session-end` gates on stray `.claude/` dirs in sub-repos.

## Drift Detection

Run `just drift` after completing features or before MRs. Levels: `high`/`medium`/`low`.

## GitLab & Git (MANDATORY)

All repos have protected `main` — merge via MR only, force push disabled.
Use `just gitlab mr-create [repo]` for MRs. Use `/skill:multi-repo-mr` for multi-repo workflows.
Contributing guide: `docs/src/developers/contributing.md`.

## Reference Docs

`.claude/docs/`: `just-commands.md`, `repo-organization.md`, `commit-conventions.md`, `local-bindings.md`, `drift-naming.md`, `test-quality-rules.md`, `exchange-protocol.md`, `tls-backend-decisions.md`, `audit-scope.md`, `agent-selection.md`
`_private/docs/testing/`: `manual-testing.md`, `device-automation/`, also `.claude/docs/device-testing.md`

**Per-repo docs** (read when working in matching repos — NOT auto-loaded):
`platform-bindings-rules.md` (android/ios), `scripts-repo-rules.md` (scripts/), `small-repos-rules.md` (relay, drift-detector), `device-testing-rules.md` (device automation)

## Reasoning Error Log

- `.claude/docs/log_reasoning_errors.md` — committed, shared,
  lightweight session entries. Append when self-caught, user-corrected,
  or when reviewing past work reveals a wrong claim / implementation /
  tool usage. Saves tokens for future sessions by short-circuiting
  known dead ends.

### Common waste patterns (pattern-match before acting)

Recurring failure modes drawn from the archive. Each costs 5–50 K tokens per
occurrence — preventing one outweighs this section's load cost many times over.

- **Process-bypass under friction.** A failing test, blocked hook, or
  red CI tempts a "make it pass" shortcut (`--no-verify`, exclude file
  from lint, mock the check, suppress the warning). Default: fix the
  source first. Read CC-21 (Chesterton's Fence) before muting any
  check.
- **"Works on host" assumption.** GNU coreutils on a Linux host does
  not predict BusyBox on `alpine:3.21` CI. For shell that runs in
  alpine, test inside the same image
  (`docker run --rm -v "$PWD":/work -w /work alpine:3.21 sh -c '…'`).
  Same shape: macOS BSD vs Linux GNU.
- **Header-comment-as-spec.** Comments age faster than the code they
  describe; an inverted-intent header is common. Trust the body. Run a
  sentinel-input test before wiring an unfamiliar script into CI.
- **Wrong-layer audit.** Optimizing at file/config layer when the cost
  lives in behavior (Agent calls, large `Read`s, retry cycles). Sample
  empirically where tokens actually go (jsonl logs, hook counts) before
  optimizing.
- **Retry-instead-of-think.** If the second attempt at a problem isn't
  right, STOP and re-read carefully. Attempt 3+ costs more tokens than
  the planning time it skipped — this is the dominant in-session waste
  pattern by frequency.
- **Memory-loaded-but-unused.** A relevant memory entry is in context,
  yet the next action ignores it (e.g. reflexive `cd` despite the
  `git -C` memory). When starting a multi-step action, scan the
  loaded memory for entries that name the action verb.
- **Stale local checkout as evidence.** Diagnosing, diffing, or
  branching from a sub-repo's local main without fetching first. In a
  20-repo workspace with concurrent sessions, any unfetched checkout
  is weeks old; conclusions drawn from it (and branches built on it)
  get clobbered by reality at push time. `git -C <repo> fetch origin`
  before reading state you'll act on; compare against `origin/main`,
  not the working tree.
- **Blocked twice or unsure → ask.** When a hook/check/permission
  blocks a second attempt, or a fix rests on a semantic guess you
  can't verify, stop and ask the user — never bypass, never
  third-retry.
- **Stale-pathspec `git add` after `git mv`.** Stage ONLY the new
  paths — a dead old path aborts the whole `git add`, and
  `2>/dev/null` turns the abort into silent content loss. Never silence
  `git add` stderr; verify `git show --stat` shows nonzero insertions
  before pushing a commit that should carry content.

When a `log_reasoning_errors.md` entry hits N≥3, OR a session reveals
a clear recurrence with worked example, promote a one-liner here.

## Exploration

`just tell-me-about "<topic>"` — uses local LLM to search and summarize codebase.
