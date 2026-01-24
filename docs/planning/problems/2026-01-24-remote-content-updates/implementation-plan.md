# Implementation Plan: Remote Content Updates

**Status:** Draft
**Created:** 2026-01-24
**Estimated Phases:** 4
**Priority:** HIGH

---

## Overview

Implement a remote content update system allowing theming, internationalization, in-app help, and contact types to be updated without app store releases.

### Architecture Summary

```
GitLab CI → vauchi.app/app-files/ (static CDN)
                    ↓
            manifest.json (versions + checksums)
                    ↓
         vauchi-core ContentManager
                    ↓
    ┌───────────────┼───────────────┐
    ↓               ↓               ↓
 Bundled         Cached          Remote
(fallback)    (preferred)      (on update)
```

### Principles Alignment

- **Privacy**: No tracking, minimal metadata, Tor-compatible
- **Offline-first**: Bundled fallback always works
- **TDD**: Red→Green→Refactor for all code
- **User control**: Opt-out setting for remote updates

---

## Phase 1: Core Infrastructure

**Goal:** Build the foundation in `vauchi-core` for fetching, caching, and resolving content.

### 1.1 Add HTTP Client Dependency

**File:** `core/vauchi-core/Cargo.toml`

```toml
[dependencies]
# HTTP client for content fetching (optional)
reqwest = { version = "0.12", default-features = false, features = ["rustls-tls"], optional = true }

[features]
default = ["network"]
content-updates = ["reqwest"]
```

**Rationale:**
- `reqwest` with `rustls-tls` aligns with existing rustls usage for mobile
- Optional feature keeps core minimal for apps that don't need remote updates
- No `default-features` avoids pulling in unnecessary dependencies

### 1.2 Define Content Types

**File:** `core/vauchi-core/src/content/types.rs`

```rust
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Content manifest from remote server
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentManifest {
    pub schema_version: u32,
    pub generated_at: String,
    pub base_url: String,
    pub content: ContentIndex,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentIndex {
    pub networks: Option<ContentEntry>,
    pub locales: Option<LocalesEntry>,
    pub help: Option<LocalesEntry>,
    pub themes: Option<ContentEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentEntry {
    pub version: String,
    pub path: String,
    pub checksum: String,
    pub size_bytes: u64,
    pub min_app_version: String,
    #[serde(default)]
    pub max_app_version: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalesEntry {
    pub version: String,
    pub path: String,
    pub files: HashMap<String, FileEntry>,
    pub min_app_version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEntry {
    pub path: String,
    pub checksum: String,
    pub size_bytes: u64,
}

/// Update check result
#[derive(Debug, Clone)]
pub enum UpdateStatus {
    UpToDate,
    UpdatesAvailable(Vec<ContentType>),
    CheckFailed(String),
    Disabled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ContentType {
    Networks,
    Locales,
    Help,
    Themes,
}
```

### 1.3 Implement Checksum Verification

**File:** `core/vauchi-core/src/content/integrity.rs`

```rust
use ring::digest::{Context, SHA256};

/// Verify SHA-256 checksum of content
pub fn verify_checksum(data: &[u8], expected: &str) -> Result<(), IntegrityError> {
    // Expected format: "sha256:hexstring"
    let expected_hex = expected
        .strip_prefix("sha256:")
        .ok_or(IntegrityError::InvalidFormat)?;

    let mut context = Context::new(&SHA256);
    context.update(data);
    let digest = context.finish();
    let actual_hex = hex::encode(digest.as_ref());

    if actual_hex == expected_hex {
        Ok(())
    } else {
        Err(IntegrityError::ChecksumMismatch {
            expected: expected_hex.to_string(),
            actual: actual_hex,
        })
    }
}

/// Compute SHA-256 checksum of content
pub fn compute_checksum(data: &[u8]) -> String {
    let mut context = Context::new(&SHA256);
    context.update(data);
    let digest = context.finish();
    format!("sha256:{}", hex::encode(digest.as_ref()))
}

#[derive(Debug, thiserror::Error)]
pub enum IntegrityError {
    #[error("Invalid checksum format, expected 'sha256:...'")]
    InvalidFormat,
    #[error("Checksum mismatch: expected {expected}, got {actual}")]
    ChecksumMismatch { expected: String, actual: String },
}
```

