# Theming Implementation Plan

**Parent:** Remote Content Updates
**Created:** 2026-01-24
**Priority:** MEDIUM

---

## Overview

Implement a theming system that supports popular open-source color schemes (Catppuccin, Dracula, Nord, Solarized, Gruvbox) with remote updates capability.

### Goals

1. Support multiple color themes across all platforms
2. Include Catppuccin (all 4 flavors) as primary theme option
3. Enable remote theme updates without app releases
4. Maintain accessibility (contrast ratios, high contrast mode)
5. Respect system dark/light mode preferences

---

## Theme Schema

### Theme File Format

```json
{
  "id": "catppuccin-mocha",
  "name": "Catppuccin Mocha",
  "version": "1.0.0",
  "author": "Catppuccin",
  "license": "MIT",
  "source": "https://github.com/catppuccin/catppuccin",
  "mode": "dark",

  "colors": {
    "bg-primary": "#1e1e2e",
    "bg-secondary": "#181825",
    "bg-tertiary": "#313244",
    "text-primary": "#cdd6f4",
    "text-secondary": "#a6adc8",
    "accent": "#89b4fa",
    "accent-dark": "#74c7ec",
    "success": "#a6e3a1",
    "error": "#f38ba8",
    "warning": "#fab387",
    "border": "#45475a"
  },

  "palette": {
    "rosewater": "#f5e0dc",
    "flamingo": "#f2cdcd",
    "pink": "#f5c2e7",
    "mauve": "#cba6f7",
    "red": "#f38ba8",
    "maroon": "#eba0ac",
    "peach": "#fab387",
    "yellow": "#f9e2af",
    "green": "#a6e3a1",
    "teal": "#94e2d5",
    "sky": "#89dceb",
    "sapphire": "#74c7ec",
    "blue": "#89b4fa",
    "lavender": "#b4befe",
    "text": "#cdd6f4",
    "subtext1": "#bac2de",
    "subtext0": "#a6adc8",
    "overlay2": "#9399b2",
    "overlay1": "#7f849c",
    "overlay0": "#6c7086",
    "surface2": "#585b70",
    "surface1": "#45475a",
    "surface0": "#313244",
    "base": "#1e1e2e",
    "mantle": "#181825",
    "crust": "#11111b"
  }
}
```

### Color Mapping Strategy

Map open-source theme palettes to Vauchi's CSS variables:

| Vauchi Variable | Catppuccin | Dracula | Nord | Solarized Dark |
|----------------|------------|---------|------|----------------|
| `--bg-primary` | base | #282a36 | nord0 | base03 |
| `--bg-secondary` | mantle | #21222c | nord1 | base02 |
| `--bg-tertiary` | surface0 | #44475a | nord2 | base01 |
| `--text-primary` | text | #f8f8f2 | nord4 | base0 |
| `--text-secondary` | subtext0 | #6272a4 | nord3 | base01 |
| `--accent` | blue | #bd93f9 | nord8 | blue |
| `--accent-dark` | sapphire | #ff79c6 | nord9 | cyan |
| `--success` | green | #50fa7b | nord14 | green |
| `--error` | red | #ff5555 | nord11 | red |
| `--warning` | peach | #ffb86c | nord13 | yellow |
| `--border` | surface1 | #44475a | nord3 | base01 |

---

## Bundled Themes

### Core Themes (Always Available)

```
themes/
├── default-dark.json      # Current Vauchi dark theme
├── default-light.json     # Light variant
└── high-contrast.json     # Accessibility theme
```

### Remote Themes (Downloaded)

```
vauchi.app/app-files/themes/v1/
├── catppuccin-latte.json
├── catppuccin-frappe.json
├── catppuccin-macchiato.json
├── catppuccin-mocha.json
├── dracula.json
├── nord.json
├── solarized-dark.json
├── solarized-light.json
├── gruvbox-dark.json
├── gruvbox-light.json
└── tokyo-night.json
```

---

## Implementation

### 1. Core Theme Types

**File:** `core/vauchi-core/src/content/themes.rs`

