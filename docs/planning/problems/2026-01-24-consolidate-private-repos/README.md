# Problem: Consolidate Private Repos for OSS Program

**Status**: done
**Created**: 2026-01-24
**Completed**: 2026-01-24
**Owner**: TBD

## Problem Statement

GitLab Open Source Program requires groups to have **at most 1 non-public project**.

Previous private repos (8):
- `assets` (`_assets/`)
- `code`
- `dev-tools` (`_dev-tools/`)
- `docs` (`_docs/`)
- `gitlab-profile`
- `infra` (`_infra/`)
- `strategy` (`_strategy/`)
- `website` (`_website/`)

## Solution

Merged all private repos into a single `_private` repo with subdirectories:

```
_private/
├── assets/
├── dev-tools/
├── docs/
├── infra/
├── strategy/
└── website/
```

## Completed Actions

1. Created `vauchi/private` repo on GitLab (private)
2. Copied content from all 6 private repos into subdirectories
3. Committed and pushed to GitLab
4. Made `code` and `gitlab-profile` public (they were meta repos)
5. Deleted old private repos (assets, dev-tools, docs, infra, strategy, website)
6. Updated main CLAUDE.md with new paths

## Final State

- **1 private repo**: `vauchi/private`
- **14 public repos**: vauchi, core, cli, tui, desktop, relay, e2e, features, android, ios, vauchi-mobile-android, vauchi-mobile-swift, gitlab-profile, code
- **Eligible for GitLab Open Source Program**

## Remaining Tasks

- [ ] Apply for GitLab Open Source Program
- [ ] Remove old local directories (`_docs/`, `_assets/`, etc.) after verification
- [ ] Update justfile if needed
- [ ] Set up GitHub mirror for `features` repo
