<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

## Drift-Detector Naming & Tagging Conventions (MANDATORY)

The project uses `drift-detector` to verify cross-layer traceability. Follow these conventions so new code is automatically traceable.

### Concept Tags (use consistently across all layers)

| Concept | Use in feature tags | Use in module/file paths | Use in test names |
|---------|-------------------|-------------------------|-------------------|
| `crypto` | `@crypto` | `/crypto/` | `test_encrypt_`, `test_decrypt_` |
| `exchange` | `@exchange` | `/exchange/` | `test_exchange_`, `test_qr_` |
| `contacts` | `@contacts` | `/contact_card/`, `/contact/` | `test_contact_` |
| `identity` | `@identity` | `/identity/` | `test_identity_` |
| `recovery` | `@recovery` | `/recovery/` | `test_recovery_`, `test_backup_` |
| `sync` | `@sync` | `/sync/` | `test_sync_` |
| `device` | `@device` | `/device/`, `/device_link/` | `test_device_` |
| `relay` | `@relay` | `/relay/` | `test_relay_` |
| `visibility` | `@visibility` | `/visibility/` | `test_visibility_` |
| `vouching` | `@vouching` | `/vouching/` | `test_vouch_`, `test_trust_` |
| `emergency-shred` | `@shred` | `/shred/` | `test_shred_`, `test_panic_shred_` |
| `duress` | `@duress` | - | `test_duress_`, `test_decoy_` |
| `tor-mode` | `@tor` | `/tor/` | `test_tor_` |
| `storage` | `@storage` | `/storage/` | `test_storage_` |

### Feature Files (`features/*.feature`)

- **File naming**: `snake_case.feature` (one feature per file)
- **Feature-level tags**: Domain tags on the `Feature:` line (e.g., `@exchange @proximity`)
- **Scenario lifecycle tags** (MANDATORY on every Scenario/Scenario Outline):
  - `@implemented` — Has passing tests
  - `@planned` — Specced, not yet implemented
  - `@wip` — Actively being worked on (must resolve before merge)
- **Domain tags on scenarios**: Add domain tags alongside lifecycle tag (e.g., `@security @implemented`)

### Test Files (`tests/*.rs`)

- **Test naming**: `test_<subject>_<scenario>_<expected_outcome>`
- **Scenario annotations** (MANDATORY for tests covering a Gherkin scenario):
  ```rust
  // @scenario: feature_name.feature:Scenario Name
  #[test]
  fn test_exchange_round_trip_succeeds() { ... }
  ```
  - Format: `// @scenario: <feature_file>:<scenario_title>` or `// @scenario: <feature_name>:<scenario_title>`
  - Place immediately above `#[test]`
  - Multiple annotations allowed for tests covering multiple scenarios
- **Source annotations** (optional, for explicit test-to-code linking):
  ```rust
  // @source: exchange::ExchangeSession::new_qr
  #[test]
  fn test_qr_session_initialization() { ... }
  ```

### Concept Aliases (for searching)

When searching the codebase for a concept, use these aliases to find all related code:
- **exchange**: `proximity`, `qr-code`, `qr`, `nfc`, `ble`, `audio`, `prekey`
- **contacts**: `contact-card`, `contact-actions`, `add-field`, `merge`, `favorites`, `labels`
- **security**: `auth`, `attacks`, `spoofing`, `passwords`, `audit`
- **privacy**: `consent`, `gdpr`, `compliance`, `plausible-deniability`
- **emergency-shred**: `shred`, `panic-shred`, `crypto-shred`, `soft-shred`, `hard-shred`
- **sync**: `updates`, `content-updates`, `remote-content`, `conflict`, `propagation`
- **device**: `link`, `unlink`, `multi-device`, `device-link`, `device-sync`

Full alias map: `driftconfig.toml` → `[concepts.aliases]`

### When Writing New Code

1. **New feature file** → Add domain tags + `@planned` on all scenarios
2. **New test file** → Add `// @scenario:` annotations linking to feature scenarios
3. **New module** → Name the directory to match a concept tag (e.g., `src/exchange/`)
4. **Promoting scenario** → Change `@planned` → `@implemented` when tests pass
5. **Run `just drift`** after completing a feature to verify traceability
