<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Visibility Policy

This document defines what content is public vs private in the Vauchi project.

## Rule of Thumb

> **If it's in `_private/`, it's actually private. Everything else is public.**

## Never Commit Secrets

**Passwords, tokens, API keys, and credentials must NEVER be committed to git**

- not even in `_private/`. Use:

- Environment variables
- `.env` files (gitignored)
- Secret management tools (e.g., `pass`, 1Password CLI)
- CI/CD secret variables

If you accidentally commit a secret, consider it compromised and rotate it
immediately.

## Public Content (Main Repo)

| Directory | Content | Why Public |
|-----------|---------|------------|
| `docs/` | Architecture, guides, workflows | Helps contributors understand the project |
| `features/` | Gherkin feature specs | Defines expected behavior for TDD |
| `scripts/` | Dev tools, hooks, utilities | Helps contributors set up and work |
| `assets/` | Logo, brand assets | Used publicly in apps and website |
| `website/` | Landing page source | Served publicly anyway |
| `core/`, `cli/`, etc. | Source code | Open source project |

## Private Content (`_private/`)

| Directory | Content | Why Private |
|-----------|---------|-------------|
| `infra/` | Deployment configs, server IPs, runner tokens | Security - exposes infrastructure |
| `strategy/` | Business plans, funding, roadmap priorities | Business sensitive |
| `docs/designs/` | Design documents | Internal working docs with local paths and private references |
| `docs/planning/` | Lifecycle-tracked plans (todo/done/deferred) | Internal planning workflow |
| `docs/investigations/` | Research, audits, assessments | Internal analysis |
| `docs/post-mortems/` | Incident analysis | Internal incident tracking |
| `docs/decisions/` | ADR decision records | Architecture decisions |
| `docs/problems/` | Problem records | Internal problem tracking |

## Referring to Private Material from Public Text

A public document may name a private issue by its tracker number
(`vauchi/private#N`): it is an opaque reference the maintainers can
follow and reveals nothing but that work is tracked. It may **not**
name a private problem record, design or plan by its dated slug or
path (`2026-10-24-some-record`, `docs/problems/...`): that is a dead
reference for every outside reader. The VDC02 CI check
(`check:no-private-refs`) fails a public repo on both `_private/` paths
and backticked dated slugs.

## What Makes Something Private?

Content should be in `_private/` if it contains:

- **Server details**: IPs, hostnames, SSH configs
- **Secrets**: Tokens, passwords, API keys
- **Infrastructure**: Deployment scripts with server specifics
- **Business strategy**: Funding plans, partnerships, pricing

## Enforcement

### Pre-commit Hook

The `scripts/hooks/check-sensitive.sh` hook scans for:

- Public IP addresses
- Token patterns (`glpat-*`, `ghp_*`, `sk-*`)
- Private key headers
- Markers: `CONFIDENTIAL`, `DO NOT SHARE`

### CI Validation

The `.gitlab-ci.yml` includes a job that validates no sensitive patterns exist in public
directories.

### If Flagged

If the hook flags your commit:

1. Review the flagged content
2. If truly sensitive → move to `_private/`
3. If false positive → add to `.sensitive-ignore`

## Adding New Content

| You want to add... | Put it in... |
|--------------------|--------------|
| Architecture docs | `docs/architecture/` |
| Planning docs | `_private/docs/planning/todo/` |
| Design documents | `_private/docs/designs/` |
| Investigations | `_private/docs/investigations/` |
| Problem records | `_private/docs/problems/` |
| Dev scripts | `scripts/` |
| Deployment with secrets | `_private/infra/` |
| Business docs | `_private/strategy/` |

## Questions?

When in doubt, ask: "Would I be comfortable if this appeared on Hacker News?"

- Yes → public
- No → `_private/`