### 1.4 Implement Content Cache

**File:** `core/vauchi-core/src/content/cache.rs`

```rust
use std::path::PathBuf;
use std::fs;

pub struct ContentCache {
    cache_dir: PathBuf,
}

impl ContentCache {
    pub fn new(storage_path: &Path) -> Result<Self, CacheError> {
        let cache_dir = storage_path.join("content");
        fs::create_dir_all(&cache_dir)?;
        Ok(Self { cache_dir })
    }

    /// Get cached manifest if exists
    pub fn get_manifest(&self) -> Option<ContentManifest> {
        let path = self.cache_dir.join("manifest.json");
        let data = fs::read_to_string(&path).ok()?;
        serde_json::from_str(&data).ok()
    }

    /// Save manifest to cache
    pub fn save_manifest(&self, manifest: &ContentManifest) -> Result<(), CacheError> {
        let path = self.cache_dir.join("manifest.json");
        let data = serde_json::to_string_pretty(manifest)?;
        atomic_write(&path, data.as_bytes())
    }

    /// Get cached content file
    pub fn get_content(&self, content_type: ContentType, filename: &str) -> Option<Vec<u8>> {
        let path = self.content_path(content_type, filename);
        fs::read(&path).ok()
    }

    /// Save content file to cache (atomic)
    pub fn save_content(
        &self,
        content_type: ContentType,
        filename: &str,
        data: &[u8],
        checksum: &str,
    ) -> Result<(), CacheError> {
        // Verify checksum before saving
        verify_checksum(data, checksum)?;

        let dir = self.cache_dir.join(content_type.dir_name());
        fs::create_dir_all(&dir)?;

        let path = dir.join(filename);
        atomic_write(&path, data)
    }

    fn content_path(&self, content_type: ContentType, filename: &str) -> PathBuf {
        self.cache_dir.join(content_type.dir_name()).join(filename)
    }
}

impl ContentType {
    fn dir_name(&self) -> &'static str {
        match self {
            ContentType::Networks => "networks",
            ContentType::Locales => "locales",
            ContentType::Help => "help",
            ContentType::Themes => "themes",
        }
    }
}

/// Atomic file write (write to temp, then rename)
fn atomic_write(path: &Path, data: &[u8]) -> Result<(), CacheError> {
    let temp_path = path.with_extension("tmp");
    fs::write(&temp_path, data)?;
    fs::rename(&temp_path, path)?;
    Ok(())
}
```

### 1.5 Implement Content Fetcher

**File:** `core/vauchi-core/src/content/fetcher.rs`

```rust
use reqwest::Client;
use std::time::Duration;

pub struct ContentFetcher {
    client: Client,
    base_url: String,
    timeout: Duration,
}

impl ContentFetcher {
    pub fn new(config: &ContentConfig) -> Result<Self, FetchError> {
        let mut builder = Client::builder()
            .timeout(config.timeout)
            .user_agent(format!("Vauchi/{}", env!("CARGO_PKG_VERSION")));

        // Support Tor proxy if configured
        if let Some(proxy_url) = &config.proxy_url {
            builder = builder.proxy(reqwest::Proxy::all(proxy_url)?);
        }

        Ok(Self {
            client: builder.build()?,
            base_url: config.content_url.clone(),
            timeout: config.timeout,
        })
    }

    /// Fetch manifest from remote
    pub async fn fetch_manifest(&self) -> Result<ContentManifest, FetchError> {
        let url = format!("{}/manifest.json", self.base_url);
        let response = self.client.get(&url).send().await?;

        if !response.status().is_success() {
            return Err(FetchError::HttpError(response.status().as_u16()));
        }

        let manifest: ContentManifest = response.json().await?;
        Ok(manifest)
    }

    /// Fetch content file from remote
    pub async fn fetch_content(
        &self,
        path: &str,
        expected_checksum: &str,
        max_size: u64,
    ) -> Result<Vec<u8>, FetchError> {
        let url = format!("{}/{}", self.base_url, path);
        let response = self.client.get(&url).send().await?;

        if !response.status().is_success() {
            return Err(FetchError::HttpError(response.status().as_u16()));
        }

        // Check content length before downloading
        if let Some(len) = response.content_length() {
            if len > max_size {
                return Err(FetchError::TooLarge { size: len, max: max_size });
            }
        }

        let data = response.bytes().await?.to_vec();

        // Verify checksum
        verify_checksum(&data, expected_checksum)?;

        Ok(data)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum FetchError {
    #[error("HTTP error: {0}")]
    HttpError(u16),
    #[error("Network error: {0}")]
    NetworkError(#[from] reqwest::Error),
    #[error("Content too large: {size} bytes (max {max})")]
    TooLarge { size: u64, max: u64 },
    #[error("Integrity error: {0}")]
    IntegrityError(#[from] IntegrityError),
}
```

