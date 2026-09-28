<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# CLAUDE.md

Privacy-focused updatable contact cards via in-person exchange.
E2E encrypted, decentralized.

## Quick Start

```bash
just setup         # Clone all repos (first time only)
just session-init  # Sync, fetch, hold slot, show issue queue + dashboard (every session)
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
- **Lint rule pages**: `_private/docs/lint-errors/` — one ruff-style
  page per deterministic rule ID (VSH/VGT/VDC/VTL/VCI/VRS/VSC,
  CC-##, ADR-###). Lint error messages cite these; when a check
  fires, the page has the why + fix.
- **Public docs**: `docs/` is the public mdBook site — never write
  plans or private content there

## Tool Usage (MANDATORY)

**Always use `just` recipes instead of raw commands.** Run `just help` for commands.
Full reference: `.claude/docs/just-commands.md`

Key mappings: `cargo build` → `just build [repo]`, `cargo test` → `just test [repo]`,
`cargo fmt && clippy && test` → `just check [repo]`, `grep -r` → `just grep <pattern>`,
`glab mr create` → `just gitlab mr-create [repo]`

**Multi-repo git, commits, branching, WIP, workspace slots**: See `.claude/rules/multi-repo-awareness.md`

**Subagent budget (MANDATORY)** — each `Agent` call pays per-invocation
overhead (system prompt + agent definition + skills list) before doing
any work, and Kimi/Codex subagents have no cheap model tier — every
spawn runs at full session-model price. Evidence and cost data:
`.claude/docs/token-budget.md`. Rules:

- **Never `Agent` for ≤2 search queries.** One wide `Grep` beats two
  `Agent` calls.
- **`Agent` is appropriate when**: (a) ≥3 independent searches across
  unrelated files, (b) the result is many KB and needs digesting before
  returning to main context, or (c) the task matches a specialized
  agent (`adr-check`, `rust-reviewer`, `ci-fixer`).
- **Never `Agent` for**: a single grep, one file read, one symbol, one
  directory listing — anything expressible as a single tool call.
- **Parallelize before delegating.** Two `Grep` calls in one message
  are cheaper than one `Agent` call.
- **Claude: route spawns to the cheapest model that fits** — pass
  `model: "haiku"` (search) or `"sonnet"` (light reasoning); project
  agents already pin cheap models, the built-ins inherit the session
  model.
- **Cascade batches of judgment-free edits** (docs prose, tidy renames,
  version bumps, locale keys) to the `mechanical-edit` agent (Haiku);
  single one-line fixes stay inline.

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
- **Never re-read the same file in one session.** The `log-read-patterns`
  hook flags 3rd+ reads — it exists because this is the dominant waste
  pattern. Read once, hold the relevant region in your head, edit from
  there.
- For wide searches, prefer one well-formed `Grep` with `-A`/`-B`
  context over multiple narrow greps that each return only a line.

## Problem Workflow (MANDATORY)

All significant work follows the Problem to Solution Flow. Use `/problem-workflow`.
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
**Staleness threshold**: 60 days (backlog), 14 days (intake), or 30 days (other
phases).

## Shell & Cargo Rules

- Verify correct working directory before sub-repo commands.
- **CWD gotcha**: `just` recipes use `scripts/scripts/` (double-nested).
  Recipes fail if CWD is not the workspace root. Always run `just` from
  the root, never from a sub-repo.
- Portable-shell rules auto-load when shell paths are touched
  (`.claude/rules/portable-shell.md`; VSH01–12 enforced by
  `check-portable-shell.sh`). Cargo-vet discipline is VSC01-enforced —
  `_private/docs/lint-errors/vsc01-no-ai-audits.md` owns the workflow
  (the old cargo-vet.md rules file is deleted).

## Dependencies & Repo Layout

Crate→consumer graph and pinning: `dependency-map` skill.

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
Use `just gitlab mr-create [repo]` for MRs. Use `/create-mr` for multi-repo workflows.
Contributing guide: `docs/src/developers/contributing.md`.

## Reference Docs

`.claude/docs/`: `just-commands.md`, `repo-organization.md`, `commit-conventions.md`, `local-bindings.md`, `drift-naming.md`, `test-quality-rules.md`, `exchange-protocol.md`, `tls-backend-decisions.md`, `audit-scope.md`, `agent-selection.md`, `token-budget.md`
`.claude/docs/operational-notes-infrastructure.md` and
`operational-notes-development.md`: hard-won operational facts (CI hosts,
GitLab, registry, builds, devices). They replace Claude auto-memory, which
is off for this project; add new facts there.
`_private/docs/testing/`: `manual-testing.md`, `device-automation/`, also `.claude/docs/device-testing.md`

**Per-repo docs** (read when working in matching repos — NOT auto-loaded):
`platform-bindings-rules.md` (android/ios), `scripts-repo-rules.md` (scripts/), `small-repos-rules.md` (relay, drift-detector), `device-testing-rules.md` (device automation)

## Reasoning Error Log

- `.claude/docs/log_reasoning_errors.md` — committed, shared,
  lightweight session entries. Append when self-caught, user-corrected,
  or when review reveals a wrong claim / implementation / tool usage.
  Promote a one-liner to "Common waste patterns" below after 3+
  occurrences.

### Common waste patterns (pattern-match before acting)

Recurring failure modes from the archive and active log. Each costs
5–50 K tokens per occurrence — preventing one outweighs this section's
load cost many times over. Attribution and history:
`.claude/docs/token-budget.md`.

- **Process-bypass under friction.** A failing test, blocked hook, or
  red CI tempts a "make it pass" shortcut (`--no-verify`, exclude file
  from lint, mock the check, suppress the warning). Fix the source
  first; read CC-21 (Chesterton's Fence) before muting any check.
- **"Works on host" assumption.** GNU coreutils on a Linux host does
  not predict BusyBox on `alpine:3.21` CI or BSD on macOS. Test shell
  in the target image (`docker run --rm -v "$PWD":/work -w /work
  alpine:3.21 sh -c '…'`).
- **Header-comment-as-spec.** Comments age faster than the code they
  describe; an inverted-intent header is common. Trust the body;
  sentinel-test unfamiliar scripts before wiring them into CI.
- **Wrong-layer audit.** The cost lives in behavior (Agent calls, large
  `Read`s, retry cycles), not in files/config. Sample jsonl logs and
  hook counts before optimizing.
- **Retry-instead-of-think.** If the second attempt at a problem isn't
  right, STOP and re-read carefully. Attempt 3+ costs more tokens than
  the planning time it skipped.
- **Rules-loaded-but-unused.** Before a multi-step action, scan the
  loaded rules and operational notes for entries that name the action verb.
- **Stale local checkout as evidence.** `git -C <repo> fetch origin`
  before reading state you'll act on; compare against `origin/main`,
  not the working tree. Applies equally when *creating* — the check that
  matters before a new doc or mechanism is "does this already exist",
  and fetching answers only half of it: **no local git state reveals an
  open Draft MR**, so also run `just gitlab mr-list <repo>`. Run
  `just session-init` and both are covered. 6 recurrences; now
  warn-enforced as **VGT09**
  (`_private/docs/lint-errors/vgt09-session-init-receipt.md`).
- **Hypothesis written as finding.** Verification is usually fine while
  evidence is in reach; the break is at the blocked observation, where a
  plausible mechanism gets written into a commit message, gate, record or
  memory with the grammar of a fact. Chat hedging does not travel — the
  commit does. Don't write `fix:` before the run is green; commit as
  `diag:` and name the theory — **VGT11** rejects a `fix:` whose
  `Evidence:` has no observed `after:`. With several candidates,
  prefer one diagnostic that makes the system name the answer (tag them
  all, print the flagged element) over testing candidates one at a time:
  same single CI run, and it cannot be wrong about which one it was.
  4 occurrences in one session, 2026-09-11 (macOS `test:ui`).
- **Xcode on the CI host.** Run `hostname` before any `xcodebuild`: on
  `nell` (the macOS/iOS runner) never boot an iOS simulator — push the
  red test alone and let the MR pipeline show it — and give local macOS
  builds a scratch `-derivedDataPath`. 3 occurrences (2026-09-09,
  2026-09-28 twice); `.claude/docs/operational-notes-infrastructure.md`.
- **Blocked twice or unsure → ask.** Never bypass, never third-retry —
  a question is always cheaper than the cleanup.
- **Stale-pathspec `git add` after `git mv`.** Stage ONLY the new
  paths — a dead old path aborts the whole `git add`. Never silence
  `git add` stderr; verify `git show --stat` shows nonzero insertions
  before pushing a commit that should carry content.

When a `log_reasoning_errors.md` entry hits N≥3, OR a session reveals
a clear recurrence with worked example, promote a one-liner here.

## Exploration

`just tell-me-about "<topic>"` — local-LLM (ollama) codebase search +
summary, **zero API tokens**. Prefer it as the *first* step for open-ended
"where does X live / how does Y work" questions before reaching for an
`Explore`/`general-purpose` agent (which runs on the session model). Use a
frontier agent only when the local pass is inconclusive or the task needs
reasoning over the results, not just locating them.

One-time activation (the tool fails loud until both are done):
`ollama serve >/dev/null 2>&1 &` then `ollama pull gemma4:e2b` (or set
`TELL_ME_AUTOPULL=1`). Override the model with `TELL_ME_MODEL`.

`just semsearch "<question>"` — local **semantic** code search (Ollama
embeddings + sqlite, zero API tokens). Use to *locate* code by meaning when
grep's exact match won't do — prefer it over an `Explore`/`general-purpose`
agent for "where is the code that does X". Exact strings → still `just grep`.
Setup: `semsearch` skill. Search ladder: `grep` (exact) →
`semsearch` (semantic) → `tell-me-about` (summarize) → frontier agent (reason).
