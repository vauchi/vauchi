# Problem: Public vs Private Content Policy

**Status**: investigating
**Created**: 2026-01-24

## Problem Statement

Now that we're in the GitLab OSS Program (1 private repo allowed), we need:
1. A clear policy for what goes where
2. A way to enforce it (prevent accidental leaks)
3. Minimal mental overhead for contributors

## Current State

Everything in `_private/`:
```
_private/
├── assets/      # Logos, brand
├── dev-tools/   # Scripts, hooks
├── docs/        # All documentation
├── infra/       # Deployment, runners, secrets
├── strategy/    # Business strategy
└── website/     # Landing page
```

## Analysis: What's Actually Sensitive?

| Content | Sensitive? | Why |
|---------|------------|-----|
| `infra/` | **YES** | Server IPs, runner tokens, deployment configs |
| `strategy/` | **YES** | Business plans, funding, go-live strategy |
| Security audit details | **YES** | Specific vulnerabilities before fixes |
| `docs/` (general) | No | Architecture, TDD rules help contributors |
| `dev-tools/` | No | Scripts help contributors |
| `assets/` | No | Logo is public anyway |
| `website/` | No | Served publicly |

## The Mental Load Problem

Current structure requires remembering:
- "Is this in main repo or _private?"
- "Which subdir of _private?"
- 6 subdirectories to navigate

Ideal: **One obvious place for each type of content**

## Options

### Option A: Move Public Content to Main Monorepo

```
vauchi/                    # Main monorepo (public)
├── docs/                  # Architecture, planning, TDD
├── scripts/               # Dev tools, hooks
├── assets/                # Logo, brand
├── website/               # Landing page
└── ...code repos...

_private/                  # Truly private only
├── infra/                 # Deployment, secrets
├── strategy/              # Business plans
└── sensitive-docs/        # Security audits pre-fix
```

**Pros:**
- Clear separation: public in main, private in _private
- Contributors see docs alongside code
- Fewer places to look

**Cons:**
- Migration effort
- Main repo gets bigger

### Option B: Keep Current, Add Policy File

Keep `_private/` as-is, add `PRIVATE_POLICY.md` explaining what goes where.

**Pros:**
- No migration
- Simple

**Cons:**
- Everything looks private even when it's not
- Mental overhead remains
- Less transparent to contributors

### Option C: Hybrid - Docs in Main, Rest Stays

Only move `docs/` to main repo (biggest contributor value).
Keep dev-tools, assets, website, infra, strategy in _private.

```
vauchi/
├── docs/                  # Public docs
└── ...

_private/
├── dev-tools/
├── assets/
├── website/
├── infra/
└── strategy/
```

**Pros:**
- Docs visible to contributors (highest value)
- Smaller change

**Cons:**
- Still 5 subdirs in _private
- assets/website being private is odd

## Enforcement Mechanisms

1. **Pre-commit hook**: Scan for sensitive patterns (IPs, tokens, "CONFIDENTIAL")
2. **CI check**: Validate no sensitive files in public repos
3. **CODEOWNERS**: Require review for sensitive directories
4. **Clear naming**: `_private/` prefix is already a signal
5. **Policy file**: Document what goes where

## Recommendation

**Option A** with enforcement:
- Move public content to main monorepo
- Keep `_private/` lean (only infra + strategy + sensitive docs)
- Add pre-commit hook to catch sensitive content
- Add `VISIBILITY_POLICY.md` in main repo

This minimizes mental load: "If it's in _private, it's actually private"
