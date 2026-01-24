# Investigation: Remote Content Updates

**Status:** In Progress
**Last Updated:** 2026-01-24

## Current State Analysis

### Content Types Inventory

#### 1. Social Networks Registry (LOW RISK - Start Here)

**Location:** `core/vauchi-core/src/social/networks.json`

```rust
// core/vauchi-core/src/social/registry.rs
pub struct SocialNetwork {
    id: String,              // "twitter", "github"
    display_name: String,    // "Twitter / X", "GitHub"
    profile_url_template: String,  // "https://twitter.com/{handle}"
    icon: Option<String>,    // Optional icon identifier
}
```

- 39 predefined networks currently
- JSON file loaded at compile time via `include_str!`
- Adding new networks requires core release + all downstream updates
- **Ideal first candidate**: Self-contained, low risk, clear schema

#### 2. Internationalization (MEDIUM RISK)

**Status:** Planned but not implemented

**Planned structure:**
```
locales/
├── en.json    # Source language
├── de.json
├── fr.json
└── es.json
```

**Platform implementations:**
- iOS: `.xcstrings` format
- Android: `strings.xml` resources
- Desktop: JSON with `solid-primitives/i18n`
- TUI: Fluent `.ftl` files

**Challenge:** Each platform has different native formats. Options:
1. Canonical JSON → platform-specific build transforms
2. Platform-specific files hosted separately
3. Universal JSON loaded at runtime (bypass native systems)

#### 3. In-App Help (LOW RISK)

**Status:** Design exists at `features/ideas/in-app-help.md`

**Proposed content:**
- Contextual hints (first-time tooltips)
- FAQ entries with expandable answers
- Privacy explainer diagrams
- Onboarding text

**Format:** Markdown or structured JSON with i18n keys

#### 4. Theming (MEDIUM RISK)

**Current implementations:**
- Desktop: CSS custom properties in `desktop/ui/src/styles/app.css`
- Android: Material3 `ColorScheme` in Kotlin
- iOS: SwiftUI defaults (no custom theme yet)

**What could be remote:**
- Color palette values
- NOT: Layout, spacing, component structure

---

## Architecture Options

### Option A: Static File Hosting (Recommended)

```
GitLab repo → CI/CD → vauchi.app/app-files/
```

**Pros:**
- Simple deployment (git push)
- CDN-cacheable
- Version control built-in
- No server to maintain

**Cons:**
- No dynamic behavior (A/B testing, gradual rollout)
- Global updates only

### Option B: API Endpoint

```
Dedicated service at api.vauchi.app/content/
```

**Pros:**
- Dynamic responses based on app version
- Gradual rollout capability
- Analytics possible

**Cons:**
- Server to maintain
- More complex deployment
- Privacy concerns (request logging)
- Against minimalism principle

### Option C: Hybrid (Static + Metadata)

Static files with `manifest.json` that includes version compatibility:

```json
{
  "schema_version": 1,
  "generated_at": "2026-01-24T10:00:00Z",
  "content": {
    "networks": {
      "version": "1.8.0",
      "min_app_version": "1.0.0",
      "max_app_version": null,
      "checksum": "sha256:abc123...",
      "files": ["networks.json"]
    }
  }
}
```

**Recommendation:** Option C - Static hosting with smart manifest

---

## Manifest Schema Design

### Version 1 Proposal

```json
{
  "schema_version": 1,
  "base_url": "https://vauchi.app/app-files",
  "generated_at": "2026-01-24T10:00:00Z",

  "content": {
    "networks": {
      "version": "1.0.0",
      "path": "networks/v1/networks.json",
      "checksum": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "size_bytes": 12450,
      "min_app_version": "1.0.0",
      "max_app_version": null
    },
    "locales": {
      "version": "1.0.0",
      "path": "locales/v1/",
      "files": {
        "en": { "checksum": "sha256:...", "size_bytes": 8200 },
        "de": { "checksum": "sha256:...", "size_bytes": 8500 },
        "fr": { "checksum": "sha256:...", "size_bytes": 8300 }
      },
      "min_app_version": "1.0.0"
    },
    "help": {
      "version": "1.0.0",
      "path": "help/v1/",
      "files": {
        "en": { "checksum": "sha256:...", "size_bytes": 15000 }
      },
      "min_app_version": "1.0.0"
    },
    "themes": {
      "version": "1.0.0",
      "path": "themes/v1/default.json",
      "checksum": "sha256:...",
      "size_bytes": 2000,
      "min_app_version": "1.0.0"
    }
  }
}
```

