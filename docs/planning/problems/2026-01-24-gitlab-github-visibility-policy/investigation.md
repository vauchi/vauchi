# Investigation: GitLab Open Source Program & Visibility Policy

**Date**: 2026-01-24

## GitLab Open Source Program

### What's Included (Free)

| Benefit | Details |
|---------|---------|
| **GitLab Ultimate** | Full enterprise tier features |
| **CI/CD Minutes** | 50,000 compute minutes/year |
| **AI Features** | GitLab Duo AI (code suggestions, chat) |
| **Security** | Dependency scanning, vulnerability database |
| **Compliance** | Chain of custody, requirements management |
| **Planning** | Multi-level epics, portfolio roadmaps |

### Eligibility Requirements

All three must be met:

1. **OSI-approved license** - All hosted code must use OSI-approved open source licenses
2. **Non-profit** - Cannot seek profit through services or paid tiers (donations OK)
3. **Public visibility** - Source code and GitLab groups must be publicly visible

### Important Notes

- **Application required** - Since Feb 2022, public projects don't automatically get Ultimate
- **Annual renewal** - Must renew yearly or account downgrades to Free tier
- **No support included** - Can purchase support at 95% off ($4.95/user/month)

### Free Tier Comparison

| Feature | Free Tier | Open Source Program |
|---------|-----------|---------------------|
| CI/CD minutes | 400/month | 50,000/year (~4,166/month) |
| Ultimate features | No | Yes |
| AI features | Limited | Full |
| Security scanning | Basic | Advanced |

### Self-Hosted Runners Alternative

- CI minute limits only apply to GitLab shared runners
- Self-hosted runners have **no minute limits**
- Vauchi already uses self-hosted runners (per `.gitlab-ci.yml`)

## Vauchi Eligibility Assessment

| Requirement | Status | Notes |
|-------------|--------|-------|
| OSI license | Yes | MIT License |
| Non-profit | Yes | No paid tiers, accepts donations |
| Public visibility | Partial | Main repo public, some private |

**Assessment**: Vauchi likely qualifies, but needs public GitLab visibility for qualifying repos.

## Visibility Policy Options

### Option A: Minimal Public

- Only main monorepo public on both platforms
- All other repos private on GitLab
- **Pro**: Maximum control, less maintenance
- **Con**: Limited community contribution, may not qualify for OSS program

### Option B: Mirror All Non-Private

- All repos without `_` prefix public on GitLab
- All public GitLab repos mirror to GitHub
- **Pro**: Consistent, community-friendly, qualifies for OSS program
- **Con**: More maintenance, exposes more code

### Option C: Selective Mirroring

- Public on GitLab: All non-prefixed repos
- Mirror to GitHub: Only community-facing repos (core, cli, features)
- **Pro**: Balance of visibility and maintenance
- **Con**: Inconsistent, harder to document

## Recommendation

**Option B: Mirror All Non-Private** with these rules:

1. Repos prefixed with `_` are private (GitLab only)
2. All other repos are public on GitLab
3. All public GitLab repos mirror to GitHub
4. Apply for GitLab Open Source Program

Rationale:
- Simple, consistent rule
- Maximizes community visibility
- Qualifies for OSS program benefits
- Self-hosted runners already handle CI, but 50k minutes is good backup

## Sources

- [GitLab Open Source Program](https://about.gitlab.com/solutions/open-source/)
- [Ultimate Perks for Open Source Projects](https://about.gitlab.com/blog/ultimate-perks-for-open-source-projects/)
- [GitLab Forum: CI/CD Minutes](https://forum.gitlab.com/t/ci-cd-minutes-for-gitlab-saas-free-tier/40241)
- [GitLab Forum: Open Source Program Requirements](https://forum.gitlab.com/t/public-projects-requiring-gitlab-ultimate-features-should-apply-for-the-gitlab-for-open-source-program/66886)
