<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# AGENTS.md

Privacy-focused updatable contact cards via in-person exchange.
E2E encrypted, decentralized.

This is the Codex entry point for the Vauchi workspace. `CLAUDE.md` is the
canonical, most detailed repository guide: read it before doing work and follow
all project conventions in it unless a Codex-specific mapping below overrides
the Claude-specific wording.

## Codex mappings

- Treat references to `.claude/rules/` and `.claude/docs/` as references to
  the matching `.codex/rules/` and `.codex/docs/` paths. They share the same
  tracked source in `_private`.
- Repository skills are exposed through `.agents/skills/`. Invoke a named
  skill with `$skill-name` when the task matches its description.
- Treat Claude `Agent` guidance as guidance for Codex subagents. Do not spawn a
  subagent for one or two searches, a single file read, or a mechanical
  one-line change. Parallelize independent local tool calls first.
- Claude slash-command examples such as `/problem-workflow` map to the
  corresponding Codex skill, such as `$problem-workflow`.
- Codex project hooks live in `.codex/config.toml`. They adapt the shared
  `.claude/hooks/` guardrails to Codex hook input. A hook is an additional
  guardrail, not a substitute for following these instructions.

## Mandatory workflow

- Use `just` recipes instead of raw build, test, lint, format, coverage, or MR
  commands. Run `just help` or use `$just-recipes` to find the right recipe.
- Significant work follows the Problem to Solution Flow. Use
  `$problem-workflow` and maintain `_private/docs/work-board.md` plus
  `.claude/.workcontext` as described in `CLAUDE.md`.
- Follow strict TDD for code changes: failing test first, minimal
  implementation, then refactor. See `$tdd-workflow` and
  `docs/src/developers/tdd-rules.md`.
- Never work directly on `main`. Branch in your workspace slot (`just git
  branch <name> [repos]`); parallel sessions use separate slots (`just slot
  status`), never git worktrees.
- Never force-push, bypass hooks, use `--no-verify`, skip required checks, or
  weaken tests to make a check pass.
- All repositories have protected `main`; changes merge through merge requests.
- Verify claims against current code and current git state before acting.
- Keep private plans, audits, strategy, and internal material in `_private/`.
  `docs/` is the public mdBook site.
- Preserve user changes in dirty worktrees and avoid destructive git or file
  operations.

## Context and output discipline

- Start with `rg`/`just grep` for exact search, then `$semsearch`, then
  `just tell-me-about`, and use a subagent only when local exploration is
  insufficient.
- Keep command output narrow. Use `--quiet` on supported `just` checks and
  tests, and inspect targeted excerpts instead of dumping large logs or files.
- Do not reread the same file repeatedly. For files over 500 lines, read the
  relevant range.
- Check installed tools and existing repository helpers before proposing new
  dependencies or scripts.

## Relevant rule loading

Codex does not apply Claude-style `paths:` frontmatter automatically. Before
editing, read the applicable files under `.codex/rules/`; at minimum:

- all code: `tdd-and-code-rules.md`, `test-quality-rules.md`, `comments.md`,
  `file-size.md`, `verify-before-acting.md`, and `visibility-boundary.md`;
- `core/`: `core-repo.md`, `wire-humble.md`, and
  `defensive-coding-asvs.md`;
- `features/`: `feature-specs.md`;
- locale or theme work: `locales-themes.md`;
- shell scripts: `portable-shell.md`;
- multi-repository work: `multi-repo-awareness.md`;
- private documentation: `private-docs.md`;
- platform bindings: use `$platform-bindings` and the referenced platform
  rules.

The full architecture, repository layout, security constraints, commit
conventions, testing commands, error patterns, and reference documentation
remain in `CLAUDE.md` and are mandatory for Codex as well.
