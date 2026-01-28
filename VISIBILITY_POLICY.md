# Visibility Policy

This document defines what content is public vs private in the Vauchi project.

## Rule of Thumb

> **If it's in `_private/`, it's actually private. Everything else is public.**

## Never Commit Secrets

**Passwords, tokens, API keys, and credentials must NEVER be committed to git** - not even in `_private/`. Use:

- Environment variables
- `.env` files (gitignored)
- Secret management tools (e.g., `pass`, 1Password CLI)
- CI/CD secret variables

If you accidentally commit a secret, consider it compromised and rotate it immediately.

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

The `.gitlab-ci.yml` includes a job that validates no sensitive patterns exist in public directories.

### If Flagged

If the hook flags your commit:
1. Review the flagged content
2. If truly sensitive → move to `_private/`
3. If false positive → add to `.sensitive-ignore`

## Adding New Content

| You want to add... | Put it in... |
|--------------------|--------------|
| Architecture docs | `docs/architecture/` |
| Planning docs | `docs/planning/` |
| Dev scripts | `scripts/` |
| Deployment with secrets | `_private/infra/` |
| Business docs | `_private/strategy/` |

## Questions?

When in doubt, ask: "Would I be comfortable if this appeared on Hacker News?"
- Yes → public
- No → `_private/`
