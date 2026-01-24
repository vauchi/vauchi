# Selective Downloads Strategy

**Created:** 2026-01-24
**Goal:** Minimize app storage and bandwidth by downloading only what the user needs

---

## Problem

Downloading all content on every update wastes bandwidth and storage:

| Content Type | Full Download | Selective |
|-------------|---------------|-----------|
| **Locales** | 10 languages × ~10KB = 100KB | 1 language × 10KB = **10KB** |
| **Themes** | 12 themes × ~1.5KB = 18KB | 1 theme × 1.5KB = **1.5KB** |
| **Help** | 10 languages × ~20KB = 200KB | 1 language × 20KB = **20KB** |
| **Total** | ~320KB | **~32KB** (90% smaller) |

On mobile with limited data plans, this matters.

---

## Solution: On-Demand Downloads

### Principle

> **Download only what the user explicitly selects. Bundle minimal fallbacks.**

### Bundled Content (Always Available)

```
Bundled in app binary:
├── locales/en.json          # English always available
├── themes/default-dark.json # Default theme always available
├── themes/default-light.json
└── help/en.json             # English help always available
```

**Size impact:** ~35KB added to binary (acceptable)

### Downloaded on Demand

```
Downloaded when user selects:
├── locales/{lang}.json      # When user changes language
├── themes/{theme}.json      # When user selects theme
└── help/{lang}.json         # When user changes language
```

---

## Manifest Schema (Updated)

The manifest lists all available content, but apps only download what's needed:

```json
{
  "schema_version": 1,
  "content": {
    "locales": {
      "version": "1.0.0",
      "path": "locales/v1/",
      "bundled": ["en"],
      "files": {
        "en": { "path": "en.json", "checksum": "sha256:...", "size_bytes": 8200 },
        "de": { "path": "de.json", "checksum": "sha256:...", "size_bytes": 8500 },
        "fr": { "path": "fr.json", "checksum": "sha256:...", "size_bytes": 8300 },
        "es": { "path": "es.json", "checksum": "sha256:...", "size_bytes": 8100 },
        "ja": { "path": "ja.json", "checksum": "sha256:...", "size_bytes": 12000 },
        "zh-Hans": { "path": "zh-Hans.json", "checksum": "sha256:...", "size_bytes": 9500 },
        "ar": { "path": "ar.json", "checksum": "sha256:...", "size_bytes": 8800 }
      },
      "min_app_version": "1.0.0"
    },
    "themes": {
      "version": "1.0.0",
      "path": "themes/v1/",
      "bundled": ["default-dark", "default-light"],
      "files": {
        "default-dark": { "path": "default-dark.json", "checksum": "sha256:...", "size_bytes": 800 },
        "default-light": { "path": "default-light.json", "checksum": "sha256:...", "size_bytes": 800 },
        "catppuccin-mocha": { "path": "catppuccin-mocha.json", "checksum": "sha256:...", "size_bytes": 1500 },
        "catppuccin-latte": { "path": "catppuccin-latte.json", "checksum": "sha256:...", "size_bytes": 1500 },
        "catppuccin-frappe": { "path": "catppuccin-frappe.json", "checksum": "sha256:...", "size_bytes": 1500 },
        "catppuccin-macchiato": { "path": "catppuccin-macchiato.json", "checksum": "sha256:...", "size_bytes": 1500 },
        "dracula": { "path": "dracula.json", "checksum": "sha256:...", "size_bytes": 800 },
        "nord": { "path": "nord.json", "checksum": "sha256:...", "size_bytes": 800 },
        "solarized-dark": { "path": "solarized-dark.json", "checksum": "sha256:...", "size_bytes": 800 },
        "solarized-light": { "path": "solarized-light.json", "checksum": "sha256:...", "size_bytes": 800 },
        "gruvbox-dark": { "path": "gruvbox-dark.json", "checksum": "sha256:...", "size_bytes": 800 },
        "gruvbox-light": { "path": "gruvbox-light.json", "checksum": "sha256:...", "size_bytes": 800 }
      },
      "min_app_version": "1.0.0"
    },
    "help": {
      "version": "1.0.0",
      "path": "help/v1/",
      "bundled": ["en"],
      "files": {
        "en": { "path": "en.json", "checksum": "sha256:...", "size_bytes": 15000 },
        "de": { "path": "de.json", "checksum": "sha256:...", "size_bytes": 16000 },
        "fr": { "path": "fr.json", "checksum": "sha256:...", "size_bytes": 15500 }
      },
      "min_app_version": "1.0.0"
    },
    "networks": {
      "version": "1.0.0",
      "path": "networks/v1/networks.json",
      "checksum": "sha256:...",
      "size_bytes": 12450,
      "min_app_version": "1.0.0"
    }
  }
}
```