```rust
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Theme {
    pub id: String,
    pub name: String,
    pub version: String,
    pub author: Option<String>,
    pub license: Option<String>,
    pub source: Option<String>,
    pub mode: ThemeMode,
    pub colors: ThemeColors,
    #[serde(default)]
    pub palette: HashMap<String, String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ThemeMode {
    Light,
    Dark,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ThemeColors {
    #[serde(rename = "bg-primary")]
    pub bg_primary: String,
    #[serde(rename = "bg-secondary")]
    pub bg_secondary: String,
    #[serde(rename = "bg-tertiary")]
    pub bg_tertiary: String,
    #[serde(rename = "text-primary")]
    pub text_primary: String,
    #[serde(rename = "text-secondary")]
    pub text_secondary: String,
    pub accent: String,
    #[serde(rename = "accent-dark")]
    pub accent_dark: String,
    pub success: String,
    pub error: String,
    pub warning: String,
    pub border: String,
}

impl Theme {
    /// Validate theme has sufficient contrast ratios
    pub fn validate_accessibility(&self) -> Result<(), ThemeValidationError> {
        let bg = parse_hex(&self.colors.bg_primary)?;
        let text = parse_hex(&self.colors.text_primary)?;

        let ratio = contrast_ratio(bg, text);
        if ratio < 4.5 {
            return Err(ThemeValidationError::InsufficientContrast {
                actual: ratio,
                required: 4.5,
            });
        }

        Ok(())
    }
}

/// Calculate WCAG contrast ratio between two colors
fn contrast_ratio(c1: (u8, u8, u8), c2: (u8, u8, u8)) -> f64 {
    let l1 = relative_luminance(c1);
    let l2 = relative_luminance(c2);
    let (lighter, darker) = if l1 > l2 { (l1, l2) } else { (l2, l1) };
    (lighter + 0.05) / (darker + 0.05)
}
```

### 2. Theme Manager

**File:** `core/vauchi-core/src/content/theme_manager.rs`

```rust
pub struct ThemeManager {
    current_theme: Theme,
    available_themes: Vec<ThemeMeta>,
    system_mode: ThemeMode,
    cache: ContentCache,
}

#[derive(Debug, Clone)]
pub struct ThemeMeta {
    pub id: String,
    pub name: String,
    pub mode: ThemeMode,
    pub bundled: bool,
}

impl ThemeManager {
    pub fn new(cache: &ContentCache) -> Self {
        let bundled = Self::load_bundled_themes();
        let cached = Self::load_cached_themes(cache);

        let available = bundled.into_iter()
            .chain(cached.into_iter())
            .map(|t| ThemeMeta {
                id: t.id.clone(),
                name: t.name.clone(),
                mode: t.mode,
                bundled: false, // TODO: track this
            })
            .collect();

        Self {
            current_theme: Self::default_theme(),
            available_themes: available,
            system_mode: ThemeMode::Dark,
            cache: cache.clone(),
        }
    }

    /// Get list of available themes
    pub fn available_themes(&self) -> &[ThemeMeta] {
        &self.available_themes
    }

    /// Get current theme
    pub fn current(&self) -> &Theme {
        &self.current_theme
    }

    /// Apply a theme by ID
    pub fn apply(&mut self, theme_id: &str) -> Result<(), ThemeError> {
        let theme = self.load_theme(theme_id)?;
        theme.validate_accessibility()?;
        self.current_theme = theme;
        Ok(())
    }

    /// Set system dark/light mode
    pub fn set_system_mode(&mut self, mode: ThemeMode) {
        self.system_mode = mode;
    }

    /// Get themes matching current system mode
    pub fn themes_for_mode(&self, mode: ThemeMode) -> Vec<&ThemeMeta> {
        self.available_themes.iter()
            .filter(|t| t.mode == mode)
            .collect()
    }

    fn load_bundled_themes() -> Vec<Theme> {
        vec![
            serde_json::from_str(include_str!("../../themes/default-dark.json")).unwrap(),
            serde_json::from_str(include_str!("../../themes/default-light.json")).unwrap(),
        ]
    }
}
```

### 3. Platform Integration

#### Desktop (CSS Custom Properties)

**File:** `desktop/ui/src/services/theme.ts`

```typescript
import { Theme } from '../types';

export function applyTheme(theme: Theme): void {
  const root = document.documentElement;

  // Apply all color variables
  Object.entries(theme.colors).forEach(([key, value]) => {
    root.style.setProperty(`--${key}`, value);
  });

  // Set data attribute for mode-specific styles
  root.dataset.themeMode = theme.mode;

  // Store in localStorage
  localStorage.setItem('selected-theme', theme.id);
}

export function getStoredThemeId(): string | null {
  return localStorage.getItem('selected-theme');
}
```

