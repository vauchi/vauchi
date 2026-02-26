---
name: desktop-stack
description: Tauri + SolidJS desktop app conventions, IPC commands, i18n, theming, and build/test commands. Use when working on the desktop/ repo.
model: haiku
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi Desktop Stack (Tauri + SolidJS)

## Directory Layout

```
desktop/
├── src-tauri/
│   ├── Cargo.toml           # Tauri 2 + vauchi-core (content-updates)
│   ├── tauri.conf.json      # Window: 800x400, min 400x500
│   ├── .cargo/config.toml   # Path override: ../../core/vauchi-core
│   └── src/
│       ├── lib.rs           # 48 Tauri commands registered
│       ├── state.rs         # AppState (Mutex<Identity + Storage>)
│       └── commands/        # Command modules
│           ├── identity.rs
│           ├── card.rs
│           ├── contacts.rs
│           ├── exchange.rs
│           ├── visibility.rs
│           ├── labels.rs
│           ├── devices.rs
│           ├── backup.rs
│           ├── recovery.rs
│           ├── sync.rs
│           ├── content.rs
│           ├── theme.rs
│           ├── i18n.rs
│           ├── help.rs
│           └── actions.rs
└── ui/
    ├── package.json
    ├── vite.config.ts
    ├── tsconfig.json
    └── src/
        ├── main.tsx         # Entry point
        ├── App.tsx          # Root with page routing
        ├── pages/           # 8 pages
        │   ├── Home.tsx     # Card management + visibility
        │   ├── Contacts.tsx
        │   ├── Exchange.tsx # QR code exchange
        │   ├── Settings.tsx
        │   ├── Devices.tsx
        │   ├── Recovery.tsx
        │   ├── Help.tsx
        │   └── Setup.tsx    # Identity creation
        ├── services/
        │   ├── i18nService.ts
        │   ├── themeService.ts
        │   └── helpService.ts
        └── styles/
            └── app.css      # Single CSS file, CSS variables
```

## IPC Pattern

**Frontend → Backend:**
```typescript
import { invoke } from '@tauri-apps/api/core';
const result = await invoke('command_name', { arg1, arg2 });
```

**Backend command:**
```rust
#[tauri::command]
fn get_card(state: State<Mutex<AppState>>) -> Result<CardData, String> {
    let state = state.lock().unwrap();
    // ... return Result<T, String>
}
```

All errors serialize to `String` for IPC transport.

### Command Reference (48 commands)

| Module | Commands |
|--------|----------|
| `identity` | `has_identity`, `create_identity`, `get_identity_info`, `update_display_name` |
| `card` | `get_card`, `add_field`, `remove_field`, `update_field` |
| `contacts` | `list_contacts`, `get_contact`, `remove_contact`, `get_contact_fingerprint`, `verify_contact` |
| `exchange` | `generate_qr`, `complete_exchange` |
| `visibility` | `get_visibility_rules`, `set_field_visibility`, `get_field_viewers` |
| `labels` | `list_labels`, `create_label`, `set_label_field_visibility`, `get_suggested_labels` (9 total) |
| `devices` | `list_devices`, `generate_device_link`, `join_device`, `complete_device_link`, `revoke_device` |
| `backup` | `export_backup`, `import_backup`, `check_password_strength` |
| `recovery` | `get_recovery_settings`, `create_recovery_claim`, `check_recovery_claim`, `parse_recovery_claim` |
| `sync` | `sync`, `get_sync_status`, `get_relay_url`, `set_relay_url` |
| `content` | `check_content_updates`, `apply_content_updates`, `get_social_networks` |
| `theme` | `get_available_themes`, `get_theme`, `get_default_theme_id` |
| `i18n` | `get_locales`, `get_localized_string`, `get_locale_strings` |
| `help` | `get_help_categories`, `get_all_faqs`, `search_help` |
| `actions` | `open_contact_field`, `get_field_action` |