Key additions:
- `bundled` array indicates which files are included in the app binary
- Apps skip downloading bundled content unless a newer version exists

---

## Download Triggers

### 1. Language Change

```
User selects German (de)
    │
    ├─► Is de.json cached? ─► YES ─► Use cached
    │
    └─► NO ─► Download de.json
              └─► Also download help/de.json if available
```

**UX:** Show download progress, allow cancel, fallback to English if fails.

### 2. Theme Selection

```
User selects Catppuccin Mocha
    │
    ├─► Is theme cached? ─► YES ─► Apply immediately
    │
    └─► NO ─► Download theme
              └─► Apply after download
              └─► Show preview with placeholder colors during download
```

**UX:** Show "Downloading theme..." with progress indicator.

### 3. Background Updates

```
App checks manifest (hourly)
    │
    ├─► New version of user's CURRENT language? ─► Download in background
    │
    ├─► New version of user's CURRENT theme? ─► Download in background
    │
    └─► New content available user hasn't selected? ─► Do NOT download
```

**Key:** Only auto-update content the user is actively using.

---

## Implementation

### ContentManager API

```rust
impl ContentManager {
    /// Get available locales (from manifest, not downloaded)
    pub fn available_locales(&self) -> Vec<LocaleMeta> {
        self.manifest.locales.files.keys()
            .map(|id| LocaleMeta {
                id: id.clone(),
                name: locale_display_name(id),
                downloaded: self.cache.has_locale(id),
                bundled: self.manifest.locales.bundled.contains(id),
            })
            .collect()
    }

    /// Get locale strings - downloads if needed
    pub async fn locale(&self, lang: &str) -> Result<LocaleStrings, ContentError> {
        // 1. Check cache
        if let Some(cached) = self.cache.get_locale(lang) {
            return Ok(cached);
        }

        // 2. Check bundled
        if self.bundled.has_locale(lang) {
            return Ok(self.bundled.locale(lang));
        }

        // 3. Download
        let entry = self.manifest.locales.files.get(lang)
            .ok_or(ContentError::NotAvailable)?;

        let data = self.fetcher.fetch_content(&entry.path, &entry.checksum).await?;
        self.cache.save_locale(lang, &data, &entry.checksum)?;

        Ok(serde_json::from_slice(&data)?)
    }

    /// Get available themes (metadata only)
    pub fn available_themes(&self) -> Vec<ThemeMeta> {
        self.manifest.themes.files.keys()
            .map(|id| ThemeMeta {
                id: id.clone(),
                name: theme_display_name(id),
                mode: theme_mode(id),
                downloaded: self.cache.has_theme(id),
                bundled: self.manifest.themes.bundled.contains(id),
            })
            .collect()
    }

    /// Get theme - downloads if needed
    pub async fn theme(&self, id: &str) -> Result<Theme, ContentError> {
        // Same pattern: cache → bundled → download
    }

    /// Pre-download content for offline use
    pub async fn download_for_offline(&self, items: &[ContentItem]) -> Result<(), ContentError> {
        for item in items {
            match item {
                ContentItem::Locale(lang) => { self.locale(lang).await?; }
                ContentItem::Theme(id) => { self.theme(id).await?; }
                ContentItem::Help(lang) => { self.help(lang).await?; }
            }
        }
        Ok(())
    }
}
```

### UI Integration

#### Settings > Language

```
┌─────────────────────────────────────┐
│ Language                            │
├─────────────────────────────────────┤
│ ● English (System)           [✓]   │
│ ○ Deutsch                    [↓]   │  ← Download icon
│ ○ Français                   [↓]   │
│ ○ Español                    [↓]   │
│ ○ 日本語                      [↓]   │
│ ○ 中文 (简体)                  [↓]   │
│ ○ العربية                    [↓]   │
└─────────────────────────────────────┘

[↓] = Not downloaded, tap to download
[✓] = Downloaded/bundled
```