**File:** `desktop/ui/src/pages/Settings.tsx` (addition)

```tsx
const ThemeSection = () => {
  const [themes, setThemes] = createSignal<ThemeMeta[]>([]);
  const [currentTheme, setCurrentTheme] = createSignal<string>('default-dark');

  onMount(async () => {
    const available = await invoke('get_available_themes');
    setThemes(available);
    setCurrentTheme(getStoredThemeId() || 'default-dark');
  });

  const handleThemeChange = async (themeId: string) => {
    const theme = await invoke('get_theme', { id: themeId });
    applyTheme(theme);
    setCurrentTheme(themeId);
  };

  return (
    <section aria-labelledby="theme-heading">
      <h2 id="theme-heading">Appearance</h2>

      <div class="theme-grid">
        <For each={themes()}>
          {(theme) => (
            <button
              class={`theme-option ${currentTheme() === theme.id ? 'selected' : ''}`}
              onClick={() => handleThemeChange(theme.id)}
              aria-pressed={currentTheme() === theme.id}
            >
              <div
                class="theme-preview"
                style={{
                  background: theme.preview?.bgPrimary,
                  color: theme.preview?.textPrimary,
                }}
              >
                <div class="preview-accent" style={{ background: theme.preview?.accent }} />
              </div>
              <span>{theme.name}</span>
            </button>
          )}
        </For>
      </div>
    </section>
  );
};
```

#### iOS (SwiftUI)

**File:** `ios/Vauchi/Theme/ThemeManager.swift`

```swift
import SwiftUI

class ThemeManager: ObservableObject {
    @Published var currentTheme: AppTheme = .default
    @AppStorage("selectedTheme") private var selectedThemeId: String = "default-dark"

    private let vauchi: VauchiHandle

    init(vauchi: VauchiHandle) {
        self.vauchi = vauchi
        loadSelectedTheme()
    }

    var availableThemes: [ThemeMeta] {
        getAvailableThemes(handle: vauchi)
    }

    func apply(_ themeId: String) {
        guard let theme = getTheme(handle: vauchi, id: themeId) else { return }
        currentTheme = AppTheme(from: theme)
        selectedThemeId = themeId
    }
}

struct AppTheme {
    let bgPrimary: Color
    let bgSecondary: Color
    let bgTertiary: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let accentDark: Color
    let success: Color
    let error: Color
    let warning: Color
    let border: Color

    static let `default` = AppTheme(
        bgPrimary: Color(hex: "#1a1a2e"),
        bgSecondary: Color(hex: "#16213e"),
        bgTertiary: Color(hex: "#0f3460"),
        textPrimary: Color(hex: "#eeeeee"),
        textSecondary: Color(hex: "#a0a0a0"),
        accent: Color(hex: "#4fc3f7"),
        accentDark: Color(hex: "#0288d1"),
        success: Color(hex: "#4caf50"),
        error: Color(hex: "#f44336"),
        warning: Color(hex: "#ff9800"),
        border: Color(hex: "#333333")
    )
}
```

#### Android (Jetpack Compose)

**File:** `android/app/src/main/kotlin/com/vauchi/ui/theme/DynamicTheme.kt`

```kotlin
@Composable
fun VauchiTheme(
    themeManager: ThemeManager = viewModel(),
    content: @Composable () -> Unit
) {
    val theme by themeManager.currentTheme.collectAsState()

    val colorScheme = ColorScheme(
        primary = Color(theme.accent.toColorInt()),
        onPrimary = Color(theme.bgPrimary.toColorInt()),
        primaryContainer = Color(theme.accentDark.toColorInt()),
        secondary = Color(theme.accent.toColorInt()),
        background = Color(theme.bgPrimary.toColorInt()),
        surface = Color(theme.bgSecondary.toColorInt()),
        surfaceVariant = Color(theme.bgTertiary.toColorInt()),
        onBackground = Color(theme.textPrimary.toColorInt()),
        onSurface = Color(theme.textPrimary.toColorInt()),
        onSurfaceVariant = Color(theme.textSecondary.toColorInt()),
        outline = Color(theme.border.toColorInt()),
        error = Color(theme.error.toColorInt()),
        // ... other colors
    )

    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
```

---

## Theme Files

