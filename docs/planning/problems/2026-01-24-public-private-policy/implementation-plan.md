# Implementation Plan: Public/Private Separation

## Target Structure

### Main Monorepo (Public)
```
vauchi/
├── docs/                    # From _private/docs/ (minus sensitive)
│   ├── architecture/
│   ├── deployment/          # General deployment guides (not secrets)
│   ├── development/
│   ├── diagrams/
│   ├── knowledge/
│   ├── legal/
│   ├── planning/
│   ├── testing/
│   └── workflows/
├── scripts/                 # From _private/dev-tools/
│   ├── hooks/
│   ├── coverage/
│   ├── dev/
│   ├── e2e/
│   └── ide/
├── assets/                  # From _private/assets/
│   └── logo.*
├── website/                 # From _private/website/
│   ├── public/
│   └── app-files-src/
└── VISIBILITY_POLICY.md     # New: explains what goes where
```

### Private Repo (_private/)
```
_private/
├── infra/                   # Deployment configs, runner secrets
│   ├── config/
│   ├── runners/
│   ├── mail/
│   └── scripts/
├── strategy/                # Business strategy
└── sensitive-docs/          # Security audits with unfixed vulns
```

## Migration Steps

### Phase 1: Move Content

1. Copy `_private/docs/` → `docs/` in main repo
2. Copy `_private/dev-tools/` → `scripts/` in main repo
3. Copy `_private/assets/` → `assets/` in main repo
4. Copy `_private/website/` → `website/` in main repo
5. Identify and move sensitive docs to `_private/sensitive-docs/`

### Phase 2: Update References

1. Update `justfile` paths
2. Update `CLAUDE.md`
3. Create `VISIBILITY_POLICY.md`

### Phase 3: Add Enforcement

1. Create pre-commit hook: `scripts/hooks/check-sensitive.sh`
2. Add CI job to `.gitlab-ci.yml`
3. Define sensitive patterns to scan for

### Phase 4: Cleanup

1. Remove migrated content from `_private/`
2. Commit and push all changes
3. Update `_private/` repo

## Sensitive Patterns to Detect

```
# IP addresses (private ranges OK, public IPs flagged)
\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b

# Tokens/secrets
glpat-[a-zA-Z0-9]+
ghp_[a-zA-Z0-9]+
sk-[a-zA-Z0-9]+
-----BEGIN (RSA |EC |)PRIVATE KEY-----

# Sensitive markers
CONFIDENTIAL
DO NOT SHARE
INTERNAL ONLY

# Server hostnames (specific to project)
bold-hopper-vps
```

## Files to Exclude from Scanning

- `*.md` examples showing token formats
- Test fixtures
- This policy document itself