#### Settings > Appearance > Theme

```
┌─────────────────────────────────────┐
│ Theme                               │
├─────────────────────────────────────┤
│ BUNDLED                             │
│ ┌─────┐ ┌─────┐                    │
│ │ ██  │ │ ░░  │                    │
│ │Dark │ │Light│  ← Always available │
│ └─────┘ └─────┘                    │
│                                     │
│ CATPPUCCIN                    [↓]  │  ← Download all flavors
│ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐   │
│ │Mocha│ │Macch│ │Frapp│ │Latte│   │
│ └─────┘ └─────┘ └─────┘ └─────┘   │
│                                     │
│ OTHER                               │
│ ┌─────┐ ┌─────┐ ┌─────┐           │
│ │Dracu│ │Nord │ │Solar│  [↓] each │
│ └─────┘ └─────┘ └─────┘           │
└─────────────────────────────────────┘
```

---

## Offline Mode

### "Download for Offline" Feature

Settings > Storage > Offline Content

```
┌─────────────────────────────────────┐
│ Offline Content                     │
├─────────────────────────────────────┤
│ Downloaded content is available     │
│ even without internet connection.   │
│                                     │
│ Currently downloaded:        1.2 MB │
│ ├─ English locale             10 KB │
│ ├─ German locale              11 KB │
│ ├─ Default Dark theme          1 KB │
│ ├─ Catppuccin Mocha            2 KB │
│ └─ Social networks            13 KB │
│                                     │
│ [Download all languages]     +95 KB │
│ [Download all themes]        +15 KB │
│                                     │
│ [Clear downloaded content]          │
└─────────────────────────────────────┘
```

---

## Storage Management

### Cache Structure

```
{storage_path}/content/
├── manifest.json           # Current manifest
├── locales/
│   ├── en.json            # Downloaded
│   └── de.json            # Downloaded
├── themes/
│   └── catppuccin-mocha.json
├── help/
│   └── en.json
└── networks.json
```

### Cleanup Rules

1. **Never delete currently selected** language/theme
2. **Delete unused after 30 days** (configurable)
3. **User can manually clear** in settings

---

## Bandwidth Considerations

### Conditional Requests

Use `If-None-Match` / `ETag` headers:

```http
GET /app-files/locales/v1/de.json
If-None-Match: "abc123"

→ 304 Not Modified (no body, ~200 bytes)
```

Only download when content actually changed.

### Size Hints in Manifest

Show download size before user commits:

```
Download German?
~11 KB required

[Download] [Cancel]
```

---

## Updated Feature Scenarios

Add to `features/remote-content.feature`:

```gherkin
@selective
Scenario: Download only selected language
  Given the user's language is set to English
  And German locale is available remotely
  When the user changes language to German
  Then German locale should be downloaded
  And French locale should not be downloaded
  And Spanish locale should not be downloaded

@selective
Scenario: Download only selected theme
  Given the user has default dark theme
  And Catppuccin themes are available remotely
  When the user selects Catppuccin Mocha
  Then Catppuccin Mocha theme should be downloaded
  And Dracula theme should not be downloaded
  And Nord theme should not be downloaded

@selective @offline
Scenario: Bundled content available without download
  Given the device is offline
  And no content has been downloaded
  When the user opens the app
  Then English locale should be available
  And default themes should be available
  And the app should function normally

@selective
Scenario: Show download indicator for unavailable content
  Given German locale is not downloaded
  When the user views language settings
  Then German should show a download indicator
  And English should show as available

@selective @background
Scenario: Only update actively used content
  Given the user has German locale downloaded
  And the user has Catppuccin Mocha theme downloaded
  And new versions are available for all content
  When the app checks for updates
  Then only German locale should be updated
  And only Catppuccin Mocha should be updated
  And other content should not be downloaded
```

---

## Summary

| Aspect | Before | After |
|--------|--------|-------|
| Initial download | All content (~320KB) | Nothing (bundled only) |
| Language change | Already downloaded | Download ~10KB on demand |
| Theme change | Already downloaded | Download ~1.5KB on demand |
| Background updates | All content | Only user's selections |
| Offline capability | Full | English + default theme |

**Result:** 90% bandwidth reduction for typical users, minimal storage footprint.