---

## Implementation Location

### Where to implement content fetching?

**Option 1: vauchi-core (Recommended)**

```rust
// New module: core/vauchi-core/src/content/
pub mod content {
    pub mod manifest;
    pub mod fetcher;
    pub mod cache;
    pub mod networks;  // Move from social/
    pub mod themes;
    pub mod locales;
    pub mod help;
}
```

**Pros:**
- Single implementation for all platforms
- Consistent behavior
- Leverages existing HTTP client (reqwest)
- Tor proxy support built-in

**Cons:**
- Rust → FFI complexity for mobile
- Larger core binary

**Option 2: Platform-specific**

Each platform implements its own fetching.

**Pros:**
- Native HTTP stack
- Platform-optimized caching

**Cons:**
- Duplicate logic (4 implementations)
- Inconsistent behavior risk
- More maintenance

**Recommendation:** Implement in `vauchi-core`, expose via existing FFI

---

## Integrity Verification

### Option A: SHA-256 Checksums (Recommended for MVP)

- Simple to implement
- Detects corruption and tampering during transit
- Does not prevent MITM if TLS is compromised

### Option B: Ed25519 Signatures

- Sign content with private key (kept in GitLab CI secrets)
- Verify with public key bundled in app
- Prevents tampering even with MITM
- More complex key management

**Recommendation:** Start with checksums, add signatures in v2 if needed

---

## Caching Strategy

```
┌─────────────────────────────────────────┐
│           Content Resolution            │
├─────────────────────────────────────────┤
│ 1. Check local cache                    │
│    └── If valid & not expired → use it  │
│ 2. Fetch manifest                       │
│    └── Compare versions                 │
│ 3. If newer available:                  │
│    └── Download, verify checksum, cache │
│ 4. If fetch fails:                      │
│    └── Use cached version               │
│ 5. If no cache:                         │
│    └── Use bundled fallback             │
└─────────────────────────────────────────┘
```

**Cache location:** Same as existing storage (`VauchiConfig.storage_path`)

**Cache structure:**
```
{storage_path}/
├── identity/
├── contacts/
└── content/           # New
    ├── manifest.json  # Last fetched manifest
    ├── networks.json
    ├── locales/
    │   ├── en.json
    │   └── de.json
    ├── help/
    │   └── en.json
    └── themes/
        └── default.json
```

---

## Privacy Considerations

### Minimal Fetch Strategy

1. **Single manifest request** on app launch
   - Only reveals: IP address, user-agent (app version)
   - No user identifiers

2. **Conditional fetching**
   - Use `If-None-Match` / `ETag` to avoid re-downloading unchanged content
   - Reduces bandwidth and reveals less about user behavior

3. **Tor compatibility**
   - Must route through existing Tor proxy if configured
   - Already supported via `RelayConfig::proxy`

4. **Opt-out setting**
   - Users should be able to disable remote content updates
   - Falls back to bundled content only

---

## Networking Analysis

### Current State

vauchi-core uses **tungstenite** for WebSocket connections to the relay:
- `network-native-tls` feature: tungstenite + native-tls (default)
- `network-rustls` feature: tungstenite + rustls (for mobile)

**No HTTP client currently exists** in vauchi-core. Options for content fetching:

| Option | Pros | Cons |
|--------|------|------|
| `reqwest` | Full-featured, async, proxy support | Heavy dependency (~1.5MB) |
| `ureq` | Lightweight, blocking, simple | No async, limited proxy |
| `attohttpc` | Minimal, sync | Less maintained |
| Native platform | Uses OS HTTP stack | FFI complexity, 4 implementations |

