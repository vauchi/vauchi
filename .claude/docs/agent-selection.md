<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Agent Selection Reference

When multiple agents could match a request, this doc disambiguates so
the model picks the right one instead of relying on description-match
luck.

Audit context: 2026-05-18 post-merge audit (S2-2) found three
`code-reviewer` agents addressable simultaneously
(`pr-review-toolkit:code-reviewer`, `feature-dev:code-reviewer`,
project `rust-reviewer`). The `feature-dev` plugin was disabled in
the same audit pass — its other two agents (`code-architect`,
`code-explorer`) have built-in equivalents (`Plan`, `Explore`). To
re-enable: flip `feature-dev@claude-plugins-official` to `true` in
`.claude/settings.json`.

## Code review

| Scenario | Agent |
|---|---|
| Rust code, crypto code, vauchi-specific conventions | `rust-reviewer` (project) |
| General PR review across languages | `pr-review-toolkit:code-reviewer` |
| Test coverage on a PR | `pr-review-toolkit:pr-test-analyzer` |
| Silent failure / inadequate error handling | `pr-review-toolkit:silent-failure-hunter` |
| Type design quality | `pr-review-toolkit:type-design-analyzer` |
| Comment accuracy / drift | `pr-review-toolkit:comment-analyzer` |
| Code simplification | `pr-review-toolkit:code-simplifier` |

## Exploration / architecture

| Scenario | Agent |
|---|---|
| Fast file/symbol search | `Explore` (built-in) |
| Multi-step research with synthesis | `general-purpose` (built-in) |
| Implementation strategy / architecture design | `Plan` (built-in) |
| ADR compliance check after work | `adr-check` (project) |

## Operations

| Scenario | Agent |
|---|---|
| CI pipeline failure | `ci-fixer` (project) |
| Cross-repo git operations | `multi-repo-ops` (project) |
| Effort estimation | `estimator` (project) |
| TDD compliance check | `tdd-guard` (project) |
| Plan-vs-code reconciliation | `plan-auditor` (project) |
| Claude Code / SDK / API questions | `claude-code-guide` (project) |

## Other

| Scenario | Agent |
|---|---|
| Socratic discussion (anti-echo-chamber) | `rodin` (project) |
| Status-line setup | `statusline-setup` (project) |
| Catch-all when no specialized match | `claude` or `general-purpose` |

## Per-language reviewer hint

If the diff is dominated by one language, prefer the specialist:

- Rust → `rust-reviewer`
- Anything else → `pr-review-toolkit:code-reviewer`

If unsure: ask the user, don't guess. Picking the wrong reviewer is
silent decision noise — the audit S2-2 trigger.