### 1.6 Implement Content Manager

**File:** `core/vauchi-core/src/content/manager.rs`

```rust
pub struct ContentManager {
    config: ContentConfig,
    cache: ContentCache,
    fetcher: Option<ContentFetcher>,
    bundled: BundledContent,
}

impl ContentManager {
    pub fn new(config: ContentConfig) -> Result<Self, ContentError> {
        let cache = ContentCache::new(&config.storage_path)?;
        let fetcher = if config.remote_updates_enabled {
            Some(ContentFetcher::new(&config)?)
        } else {
            None
        };

        Ok(Self {
            config,
            cache,
            fetcher,
            bundled: BundledContent::load(),
        })
    }

    /// Get social networks (cached → bundled)
    pub fn networks(&self) -> Vec<SocialNetwork> {
        self.cache
            .get_content(ContentType::Networks, "networks.json")
            .and_then(|data| serde_json::from_slice(&data).ok())
            .unwrap_or_else(|| self.bundled.networks.clone())
    }

    /// Get locale strings for language (cached → bundled → None)
    pub fn locale(&self, lang: &str) -> Option<LocaleStrings> {
        let filename = format!("{}.json", lang);

        self.cache
            .get_content(ContentType::Locales, &filename)
            .and_then(|data| serde_json::from_slice(&data).ok())
            .or_else(|| self.bundled.locale(lang))
    }

    /// Check for updates (respects sync interval)
    pub async fn check_for_updates(&self) -> UpdateStatus {
        let Some(fetcher) = &self.fetcher else {
            return UpdateStatus::Disabled;
        };

        // Check if enough time has passed since last check
        if !self.should_check_now() {
            return UpdateStatus::UpToDate;
        }

        match fetcher.fetch_manifest().await {
            Ok(remote) => self.compare_versions(&remote),
            Err(e) => UpdateStatus::CheckFailed(e.to_string()),
        }
    }

    /// Apply available updates
    pub async fn apply_updates(&self) -> Result<ApplyResult, ContentError> {
        let Some(fetcher) = &self.fetcher else {
            return Ok(ApplyResult::Disabled);
        };

        let remote = fetcher.fetch_manifest().await?;
        let updates = self.find_updates(&remote);

        if updates.is_empty() {
            return Ok(ApplyResult::NoUpdates);
        }

        let mut applied = Vec::new();
        let mut failed = Vec::new();

        for update in updates {
            match self.apply_single_update(fetcher, &remote, update).await {
                Ok(()) => applied.push(update),
                Err(e) => failed.push((update, e.to_string())),
            }
        }

        // Save updated manifest
        self.cache.save_manifest(&remote)?;

        Ok(ApplyResult::Applied { applied, failed })
    }

    fn compare_versions(&self, remote: &ContentManifest) -> UpdateStatus {
        let cached = self.cache.get_manifest();
        let mut updates = Vec::new();

        // Compare each content type
        if let Some(remote_networks) = &remote.content.networks {
            if self.is_newer(cached.as_ref(), ContentType::Networks, &remote_networks.version) {
                if self.is_compatible(&remote_networks.min_app_version) {
                    updates.push(ContentType::Networks);
                }
            }
        }

        // ... similar for locales, help, themes

        if updates.is_empty() {
            UpdateStatus::UpToDate
        } else {
            UpdateStatus::UpdatesAvailable(updates)
        }
    }

    fn is_compatible(&self, min_version: &str) -> bool {
        // Compare min_app_version with current app version
        version_compare(env!("CARGO_PKG_VERSION"), min_version) >= 0
    }
}
```

### 1.7 Configuration

**File:** `core/vauchi-core/src/content/config.rs`

