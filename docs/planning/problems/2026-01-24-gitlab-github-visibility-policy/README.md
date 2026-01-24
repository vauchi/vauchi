# Problem: GitLab/GitHub Visibility Policy Unclear

**Status**: done
**Created**: 2026-01-24
**Owner**: TBD

## Problem Statement

The project lacks a clear, documented policy for:
1. Which repositories should be public vs private on GitLab
2. Which public GitLab repositories should be mirrored to GitHub
3. Whether Vauchi should apply for GitLab's Open Source Program

Current state:
- `_docs/development/2026-01-23-gitlab-github-bridge.md` documents the technical setup
- Convention exists (repos prefixed with `_` are private)
- No explicit policy document exists

## Why This Matters

- **Consistency**: Contributors need to know visibility expectations
- **CI/CD Resources**: GitLab Open Source Program offers significant benefits
- **Community**: GitHub visibility affects discoverability and contributions
- **Cost**: Free tier vs Open Source Program has different limits

## Questions to Answer

1. Should all non-prefixed repos be public on GitLab?
2. Should all public GitLab repos mirror to GitHub?
3. Should Vauchi apply for GitLab Open Source Program?
4. What are the implications of each visibility choice?

## Related Documents

- `_docs/development/2026-01-23-gitlab-github-bridge.md` - Current bridge setup
- `_docs/planning/done/2026-01-22-P8-github-governance.md` - GitHub governance docs

## Resolution

**Decision**: Option B - Mirror All Non-Private

### Completed Actions (2026-01-24)

1. Made `vauchi` GitLab group public
2. Made 12 repos public on GitLab:
   - vauchi, core, cli, tui, desktop, relay, e2e, features
   - android, ios, vauchi-mobile-android, vauchi-mobile-swift
3. Updated `_docs/development/2026-01-23-gitlab-github-bridge.md` with visibility policy
4. Verified GitHub mirroring (11/12 repos already configured)

### Pending

- [ ] Set up GitHub mirror for `features` repo (manual step)
- [ ] Apply for GitLab Open Source Program (optional - self-hosted runners already bypass limits)

## Next Steps

- [x] Review GitLab Open Source Program eligibility
- [x] Document visibility decision criteria
- [x] Create policy document
- [x] Update bridge documentation with policy
