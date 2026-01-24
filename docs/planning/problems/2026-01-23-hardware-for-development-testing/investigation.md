# Investigation: Funding strategies for hardware acquisition

## Summary

Going open source with proper funding infrastructure is the fastest non-complex path to sustainable funding. The privacy-focused nature of vauchi aligns well with the open source funding ecosystem.

## Funding Options Compared

| Option | Setup Time | Complexity | Ongoing Effort | Potential |
|--------|------------|------------|----------------|-----------|
| GitHub Sponsors | 1-2 days | Low | Low | Medium |
| Open Collective | 1-2 days | Low | Low | Medium |
| Crowdfunding (Indiegogo) | 2-4 weeks | Medium | High (campaign) | High (one-time) |
| Grants (NLnet, NGI) | 1-3 months | High | Medium | High |
| Foundation model | 6+ months | High | High | Very High |

## Recommended: GitHub Sponsors + Open Collective

### Why this combination?

1. **Fastest setup** — Can be live in 1-2 days
2. **Zero/low fees** — GitHub: 0%, Open Collective: 10%
3. **Transparent finances** — Builds trust, shows exactly where money goes
4. **Recurring revenue** — Monthly sponsors provide predictable income
5. **No legal entity needed** — Open Source Collective acts as fiscal host
6. **Credibility** — 3,000+ projects use this model

### Setup steps

1. **Create GitHub organization** (if not exists)
2. **Apply to Open Source Collective** (opencollective.com/opensource)
3. **Set up GitHub Sponsors** linked to Open Collective
4. **Create `.github/FUNDING.yml`** (already in P8 governance plan)
5. **Define sponsorship tiers** with clear value propositions

### Sponsorship tier examples

| Tier | Amount | Perks |
|------|--------|-------|
| Supporter | $5/mo | Name in SUPPORTERS.md |
| Backer | $25/mo | Logo in README, early access to releases |
| Sponsor | $100/mo | Logo on website, priority issue response |
| Gold | $500/mo | Featured sponsor, input on roadmap |

## Privacy App Funding Precedents

### ProtonMail (reference case)

- **2014**: Raised $550k via Indiegogo (target was $100k) — 5.5x oversubscribed
- **Key factors**: Clear privacy mission, CERN founders credibility, Swiss jurisdiction
- **Lesson**: Privacy resonates with donors when mission is clear

### Signal Foundation

- Uses foundation model with major donors
- Brian Acton (WhatsApp co-founder) donated $50M
- **Lesson**: Privacy tools attract high-net-worth privacy advocates

### Key success factors for privacy projects

1. **Clear mission statement** — Why privacy matters
2. **Transparent development** — Open source, public roadmap
3. **Technical credibility** — E2E encryption, security audits
4. **No VC dependencies** — Community-funded = community-aligned

## Accelerating Open Source Release

### Current state

- Code is on GitLab (private?)
- P8 governance proposal exists but is deferred

### Fast path to fundable open source

| Step | Effort | Blocks Funding? |
|------|--------|-----------------|
| Add LICENSE file (MIT) | 5 min | Yes |
| Create public GitHub mirror | 30 min | Yes |
| Set up GitHub Sponsors | 1-2 days | Yes |
| SECURITY.md | 1 hour | No |
| CONTRIBUTING.md | 2 hours | No |
| Full P8 governance | Days | No |

**Minimum for funding**: LICENSE + public repo + GitHub Sponsors

### Recommendation

Accelerate LICENSE and public repo from P8. These are the **only blockers** for enabling GitHub Sponsors. Other governance items can follow.

## Alternative: Hybrid Cloud CI

While raising funds, use cloud CI to unblock development:

| Service | macOS | Linux | Windows | Free Tier |
|---------|-------|-------|---------|-----------|
| GitHub Actions | Yes | Yes | Yes | 2,000 min/mo |
| GitLab CI | Yes* | Yes | Yes | 400 min/mo |

*macOS on GitLab requires SaaS Premium or self-hosted

**Limitation**: Cloud CI can build and test, but cannot test on real mobile devices.

## Device Lab Alternatives

| Option | Cost | Pros | Cons |
|--------|------|------|------|
| BrowserStack | $39+/mo | Real devices, cloud | Can't test audio/proximity |
| AWS Device Farm | Pay per use | Real devices | Same limitations |
| University labs | Free? | Real devices | Access restrictions |
| Borrow from network | Free | Real devices | Availability |

**Conclusion**: No cloud option fully replaces physical device ownership for vauchi's requirements (QR, audio proximity).

## Proposed Action Plan

### Phase 1: Enable funding (1-2 days)

1. Add MIT LICENSE to repo
2. Create public GitHub mirror (or make GitLab public)
3. Apply for GitHub Sponsors via Open Source Collective
4. Create FUNDING.yml with tiers

### Phase 2: Build visibility (1-2 weeks)

1. Write clear README with privacy mission
2. Create simple landing page (GitHub Pages)
3. Announce on privacy-focused communities (HN, Reddit r/privacy, etc.)
4. Share technical architecture (builds credibility)

### Phase 3: Sustain (ongoing)

1. Regular updates to sponsors
2. Transparent use of funds (Open Collective dashboard)
3. Acknowledge contributors publicly
4. Consider grant applications (NLnet, NGI) for larger funding

## Decision Required

**Question**: Should we accelerate open source release to enable funding?

**Trade-offs**:
- Pro: Enables funding path immediately
- Pro: Builds community and trust
- Pro: Aligns with privacy mission (transparency)
- Con: Code is visible to competitors (but they can't easily catch up)
- Con: Security through obscurity lost (but we don't rely on that anyway)

**Recommendation**: Yes, accelerate. The benefits outweigh the risks for a privacy-focused project.

## Sources

- [GitHub Sponsors + Open Collective](https://docs.oscollective.org/campaigns-and-partnerships/github-sponsors)
- [Open Source Collective](https://opencollective.com/opensource)
- [ProtonMail Crowdfunding Success](https://proton.me/blog/protonmail-raises-a-record-500000-through-crowdfunding-to-disrupt-the-state-of-email-communications)
- [Sealos - Funding Open Source Guide](https://sealos.io/blog/funding-open-source)