```rust
use std::path::PathBuf;
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct ContentConfig {
    /// Local storage path for cache
    pub storage_path: PathBuf,

    /// Remote content URL (e.g., "https://vauchi.app/app-files")
    pub content_url: String,

    /// Enable/disable remote updates
    pub remote_updates_enabled: bool,

    /// Minimum interval between update checks
    pub check_interval: Duration,

    /// HTTP timeout for fetches
    pub timeout: Duration,

    /// Maximum content file size (bytes)
    pub max_content_size: u64,

    /// Proxy URL (for Tor support)
    pub proxy_url: Option<String>,
}

impl Default for ContentConfig {
    fn default() -> Self {
        Self {
            storage_path: PathBuf::from("."),
            content_url: "https://vauchi.app/app-files".to_string(),
            remote_updates_enabled: true,
            check_interval: Duration::from_secs(3600), // 1 hour
            timeout: Duration::from_secs(30),
            max_content_size: 5 * 1024 * 1024, // 5 MB
            proxy_url: None,
        }
    }
}

impl ContentConfig {
    /// Configure with Tor proxy
    pub fn with_tor(mut self) -> Self {
        self.proxy_url = Some("socks5://127.0.0.1:9050".to_string());
        self.timeout = Duration::from_secs(60); // Longer timeout for Tor
        self
    }
}
```

### Phase 1 Tests

**File:** `core/vauchi-core/tests/content/mod.rs`

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_checksum_verification() {
        let data = b"hello world";
        let checksum = compute_checksum(data);
        assert!(verify_checksum(data, &checksum).is_ok());
    }

    #[test]
    fn test_checksum_mismatch() {
        let data = b"hello world";
        let wrong = "sha256:0000000000000000000000000000000000000000000000000000000000000000";
        assert!(verify_checksum(data, wrong).is_err());
    }

    #[test]
    fn test_cache_roundtrip() {
        let temp = TempDir::new().unwrap();
        let cache = ContentCache::new(temp.path()).unwrap();

        let data = b"test content";
        let checksum = compute_checksum(data);

        cache.save_content(ContentType::Networks, "test.json", data, &checksum).unwrap();

        let loaded = cache.get_content(ContentType::Networks, "test.json").unwrap();
        assert_eq!(loaded, data);
    }

    #[test]
    fn test_bundled_fallback() {
        let config = ContentConfig {
            remote_updates_enabled: false,
            ..Default::default()
        };
        let manager = ContentManager::new(config).unwrap();

        // Should return bundled networks even with no cache
        let networks = manager.networks();
        assert!(!networks.is_empty());
    }
}
```

---

## Phase 2: Networks Migration

**Goal:** Migrate `networks.json` from compile-time to runtime loading, with remote update capability.

### 2.1 Move Networks to Content System

**Current:** `core/vauchi-core/src/social/registry.rs` loads via `include_str!`

**Changes:**

1. Keep `networks.json` bundled as fallback
2. Add content resolution: cache → bundled → remote
3. Expose through `ContentManager::networks()`

**File changes:**

```rust
// src/social/registry.rs - modify to use ContentManager
impl SocialNetworkRegistry {
    pub fn new(content: &ContentManager) -> Self {
        let networks = content.networks();
        Self { networks }
    }
}
```

### 2.2 Update API Surface

**File:** `core/vauchi-core/src/api/mod.rs`

```rust
impl Vauchi {
    pub fn new(config: VauchiConfig) -> Result<Self, VauchiError> {
        let content_config = ContentConfig {
            storage_path: config.storage_path.clone(),
            content_url: config.content_url.clone(),
            remote_updates_enabled: config.remote_updates_enabled,
            proxy_url: config.relay.proxy.as_ref().map(|p| p.url.clone()),
            ..Default::default()
        };

        let content = ContentManager::new(content_config)?;
        let social_registry = SocialNetworkRegistry::new(&content);

        // ... rest of initialization
    }

    /// Check for content updates
    pub async fn check_content_updates(&self) -> UpdateStatus {
        self.content.check_for_updates().await
    }

