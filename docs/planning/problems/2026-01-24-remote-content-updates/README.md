# Problem: Remote Content Updates

**Status:** `implementing` (Phase 1 complete)
**Created:** 2026-01-24
**Priority:** HIGH
**Effort:** MEDIUM (2-3 weeks)

## Problem Statement

The app currently bundles static content for theming, internationalization, in-app help, and contact types. Every content change requires a full app store release cycle, creating:

1. **Update friction** - Content fixes take days/weeks instead of minutes
2. **User fragmentation** - Users on older versions miss improvements
3. **Platform asymmetry** - iOS reviews (1-7 days) vs Android (hours)
4. **Iteration slowdown** - Translation typos, new social networks, help updates all blocked on app releases

## Scope

Content types to make remotely updateable:

| Content Type | Current Location | Risk Level |
|-------------|------------------|------------|
| Contact types (social networks) | `core/vauchi-core/src/social/networks.json` | Low |
| Internationalization | Planned: `locales/*.json` | Medium |
| In-app help | Planned: `features/ideas/in-app-help.md` | Low |
| Theming | CSS/platform themes | Medium |

## Proposed Solution Direction

Host versioned content files at `https://vauchi.app/app-files/` deployed via GitLab CI/CD. Apps fetch manifest on launch, download updates, cache locally with bundled fallback.

```
vauchi.app/app-files/
├── manifest.json           # Version index with checksums
├── themes/v{N}/            # Theme definitions
├── locales/v{N}/           # Translation files
├── help/v{N}/              # Help content
└── networks/v{N}/          # Social network registry
```

## Key Constraints

From PRINCIPLES.md:
- **Privacy**: No tracking via content fetches (minimal metadata)
- **Offline-first**: App must work without network (bundled fallback)
- **Trust**: Content integrity verification (checksums/signatures)
- **Tor support**: Must work through existing Tor proxy

## Open Questions

1. Should content be signed (cryptographic) or just checksummed?
2. Partial updates (delta) or full file replacement?
3. How to handle schema evolution without breaking old apps?
4. Should users be able to disable remote updates entirely?
5. Where to implement: `vauchi-core` or platform-specific?

## Artifacts

- [x] `investigation.md` - Research and technical analysis
- [ ] `rejected-solutions.md` - Approaches considered but not chosen
- [x] `implementation-plan.md` - Detailed implementation steps (5 phases)
- [x] `theming-plan.md` - Theming subsystem with Catppuccin, Dracula, Nord, etc.
- [x] `selective-downloads.md` - On-demand downloads to minimize bandwidth/storage
- [ ] `retrospective.md` - Post-implementation learnings

## Feature Specs

- [x] `features/remote-content.feature` - 55+ scenarios (includes selective downloads)
- [x] `features/theming.feature` - 40+ scenarios for theming system

## Research

- [x] `_docs/knowledge/2026-01-24-remote-content-updates-research.md` - External research

### Key Research Findings

| App | Approach | Relevance |
|-----|----------|-----------|
| **Signal** | CDN + E2E encrypted packs | Manifest pattern applicable |
| **Standard Notes** | JSON descriptor + auto-update | **Most applicable model** |
| **Proton** | Server-synced settings | Not applicable (account-based) |
| **Element/Matrix** | Widget-based pickers | More complex than needed |

**Recommendation:** Standard Notes model - static CDN with versioned JSON manifest

## Related

- `_docs/planning/todo/2026-01-20-internationalization-implementation.md` - i18n planning
- `features/ideas/in-app-help.md` - Help system design
- `core/vauchi-core/src/social/networks.json` - Current static networks

## Implementation Progress

### Phase 1: Core Infrastructure ✅ Complete (2026-01-24)

Branch: `feature/remote-content-updates`

**Files created:**
- `core/vauchi-core/src/content/mod.rs` - Module entry point
- `core/vauchi-core/src/content/types.rs` - ContentManifest, ContentEntry, etc.
- `core/vauchi-core/src/content/integrity.rs` - SHA-256 checksum verification
- `core/vauchi-core/src/content/cache.rs` - Atomic file caching
- `core/vauchi-core/src/content/config.rs` - ContentConfig with Tor support
- `core/vauchi-core/src/content/fetcher.rs` - HTTP client (feature-gated)
- `core/vauchi-core/src/content/manager.rs` - ContentManager orchestration

**Tests:** 44 tests covering all components

**Feature flag:** `content-updates` enables reqwest HTTP client

### Phase 2: Networks Migration ⏳ Pending
### Phase 3: Content Hosting Infrastructure ⏳ Pending
### Phase 4: Platform Integration ⏳ Pending
### Phase 5: Locales & Help ⏳ Pending

## Links

- Feature file: `features/remote-content.feature`
- E2E tests: TBD (`e2e/tests/remote_content/`)
- Knowledge: `_docs/knowledge/2026-01-24-remote-content-updates-research.md`
- Branch: `feature/remote-content-updates`