## AppState

```rust
// src-tauri/src/state.rs
// Manages SQLite connection + Identity in memory
// Thread-safe: Arc<Mutex<AppState>>
// Data dir: VAUCHI_DATA_DIR env > system data dir > "."
```

## i18n

**Dual-mode service** (`ui/src/services/i18nService.ts`):

```typescript
// 1. Load all strings on startup (sync after that)
await loadStrings();
t('home.greeting');                    // Sync lookup
tArgs('home.greeting', { name });     // With interpolation

// 2. Async fallback
await tAsync('key');
```

- Locale saved to `localStorage['selected-locale']`
- Browser language detection fallback (en, de, fr, es)
- RTL support: sets `document.documentElement.dir`
- Backend delegates to `vauchi_core::i18n`

## Theming

```typescript
// services/themeService.ts
interface Theme {
  id: string; name: string; mode: 'light' | 'dark';
  colors: { bg_primary, bg_secondary, text_primary, accent, ... }
}
```

- Fetched via `invoke('get_theme', { themeId })`
- Applied as CSS custom properties on `:root`
- Saved to `localStorage['selected-theme']`
- Respects `prefers-color-scheme`

## CSS Conventions

- **Single file**: `ui/src/styles/app.css`
- **CSS custom properties**: `--bg-primary`, `--accent`, `--text-primary`, etc.
- **Dark-first** design, light via system preference
- **Accessibility**:
  - `--min-touch-target: 44px` (WCAG 2.1)
  - `--focus-ring-width: 2px`
  - `.sr-only` for screen readers
  - `data-reduce-motion`, `data-high-contrast`, `data-large-touch-targets`
- **Class naming**: kebab-case (`.field-item`, `.dialog-overlay`)

## SolidJS Component Pattern

```typescript
interface PageProps {
  onNavigate: (page: string) => void;
}

function Home(props: PageProps) {
  const [data, setData] = createSignal(initial);
  const [resource] = createResource(fetchFn);
  return <div>...</div>;
}

export default Home;
```

**Page routing**: String-based via `App.tsx` (kebab-case: `'home'`, `'contacts'`, `'exchange'`)

## Naming Conventions

| Context | Convention | Example |
|---------|-----------|---------|
| Components | PascalCase | `Home.tsx`, `Setup.tsx` |
| Services | camelCase | `i18nService.ts`, `themeService.ts` |
| Rust commands | snake_case | `get_identity_info` |
| CSS classes | kebab-case | `.field-item`, `.visibility-dialog` |
| i18n keys | dot-notation | `'home.greeting'`, `'nav.home'` |
| Page routes | kebab-case strings | `'home'`, `'contacts'` |

## Build & Test Commands

```bash
# Development
just desktop-dev                   # Dev mode with Vite hot reload

# Build
just build desktop                 # Production binary
just build desktop-ui              # Frontend only

# Test
just test desktop                  # All desktop tests (Rust + frontend)
just test desktop-ui               # Playwright E2E only

# Lint & Check
just lint desktop                  # All desktop linting
just check desktop                 # fmt + lint + test (all-in-one)
just fix desktop                   # Auto-fix formatting + lint

# Visual regression (no just recipe — use npm directly)
cd desktop/ui && npm run test:visual
cd desktop/ui && npm run test:update-snapshots
```

> **Note**: For visual regression tests and snapshot updates, use npm directly since `just` has no dedicated recipe for these.

## PITFALL: Frontend Must Build Before Clippy

Tauri's `generate_context!` macro reads `ui/dist/`. Clippy fails without a built frontend:

```bash
# CI handles this with job dependency:
# lint:clippy needs: [build:frontend-dist]
```

Locally: run `cd ui && npm run build` before `cargo clippy` in `src-tauri/`.

## Test Server

If `VAUCHI_TEST_PORT` env var is set, spawns HTTP test server in same process with separate `AppState` pointing to same SQLite DB.