### Catppuccin Mocha

**File:** `app-files/src/themes/catppuccin-mocha.json`

```json
{
  "id": "catppuccin-mocha",
  "name": "Catppuccin Mocha",
  "version": "1.0.0",
  "author": "Catppuccin",
  "license": "MIT",
  "source": "https://github.com/catppuccin/catppuccin",
  "mode": "dark",

  "colors": {
    "bg-primary": "#1e1e2e",
    "bg-secondary": "#181825",
    "bg-tertiary": "#313244",
    "text-primary": "#cdd6f4",
    "text-secondary": "#a6adc8",
    "accent": "#89b4fa",
    "accent-dark": "#74c7ec",
    "success": "#a6e3a1",
    "error": "#f38ba8",
    "warning": "#fab387",
    "border": "#45475a"
  },

  "palette": {
    "rosewater": "#f5e0dc",
    "flamingo": "#f2cdcd",
    "pink": "#f5c2e7",
    "mauve": "#cba6f7",
    "red": "#f38ba8",
    "maroon": "#eba0ac",
    "peach": "#fab387",
    "yellow": "#f9e2af",
    "green": "#a6e3a1",
    "teal": "#94e2d5",
    "sky": "#89dceb",
    "sapphire": "#74c7ec",
    "blue": "#89b4fa",
    "lavender": "#b4befe"
  }
}
```

### Catppuccin Latte (Light)

**File:** `app-files/src/themes/catppuccin-latte.json`

```json
{
  "id": "catppuccin-latte",
  "name": "Catppuccin Latte",
  "version": "1.0.0",
  "author": "Catppuccin",
  "license": "MIT",
  "source": "https://github.com/catppuccin/catppuccin",
  "mode": "light",

  "colors": {
    "bg-primary": "#eff1f5",
    "bg-secondary": "#e6e9ef",
    "bg-tertiary": "#ccd0da",
    "text-primary": "#4c4f69",
    "text-secondary": "#6c6f85",
    "accent": "#1e66f5",
    "accent-dark": "#209fb5",
    "success": "#40a02b",
    "error": "#d20f39",
    "warning": "#fe640b",
    "border": "#9ca0b0"
  }
}
```

### Dracula

**File:** `app-files/src/themes/dracula.json`

```json
{
  "id": "dracula",
  "name": "Dracula",
  "version": "1.0.0",
  "author": "Zeno Rocha",
  "license": "MIT",
  "source": "https://draculatheme.com",
  "mode": "dark",

  "colors": {
    "bg-primary": "#282a36",
    "bg-secondary": "#21222c",
    "bg-tertiary": "#44475a",
    "text-primary": "#f8f8f2",
    "text-secondary": "#6272a4",
    "accent": "#bd93f9",
    "accent-dark": "#ff79c6",
    "success": "#50fa7b",
    "error": "#ff5555",
    "warning": "#ffb86c",
    "border": "#44475a"
  }
}
```

### Nord

**File:** `app-files/src/themes/nord.json`

```json
{
  "id": "nord",
  "name": "Nord",
  "version": "1.0.0",
  "author": "Arctic Ice Studio",
  "license": "MIT",
  "source": "https://nordtheme.com",
  "mode": "dark",

  "colors": {
    "bg-primary": "#2e3440",
    "bg-secondary": "#3b4252",
    "bg-tertiary": "#434c5e",
    "text-primary": "#eceff4",
    "text-secondary": "#d8dee9",
    "accent": "#88c0d0",
    "accent-dark": "#81a1c1",
    "success": "#a3be8c",
    "error": "#bf616a",
    "warning": "#ebcb8b",
    "border": "#4c566a"
  }
}
```

### Solarized Dark

**File:** `app-files/src/themes/solarized-dark.json`

```json
{
  "id": "solarized-dark",
  "name": "Solarized Dark",
  "version": "1.0.0",
  "author": "Ethan Schoonover",
  "license": "MIT",
  "source": "https://ethanschoonover.com/solarized",
  "mode": "dark",

  "colors": {
    "bg-primary": "#002b36",
    "bg-secondary": "#073642",
    "bg-tertiary": "#586e75",
    "text-primary": "#839496",
    "text-secondary": "#657b83",
    "accent": "#268bd2",
    "accent-dark": "#2aa198",
    "success": "#859900",
    "error": "#dc322f",
    "warning": "#b58900",
    "border": "#073642"
  }
}
```

