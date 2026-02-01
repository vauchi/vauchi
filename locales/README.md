<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi Locales

Master locale files for all Vauchi platforms. English (`en.json`) is the source of truth.

## Files

| File | Language | Status |
|------|----------|--------|
| `en.json` | English | Source |
| `de.json` | German | Complete |
| `fr.json` | French | Complete |
| `es.json` | Spanish | Complete |

## Key Naming Convention

Keys follow `section.element` format:

```
app.name              → App-level strings
welcome.title         → Welcome/onboarding screen
nav.home              → Navigation labels
contacts.empty        → Contacts screen
exchange.scan         → Exchange screen
settings.language     → Settings screen
help.faq              → Help screen
action.save           → Reusable action labels
error.network         → Error messages
update.sent           → Update notifications
card.edit             → Card-related strings
```

## Adding a New String

1. Add the key and English value to `en.json`
2. Add translations to all other locale files (`de.json`, `fr.json`, `es.json`)
3. Run `just sync-locales` to validate completeness
4. Use the key in code via the platform's i18n API

## Validation

```bash
just sync-locales          # Check for missing/extra keys
just sync-locales-strict   # Same but exits with error (for CI)
```

## Interpolation

Use `{variable}` syntax for dynamic values:

```json
"contacts.count": "{count} contacts",
"update.received": "Update received from {name}"
```

## Metadata

Each file contains a `_meta` object (excluded from validation):

```json
"_meta": {
  "locale": "en",
  "name": "English",
  "english_name": "English",
  "is_rtl": false
}
```
