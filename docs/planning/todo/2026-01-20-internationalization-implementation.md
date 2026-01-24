# P13: Internationalization Implementation

**Priority**: MEDIUM
**Status**: Planning
**Effort**: 2-3 weeks
**Feature File**: `features/internationalization.feature` (50 scenarios)

## Goal

Implement full internationalization support so Vauchi can be used comfortably in any language.

## Current State

| Platform | Localization | RTL Support | Locale Formatting |
|----------|--------------|-------------|-------------------|
| iOS | None (hardcoded English) | None | None |
| Android | Only `app_name` | None | None |
| Desktop | None | None | None |
| TUI | None | N/A | None |

## Target Languages (Phase 1)

| Language | Code | Priority |
|----------|------|----------|
| English | en | Source |
| German | de | P1 |
| French | fr | P1 |
| Spanish | es | P1 |

## Architecture

```
locales/                        # Source of truth
├── en.json
├── de.json
├── es.json
└── fr.json

dev-tools/scripts/
├── sync-locales.sh             # Master sync script
├── json-to-xcstrings.py        # iOS converter
├── json-to-android.py          # Android converter
└── json-to-fluent.py           # TUI converter
```

## Implementation Phases

### Phase 1: Shared Locale Infrastructure (2 days)

**Tasks:**
- [ ] Create `locales/en.json` with all UI strings
- [ ] Define string key naming convention: `screen.section.element`
- [ ] Create sync scripts for each platform
- [ ] Add `just sync-locales` command
- [ ] Set up CI check for missing translations

**String Key Convention:**
```json
{
  "welcome.title": "Welcome to Vauchi",
  "welcome.subtitle": "Privacy-focused contact cards",
  "contacts.title": "Contacts",
  "contacts.empty": "No contacts yet",
  "contacts.count": "{count} contacts",
  "exchange.generateQR": "Generate QR Code",
  "settings.title": "Settings"
}
```

### Phase 2: iOS Localization (3 days)

**Files to create:**
- `ios/Vauchi/Localizable.xcstrings`

**Files to modify:**
- All `ios/Vauchi/Views/*.swift`
- All `ios/Vauchi/Components/*.swift`

**Tasks:**
- [ ] Generate `.xcstrings` from `locales/en.json`
- [ ] Replace all hardcoded strings with `String(localized:)`
- [ ] Handle pluralization with `.stringsdict`
- [ ] Test language switching
- [ ] Add German, French, Spanish translations

**Pattern:**
```swift
// Before
Text("Welcome to Vauchi")

// After
Text(String(localized: "welcome.title"))
```

### Phase 3: Android Localization (3 days)

**Files to create:**
- `android/app/src/main/res/values/strings.xml` (expand)
- `android/app/src/main/res/values-de/strings.xml`
- `android/app/src/main/res/values-fr/strings.xml`
- `android/app/src/main/res/values-es/strings.xml`

**Files to modify:**
- All Composables in `ui/screens/` and `ui/components/`

**Tasks:**
- [ ] Generate `strings.xml` from `locales/en.json`
- [ ] Replace all hardcoded strings with `stringResource(R.string.*)`
- [ ] Handle plurals with `<plurals>` resource
- [ ] Test language switching
- [ ] Add translations

**Pattern:**
```kotlin
// Before
Text("Welcome to Vauchi")

// After
Text(stringResource(R.string.welcome_title))
```

### Phase 4: Desktop Localization (2 days)

**Dependencies:**
```json
{
  "@solid-primitives/i18n": "^2.1.0"
}
```

**Files to create:**
- `code/vauchi-desktop/ui/src/i18n/index.ts`
- `code/vauchi-desktop/ui/src/i18n/en.json`
- `code/vauchi-desktop/ui/src/i18n/de.json`

**Tasks:**
- [ ] Set up solid-primitives i18n
- [ ] Create locale context provider
- [ ] Replace all hardcoded strings
- [ ] Add language switcher in Settings
- [ ] Test all languages

**Pattern:**
```tsx
const [t] = useI18n();
<h1>{t("welcome.title")}</h1>
```

### Phase 5: TUI Localization (2 days)

**Dependencies:**
```toml
fluent = "0.16"
fluent-langneg = "0.13"
unic-langid = "0.9"
```

**Files to create:**
- `code/vauchi-tui/src/i18n.rs`
- `code/vauchi-tui/locales/en/main.ftl`
- `code/vauchi-tui/locales/de/main.ftl`

**Tasks:**
- [ ] Set up Fluent i18n
- [ ] Create locale loading module
- [ ] Replace all hardcoded strings
- [ ] Handle pluralization with Fluent syntax
- [ ] Test all languages

### Phase 6: RTL Support (3 days)

**Tasks:**
- [ ] Add Arabic and Hebrew to locale files
- [ ] iOS: Test layout mirroring
- [ ] Android: Test layout mirroring
- [ ] Desktop: Add `dir="rtl"` support
- [ ] Handle mixed LTR/RTL content (emails, URLs)

### Phase 7: Locale-Aware Formatting (2 days)

**Tasks:**
- [ ] Date formatting per locale
- [ ] Number formatting (thousand/decimal separators)
- [ ] Relative time formatting ("2 days ago")
- [ ] Phone number formatting

## Translation Workflow

1. Developer adds string to `locales/en.json`
2. Run `just sync-locales` to propagate
3. CI fails if translations missing in other locales
4. Translators update `locales/de.json`, etc.
5. Run sync again to update platform files

## Testing Strategy

```bash
# iOS - Change simulator language
xcrun simctl spawn booted defaults write NSGlobalDomain AppleLanguages '("de")'

# Android - Change emulator language
adb shell am start -a android.settings.LOCALE_SETTINGS

# Desktop
LANG=de_DE.UTF-8 pnpm dev

# TUI
LANG=de_DE.UTF-8 cargo run -p vauchi-tui
```

## Metrics

| Metric | Target |
|--------|--------|
| String coverage | 100% per locale |
| Scenarios passing | 50/50 |
| Untranslated strings visible | 0 |
| RTL layout issues | 0 |

## Risks

| Risk | Mitigation |
|------|------------|
| Long translations break layout | Flexible layouts, test with German |
| Translation quality | Use professional translators for launch |
| Missing translations at runtime | CI check, fallback to English |

## Open Questions

1. Should we use a translation management platform (Crowdin, Lokalise)?
2. Do we need professional translations or community translations?
3. What's the minimum viable language set for launch?

## References

- [Apple Localization](https://developer.apple.com/localization/)
- [Android Localization](https://developer.android.com/guide/topics/resources/localization)
- [solid-primitives/i18n](https://primitives.solidjs.community/package/i18n)
- [Project Fluent](https://projectfluent.org/)