**Recommendation:** Add `reqwest` with minimal features as optional dependency:
```toml
[dependencies]
reqwest = { version = "0.12", default-features = false, features = ["rustls-tls"], optional = true }

[features]
content-updates = ["reqwest"]
```

This aligns with existing rustls usage for mobile compatibility.

---

## Principles Validation

Checking against PRINCIPLES.md:

### Privacy Principles

| Principle | Validation | Status |
|-----------|------------|--------|
| **User Ownership** | Content cached locally, user controls update setting | PASS |
| **Zero Knowledge** | Content server sees only IP + version, no user ID | PASS |
| **No Harvesting** | No analytics on fetch requests | PASS |
| **No Sharing** | No third-party CDN needed (self-hosted) | PASS |
| **Selective Visibility** | N/A for content updates | N/A |

### Security Principles

| Principle | Validation | Status |
|-----------|------------|--------|
| **Audited Crypto Only** | SHA-256 for checksums (ring), optional Ed25519 signing | PASS |
| **Defense in Depth** | HTTPS + checksum + optional signature | PASS |

### Technical Principles

| Principle | Validation | Status |
|-----------|------------|--------|
| **TDD Mandatory** | Must write feature spec first | REQUIRED |
| **90%+ Coverage** | Content module must be tested | REQUIRED |
| **Rust Core** | Implement in vauchi-core | PASS |
| **Clean Dependencies** | Optional feature flag keeps core minimal | PASS |

### UX Principles

| Principle | Validation | Status |
|-----------|------------|--------|
| **Offline-First** | Bundled fallback ensures offline works | PASS |
| **Cross-Platform Consistency** | Single implementation in core | PASS |

**Overall:** Solution aligns with all principles. Key requirements:
1. User must be able to disable remote updates (opt-out)
2. Must work through Tor proxy
3. Must not break offline functionality

---

## Research Completed

See: `_docs/knowledge/2026-01-24-remote-content-updates-research.md`

### How do similar apps handle this?