    /// Apply available content updates
    pub async fn apply_content_updates(&self) -> Result<ApplyResult, VauchiError> {
        self.content.apply_updates().await.map_err(Into::into)
    }
}
```

### 2.3 Mobile Bindings

**File:** `core/vauchi-mobile/src/lib.rs`

```rust
/// Check for content updates
#[uniffi::export]
pub fn check_content_updates(handle: &VauchiHandle) -> UpdateStatusResult {
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        handle.inner.check_content_updates().await.into()
    })
}

/// Apply content updates
#[uniffi::export]
pub fn apply_content_updates(handle: &VauchiHandle) -> ApplyResultResult {
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        handle.inner.apply_content_updates().await.into()
    })
}
```

---

## Phase 3: Content Hosting Infrastructure

**Goal:** Set up GitLab CI pipeline to build and deploy content to `vauchi.app/app-files/`.

### 3.1 Content Repository Structure

**Option A:** Subdirectory in `_website/` repo
**Option B:** Dedicated `app-files/` repo (recommended)

```
app-files/
├── src/
│   ├── networks.json       # Source networks
│   ├── locales/
│   │   ├── en.json
│   │   ├── de.json
│   │   └── ...
│   ├── help/
│   │   ├── en.json
│   │   └── ...
│   └── themes/
│       └── default.json
├── scripts/
│   ├── build-manifest.py   # Generate manifest with checksums
│   └── validate-content.py # JSON schema validation
├── schemas/
│   ├── manifest.schema.json
│   ├── networks.schema.json
│   ├── locale.schema.json
│   └── theme.schema.json
├── dist/                   # Built output (gitignored)
└── .gitlab-ci.yml
```

### 3.2 Build Script

**File:** `app-files/scripts/build-manifest.py`

```python
#!/usr/bin/env python3
import json
import hashlib
from pathlib import Path
from datetime import datetime, timezone

def compute_checksum(path: Path) -> str:
    sha256 = hashlib.sha256()
    sha256.update(path.read_bytes())
    return f"sha256:{sha256.hexdigest()}"

def build_manifest(src_dir: Path, dist_dir: Path, version: str):
    manifest = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "base_url": "https://vauchi.app/app-files",
        "content": {}
    }

    # Networks
    networks_src = src_dir / "networks.json"
    if networks_src.exists():
        networks_dst = dist_dir / "networks" / "v1" / "networks.json"
        networks_dst.parent.mkdir(parents=True, exist_ok=True)
        networks_dst.write_bytes(networks_src.read_bytes())

        manifest["content"]["networks"] = {
            "version": version,
            "path": "networks/v1/networks.json",
            "checksum": compute_checksum(networks_dst),
            "size_bytes": networks_dst.stat().st_size,
            "min_app_version": "1.0.0"
        }

    # Locales
    locales_dir = src_dir / "locales"
    if locales_dir.exists():
        files = {}
        for locale_file in locales_dir.glob("*.json"):
            lang = locale_file.stem
            dst = dist_dir / "locales" / "v1" / locale_file.name
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(locale_file.read_bytes())

            files[lang] = {
                "path": locale_file.name,
                "checksum": compute_checksum(dst),
                "size_bytes": dst.stat().st_size
            }

        manifest["content"]["locales"] = {
            "version": version,
            "path": "locales/v1/",
            "files": files,
            "min_app_version": "1.0.0"
        }

    # Write manifest
    manifest_path = dist_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))

    return manifest

if __name__ == "__main__":
    import sys
    version = sys.argv[1] if len(sys.argv) > 1 else "1.0.0"
    build_manifest(Path("src"), Path("dist"), version)
```

### 3.3 GitLab CI Pipeline

**File:** `app-files/.gitlab-ci.yml`

```yaml
stages:
  - validate
  - build
  - deploy

variables:
  CONTENT_VERSION: "1.0.0"

validate:
  stage: validate
  image: python:3.11-slim
  script:
    - pip install jsonschema
    - python scripts/validate-content.py
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == "main"

build:
  stage: build
  image: python:3.11-slim
  script:
    - python scripts/build-manifest.py $CONTENT_VERSION
  artifacts:
    paths:
      - dist/
    expire_in: 1 week
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

deploy:
  stage: deploy
  image: alpine:latest
  script:
    - apk add --no-cache rsync openssh-client
    - mkdir -p ~/.ssh
    - echo "$DEPLOY_SSH_KEY" > ~/.ssh/id_ed25519
    - chmod 600 ~/.ssh/id_ed25519
    - rsync -avz --delete dist/ deploy@vauchi.app:/var/www/vauchi.app/app-files/
  environment:
    name: production
    url: https://vauchi.app/app-files/
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
  when: manual  # Require manual approval for deploys
