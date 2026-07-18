<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# KIMI.md

Privacy-focused updatable contact cards via in-person exchange.
E2E encrypted, decentralized.

This is the Kimi Code entry point for the Vauchi workspace. `CLAUDE.md` is the
canonical, most detailed repository guide: read it before doing work and follow
all project conventions in it unless a Kimi-specific mapping below overrides the
Claude-specific wording.

## Kimi mappings

- The shared rules, docs, and skills are one tracked source in `_private/.claude`.
  `.kimi-code/rules/`, `.kimi-code/docs/`, and `.kimi-code/skills/` are symlinks
  to it, so `.claude/rules/`, `.codex/rules/`, and `.kimi-code/rules/` all
  resolve to the same files — treat any of those paths as the same guidance.
- Invoke a repository skill with `/skill:<name>` (or let the model auto-invoke
  based on the task). The skill set is the canonical one under `.claude/skills/`;
  Claude slash-command examples such as `/problem-workflow` map to
  `/skill:problem-workflow`.
- **Co-author trailer**: Kimi commits must end with
  `Co-Authored-By: Kimi Code <noreply@kimi.com>` — the VGT06 gate requires the
  trailer to identify the active provider (Kimi Code/Kimi), not Claude.
- Treat Claude `Agent` guidance as guidance for Kimi subagents. Do not spawn a
  subagent for one or two searches, a single file read, or a mechanical one-line
  change. Parallelize independent local tool calls first, and reach for
  `just semsearch` / `just tell-me-about` (local, zero-token) before an agent.
- Kimi project hooks live in `.kimi-code/` and adapt the shared `.claude/hooks/`
  guardrails to Kimi's hook ABI. A hook is an additional guardrail, not a
  substitute for following these instructions.

## Mandatory workflow

- Use `just` recipes instead of raw build, test, lint, format, coverage, or MR
  commands. Run `just help` or use `/skill:just-recipes` to find the right recipe.
- Significant work follows the Problem to Solution Flow. Use
  `/skill:problem-workflow` and maintain `_private/docs/work-board.md` plus
  `.claude/.workcontext` as described in `CLAUDE.md`.
- Follow strict TDD for code changes: failing test first, minimal
  implementation, then refactor. See `/skill:tdd-workflow`.
- Never work directly on `main`. Use `just worktree create <slug> [repo]`.
- Never force-push, bypass hooks, use `--no-verify`, skip required checks, or
  weaken tests to make a check pass.
- All repositories have protected `main`; changes merge through merge requests.
- Verify claims against current code and current git state before acting.
- Keep private plans, audits, strategy, and internal material in `_private/`.
  `docs/` is the public mdBook site.
- Preserve user changes in dirty worktrees and avoid destructive git or file
  operations.

## Context and output discipline

- Start with `just grep` for exact search, then `just semsearch`, then
  `just tell-me-about`, and use a subagent only when local exploration is
  insufficient.
- Keep command output narrow. Use `--quiet` on supported `just` checks and
  tests, and inspect targeted excerpts instead of dumping large logs or files.
- Do not reread the same file repeatedly. For files over 500 lines, read the
  relevant range.
- Check installed tools and existing repository helpers before proposing new
  dependencies or scripts.

The full architecture, repository layout, security constraints, commit
conventions, testing commands, error patterns, and reference documentation
remain in `CLAUDE.md` and are mandatory for Kimi Code as well.
