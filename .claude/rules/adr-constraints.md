## ADR Constraints (MANDATORY)

Extracted from ADR-001 through ADR-038. These are hard rules — not guidelines.
Source: `_private/docs/decisions/adr-*.md`. Run `@adr-check` to verify compliance.

### Crypto (ADR-002, ADR-019)

- **Never mock crypto in tests** — use real crypto operations
- **Approved crates only**: RustCrypto primary (`ed25519-dalek`, `x25519-dalek`, `sha2`, `hmac`, `hkdf`), spec-mandated (`chacha20poly1305`, `argon2`), transport (`snow`, `aws-lc-rs` via rustls), privacy (`ohttp` via ADR-037). New crypto crates require ADR amendment
- **XChaCha20-Poly1305 for all new encryption** — AES-256-GCM is legacy decryption only
- **Always use HKDF domain separation** — every derivation path has a unique info string (ADR-007)
- **Identity signing key uses raw seed directly** — not HKDF-derived (Ed25519 requirement)
- **Zeroize key material after use** — all secret keys must implement `ZeroizeOnDrop`
- **Never expose plaintext to the relay** — relay sees encrypted blobs only (ADR-004)
- **Always encrypt sensitive fields at rest** — contact cards, shared keys, ratchet states, backup data (ADR-015)

### Architecture (ADR-021, ADR-022, ADR-023)

- **Core owns all business logic** — frontends never duplicate data logic, filtering, validation, or computation. If two clients need the same logic, it belongs in core
- **Frontends are pure renderers** — they render `ScreenModel` components natively and forward `UserAction`s to core. No workflow orchestration in frontends
- **Never put `DisplayHint` on `ScreenModel`** — it's a construction parameter, not screen data
- **Frontends must never branch on form factor** — core handles form-factor differences via `DisplayHint`
- **Every `WorkflowEngine` impl must handle all `DisplayHint` variants** — Phone, Watch, Desktop
- **Use `InlineConfirm` for irrevocable actions, `ShowToast` for reversible** — never modal dialogs (ADR-022 addenda)

### Hardware & Platform (ADR-030, ADR-031)

- **Core must never call hardware directly** — hardware interaction uses command/event protocol: core emits `ExchangeCommand`, frontends execute and return `ExchangeHardwareEvent`
- **Never create a Platform trait in core** — permanently unnecessary per ADR-030/031
- **Never reintroduce the Transport generic parameter** — `Box<dyn Transport>` is the final form
- **All future hardware** (biometrics, WiFi Aware, USB) **follows command/event pattern** — no new hardware traits
- **Keep `UserAction` and `ExchangeHardwareEvent` on separate dispatch paths** — different concerns (ADR-031)
- **Exchange tests must be pure input/output** — events in, commands out, no mock traits (ADR-031)

### Protocol (ADR-028/029)

- **Never use stable (non-rotating) mailbox tokens** — use daily-rotating tokens (ADR-029)
- **Clients must persist `last_connected_epoch`** and deregister historical tokens after catch-up

### Bindings (ADR-025, ADR-026)

- **Frontend repos must never run `cargo`** — except Rust-native repos (linux-gtk, windows, CLI, TUI)
- **UI types are in `core/vauchi-app/src/ui/`** — not `vauchi-core/src/ui/` (moved during crate reorganization)

### Design (ADR-038)

- **All visual properties** (colors, spacing, typography) **defined in `themes/` or `tokens.json`** — never hardcoded in frontend code
- **All user-visible strings** in `locales/*.json` via `t("key")` — never hardcoded
- **All accessibility labels** from core's `accessible_label`/`accessible_hint` fields — not hardcoded in frontends (migration in progress)

### Desktop (ADR-027)

- **Desktop = 4 native repos** (`linux-gtk`, `macos`, `windows`, `linux-qt`) — not single `desktop/` Tauri repo (archived)
- **Never reference** `desktop/`, `SolidJS`, `Tauri`, or ARIA in active plans — these are stale

### Security (ADR-032, ADR-033, ADR-034, ADR-035, ADR-037)

- **Trust level is never user-editable** — pure deterministic derivation from exchange facts (ADR-034)
- **Duress alerts disguised as card updates** — no special message type, no metadata flag (ADR-032)
- **SMK derived once at identity creation, stored in SecureStorage, never re-derived** — avoids bootstrap deadlock (ADR-033)
- **Device link QR codes expire after 5 minutes** — limits exposure window (ADR-035)
- **OHTTP gateway and relay operators must be distinct entities** — same entity defeats privacy (ADR-037)