```

### 3.4 Validation Script

**File:** `app-files/scripts/validate-content.py`

```python
#!/usr/bin/env python3
import json
import jsonschema
from pathlib import Path

def validate():
    schemas_dir = Path("schemas")
    src_dir = Path("src")

    # Validate networks.json
    networks = json.loads((src_dir / "networks.json").read_text())
    schema = json.loads((schemas_dir / "networks.schema.json").read_text())
    jsonschema.validate(networks, schema)
    print("✓ networks.json valid")

    # Validate locales
    locale_schema = json.loads((schemas_dir / "locale.schema.json").read_text())
    for locale_file in (src_dir / "locales").glob("*.json"):
        locale = json.loads(locale_file.read_text())
        jsonschema.validate(locale, locale_schema)
        print(f"✓ {locale_file.name} valid")

    print("\nAll content validated successfully!")

if __name__ == "__main__":
    validate()
```

---

## Phase 4: Platform Integration

**Goal:** Integrate content updates into iOS, Android, and Desktop apps.

### 4.1 iOS Integration

**File:** `ios/Vauchi/Services/ContentUpdateService.swift`

```swift
import Foundation

class ContentUpdateService: ObservableObject {
    @Published var updateAvailable = false
    @Published var isUpdating = false

    private let vauchi: VauchiHandle

    init(vauchi: VauchiHandle) {
        self.vauchi = vauchi
    }

    func checkForUpdates() async {
        let status = checkContentUpdates(handle: vauchi)
        await MainActor.run {
            updateAvailable = status.hasUpdates
        }
    }

    func applyUpdates() async throws {
        await MainActor.run { isUpdating = true }
        defer { Task { await MainActor.run { isUpdating = false } } }

        let result = applyContentUpdates(handle: vauchi)
        if case .error(let msg) = result {
            throw ContentUpdateError.failed(msg)
        }
    }
}
```

**Settings UI addition:**

```swift
// In SettingsView.swift
Section("Content Updates") {
    Toggle("Auto-update content", isOn: $settings.remoteUpdatesEnabled)

    if contentService.updateAvailable {
        Button("Update Now") {
            Task { try? await contentService.applyUpdates() }
        }
    }

    Text("Last checked: \(settings.lastContentCheck.formatted())")
        .font(.caption)
        .foregroundColor(.secondary)
}
```

### 4.2 Android Integration

**File:** `android/app/src/main/kotlin/com/vauchi/services/ContentUpdateService.kt`

```kotlin
class ContentUpdateService(
    private val vauchi: VauchiHandle,
    private val context: Context
) {
    private val _updateAvailable = MutableStateFlow(false)
    val updateAvailable: StateFlow<Boolean> = _updateAvailable.asStateFlow()

    suspend fun checkForUpdates() = withContext(Dispatchers.IO) {
        val status = checkContentUpdates(vauchi)
        _updateAvailable.value = status.hasUpdates
    }

    suspend fun applyUpdates(): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching {
            val result = applyContentUpdates(vauchi)
            if (result.isError) {
                throw ContentUpdateException(result.errorMessage)
            }
        }
    }

    // Schedule periodic checks with WorkManager
    fun schedulePeriodicChecks() {
        val request = PeriodicWorkRequestBuilder<ContentUpdateWorker>(
            1, TimeUnit.HOURS
        ).setConstraints(
            Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
        ).build()

        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(
                "content_update_check",
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
    }
}
```

### 4.3 Desktop Integration

**File:** `desktop/ui/src/services/contentUpdates.ts`

```typescript
import { invoke } from '@tauri-apps/api/tauri';

export interface UpdateStatus {
  hasUpdates: boolean;
  types: string[];
}

export async function checkContentUpdates(): Promise<UpdateStatus> {
  return await invoke('check_content_updates');
}

export async function applyContentUpdates(): Promise<void> {
  await invoke('apply_content_updates');
}