### Gruvbox Dark

**File:** `app-files/src/themes/gruvbox-dark.json`

```json
{
  "id": "gruvbox-dark",
  "name": "Gruvbox Dark",
  "version": "1.0.0",
  "author": "morhetz",
  "license": "MIT",
  "source": "https://github.com/morhetz/gruvbox",
  "mode": "dark",

  "colors": {
    "bg-primary": "#282828",
    "bg-secondary": "#3c3836",
    "bg-tertiary": "#504945",
    "text-primary": "#ebdbb2",
    "text-secondary": "#a89984",
    "accent": "#83a598",
    "accent-dark": "#8ec07c",
    "success": "#b8bb26",
    "error": "#fb4934",
    "warning": "#fabd2f",
    "border": "#504945"
  }
}
```

---

## Manifest Update

Add themes to content manifest:

```json
{
  "content": {
    "themes": {
      "version": "1.0.0",
      "path": "themes/v1/",
      "files": {
        "catppuccin-latte": { "path": "catppuccin-latte.json", "checksum": "sha256:...", "size_bytes": 1200 },
        "catppuccin-frappe": { "path": "catppuccin-frappe.json", "checksum": "sha256:...", "size_bytes": 1200 },
        "catppuccin-macchiato": { "path": "catppuccin-macchiato.json", "checksum": "sha256:...", "size_bytes": 1200 },
        "catppuccin-mocha": { "path": "catppuccin-mocha.json", "checksum": "sha256:...", "size_bytes": 1500 },
        "dracula": { "path": "dracula.json", "checksum": "sha256:...", "size_bytes": 800 },
        "nord": { "path": "nord.json", "checksum": "sha256:...", "size_bytes": 800 },
        "solarized-dark": { "path": "solarized-dark.json", "checksum": "sha256:...", "size_bytes": 800 },
        "solarized-light": { "path": "solarized-light.json", "checksum": "sha256:...", "size_bytes": 800 },
        "gruvbox-dark": { "path": "gruvbox-dark.json", "checksum": "sha256:...", "size_bytes": 800 },
        "gruvbox-light": { "path": "gruvbox-light.json", "checksum": "sha256:...", "size_bytes": 800 }
      },
      "min_app_version": "1.0.0"
    }
  }
}
```

---

## Testing

### Unit Tests

```rust
#[test]
fn test_catppuccin_mocha_contrast() {
    let theme: Theme = serde_json::from_str(include_str!("themes/catppuccin-mocha.json")).unwrap();
    assert!(theme.validate_accessibility().is_ok());
}

#[test]
fn test_all_themes_valid() {
    let themes = vec![
        include_str!("themes/catppuccin-mocha.json"),
        include_str!("themes/dracula.json"),
        include_str!("themes/nord.json"),
    ];

    for json in themes {
        let theme: Theme = serde_json::from_str(json).unwrap();
        assert!(theme.validate_accessibility().is_ok());
    }
}
```

### E2E Tests

```rust
#[test]
fn test_theme_selection_persists() {
    let app = TestApp::new();
    app.select_theme("catppuccin-mocha");
    app.restart();
    assert_eq!(app.current_theme().id, "catppuccin-mocha");
}
```

---

## Attribution & Licensing

All included themes are open-source. Attribution in settings:

```
Themes powered by:
• Catppuccin (MIT License) - catppuccin.com
• Dracula (MIT License) - draculatheme.com
• Nord (MIT License) - nordtheme.com
• Solarized (MIT License) - ethanschoonover.com/solarized
• Gruvbox (MIT License) - github.com/morhetz/gruvbox
```

---

## Future Enhancements

1. **Custom accent colors** - Allow users to pick accent from theme palette
2. **Theme import** - Import custom theme JSON files
3. **Scheduled themes** - Auto-switch based on time of day
4. **Per-contact themes** - Different colors for different contacts (visual identification)

---

## Dependencies

- Remote Content Updates (Phase 1-3)
- Content Manager in vauchi-core

## Sources

- [Catppuccin Palette](https://github.com/catppuccin/palette)
- [Dracula Theme](https://draculatheme.com)
- [Nord Theme](https://nordtheme.com)
- [Solarized](https://ethanschoonover.com/solarized)
- [Gruvbox](https://github.com/morhetz/gruvbox)