- [x] **Signal** - CDN-based with E2E encrypted sticker packs (`cdn.signal.org/stickers/`). Manifest + versioned content. AWS S3 + CloudFront.
- [x] **Proton Mail** - Server-synced settings (account-based, not applicable to Vauchi). Privacy defaults: block remote content.
- [x] **Standard Notes** - Most relevant model. JSON descriptor with `url`, `download_url`, `latest_url`, `version`. Auto-update checking. Offline-first for desktop.
- [x] **Element/Matrix** - Widget-based sticker pickers, room-based packs (MSC#2545). More complex than needed.

### Key Learnings

1. **No privacy app uses Firebase** - All use self-hosted or static CDN
2. **Standard Notes pattern is ideal** - Manifest JSON with version checking
3. **Offline-first is universal** - Bundle baseline, sync in background
4. **Checksums are standard** - Cryptographic signatures are optional enhancement

### Technical questions

- [x] What HTTP client does vauchi-core currently use for relay? → **tungstenite (WebSocket only, no HTTP)**
- [x] Background fetch support on iOS/Android? → **WorkManager (Android), BackgroundTasks (iOS)**
- [ ] How to handle concurrent access to cached content? → SQLite transactions or file locking

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Content fetch fails | Medium | Low | Bundled fallback always works |
| Malicious content served | Low | High | Checksums, HTTPS, optional signatures |
| Schema breaking change | Medium | Medium | `min_app_version` in manifest |
| Large download on mobile data | Medium | Low | Size limits, WiFi-only option |
| CDN outage | Low | Low | Cache persists, bundled fallback |

---

## Recommended Architecture (Post-Research)

Based on research, the **Standard Notes model** is most applicable:

### Manifest Schema (Final Proposal)

```json
{
  "schema_version": 1,
  "generated_at": "2026-01-24T10:00:00Z",
  "base_url": "https://vauchi.app/app-files",
  "content": {
    "networks": {
      "version": "1.0.0",
      "path": "networks/v1/networks.json",
      "checksum": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "size_bytes": 12450,
      "min_app_version": "1.0.0"
    },
    "locales": {
      "version": "1.0.0",
      "path": "locales/v1/",
      "files": {
        "en": { "path": "en.json", "checksum": "sha256:...", "size_bytes": 8200 },
        "de": { "path": "de.json", "checksum": "sha256:...", "size_bytes": 8500 }
      },
      "min_app_version": "1.0.0"
    },
    "help": {
      "version": "1.0.0",
      "path": "help/v1/",
      "files": {
        "en": { "path": "en.json", "checksum": "sha256:...", "size_bytes": 15000 }
      },
      "min_app_version": "1.0.0"
    },
    "themes": {
      "version": "1.0.0",
      "path": "themes/v1/default.json",
      "checksum": "sha256:...",
      "size_bytes": 2000,
      "min_app_version": "1.0.0"
    }
  }
}
```

### Update Flow

```
┌─────────────────────────────────────────────────────────────┐
│                      App Launch                              │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  1. Load bundled content (always available)                  │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  2. Check: remote updates enabled? (user setting)            │
│     └─► NO → Use bundled + cached content, done              │
└─────────────────────────┬───────────────────────────────────┘
                          │ YES
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Fetch manifest.json (respect sync interval)              │
│     └─► FAIL → Use cached content, done                      │
└─────────────────────────┬───────────────────────────────────┘
                          │ SUCCESS
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Compare versions with cached manifest                    │
│     └─► No updates → done                                    │
└─────────────────────────┬───────────────────────────────────┘
                          │ Updates available
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  5. Check min_app_version compatibility                      │
│     └─► Incompatible → Skip update, log warning              │
└─────────────────────────┬───────────────────────────────────┘
                          │ Compatible
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  6. Download updated content files                           │
│     - Verify checksum                                        │
│     - Atomic write to cache                                  │
│     └─► FAIL → Keep existing cache                           │
└─────────────────────────┬───────────────────────────────────┘
                          │ SUCCESS
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  7. Update cached manifest, notify app of new content        │
└─────────────────────────────────────────────────────────────┘
```

### Implementation in vauchi-core

```rust
// New module structure
pub mod content {
    pub mod manifest;    // Manifest parsing, version comparison
    pub mod fetcher;     // HTTP client, checksum verification
    pub mod cache;       // Local storage, atomic writes
    pub mod resolver;    // Content resolution (cache → bundled → remote)
}

// Public API
pub struct ContentManager {
    config: ContentConfig,
    cache: ContentCache,
    fetcher: ContentFetcher,
}

impl ContentManager {
    pub fn networks(&self) -> &[SocialNetwork];
    pub fn locale(&self, lang: &str) -> Option<&LocaleStrings>;
    pub fn help(&self, lang: &str) -> Option<&HelpContent>;
    pub fn theme(&self) -> &ThemeConfig;

    pub async fn check_for_updates(&self) -> Result<UpdateStatus>;
    pub async fn apply_updates(&self) -> Result<()>;
}
```

### GitLab CI Pipeline

```yaml
# .gitlab-ci.yml for app-files deployment
stages:
  - validate
  - build
  - deploy

validate:
  stage: validate
  script:
    - just validate-content  # JSON schema validation
    - just check-checksums   # Verify all checksums match

build:
  stage: build
  script:
    - just build-manifest    # Generate manifest.json with checksums
  artifacts:
    paths:
      - dist/

deploy:
  stage: deploy
  script:
    - just deploy-to-pages   # Deploy to vauchi.app/app-files/
  only:
    - main
```

## Next Steps

1. [x] Research similar apps (Signal, Proton, Standard Notes, Element)
2. [x] Finalize manifest schema
3. [x] Create implementation plan document → `implementation-plan.md`
4. [x] Write Gherkin feature spec → `features/remote-content.feature`
5. [x] Create theming plan → `theming-plan.md`
6. [x] Write theming feature spec → `features/theming.feature`
7. [x] Design selective downloads strategy → `selective-downloads.md`
8. [ ] Prototype with `networks.json` in vauchi-core (Phase 1)
9. [ ] Design content build pipeline for GitLab CI (Phase 3)
10. [ ] E2E tests