// In Settings.tsx
const ContentUpdateSettings = () => {
  const [updateAvailable, setUpdateAvailable] = createSignal(false);
  const [isUpdating, setIsUpdating] = createSignal(false);

  const checkUpdates = async () => {
    const status = await checkContentUpdates();
    setUpdateAvailable(status.hasUpdates);
  };

  const applyUpdates = async () => {
    setIsUpdating(true);
    try {
      await applyContentUpdates();
      setUpdateAvailable(false);
    } finally {
      setIsUpdating(false);
    }
  };

  onMount(() => checkUpdates());

  return (
    <section>
      <h3>Content Updates</h3>
      <label>
        <input
          type="checkbox"
          checked={settings().remoteUpdatesEnabled}
          onChange={(e) => updateSetting('remoteUpdatesEnabled', e.target.checked)}
        />
        Auto-update content
      </label>

      {updateAvailable() && (
        <button onClick={applyUpdates} disabled={isUpdating()}>
          {isUpdating() ? 'Updating...' : 'Update Now'}
        </button>
      )}
    </section>
  );
};
```

---

## Phase 5: Locales & Help (Future)

**Deferred until Phase 1-4 complete.**

### 5.1 Locales Integration

- Integrate with planned i18n system (`_docs/planning/todo/2026-01-20-internationalization-implementation.md`)
- Remote locales supplement bundled translations
- Fallback chain: cached → bundled → English

### 5.2 Help Content Integration

- Integrate with planned help system (`features/ideas/in-app-help.md`)
- Structured JSON format for FAQ, hints, onboarding
- Markdown content with i18n keys

### 5.3 Themes Integration

- Define theme schema (color palette only, not layout)
- Apply via CSS variables (desktop) and platform theme APIs

---

## Testing Strategy

### Unit Tests (vauchi-core)

| Component | Tests |
|-----------|-------|
| `integrity.rs` | Checksum computation, verification, format validation |
| `cache.rs` | Read/write, atomic operations, missing files |
| `types.rs` | Manifest parsing, version comparison |
| `manager.rs` | Resolution order, fallback behavior |

### Integration Tests

| Test | Description |
|------|-------------|
| Offline mode | App works with only bundled content |
| Cache persistence | Content survives app restart |
| Update flow | Manifest check → download → verify → cache |
| Version compatibility | `min_app_version` enforcement |

### E2E Tests

**File:** `e2e/tests/remote_content/`

| Test | Description |
|------|-------------|
| `test_networks_update.rs` | Full flow: old networks → update → new network appears |
| `test_offline_fallback.rs` | Network failure uses cached/bundled |
| `test_checksum_rejection.rs` | Corrupted content is rejected |

---

## Rollout Plan

### Phase 1: Internal Testing
- Deploy content to staging URL
- Test with debug builds
- Verify all platforms

### Phase 2: Beta Release
- Deploy to production URL
- Release to TestFlight / Play Beta
- Monitor for issues

### Phase 3: Production Release
- Full app store release
- Monitor content update adoption
- Gather feedback

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| CDN outage | Bundled fallback always works |
| Malicious content | Checksum verification, HTTPS |
| Schema mismatch | `min_app_version` enforcement |
| Large downloads | Size limits, WiFi preference setting |
| Update loop | Exponential backoff on failures |

---

## Success Metrics

1. **Adoption rate**: % of users with latest content version
2. **Update latency**: Time from deploy to 50% adoption
3. **Failure rate**: % of failed update attempts
4. **Fallback usage**: % of requests served from bundled content

---

## Dependencies

### External
- `reqwest` crate (optional feature)
- GitLab CI/CD
- Static file hosting (vauchi.app)

### Internal
- Existing `VauchiConfig` and storage system
- Existing Tor proxy support
- Mobile FFI bindings (UniFFI)

---

## Timeline

| Phase | Scope | Dependency |
|-------|-------|------------|
| **Phase 1** | Core infrastructure | None |
| **Phase 2** | Networks migration | Phase 1 |
| **Phase 3** | Hosting infrastructure | Phase 1 |
| **Phase 4** | Platform integration | Phase 2, 3 |
| **Phase 5** | Locales & Help | Phase 4, i18n planning |

---

## Open Decisions

1. **Signing**: Add Ed25519 signatures in addition to checksums?
2. **Compression**: Gzip content files for smaller downloads?
3. **Delta updates**: Send only changed portions of files?
4. **Notification**: Notify user when updates are applied?
