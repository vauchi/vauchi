---
name: rust-patterns
description: Vauchi Rust conventions, crate structure, ring crypto rules, UniFFI binding patterns, error handling, and test layout. Use when writing or modifying Rust code in core/.
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi Rust Patterns

## Workspace Structure

```
core/
├── Cargo.toml              # Workspace root (resolver 2)
├── vauchi-core/            # Main library (v0.1.2)
│   ├── src/
│   │   ├── lib.rs          # Module exports and public API
│   │   ├── api/            # High-level orchestration (feature-gated: network)
│   │   ├── crypto/         # ring + documented exceptions
│   │   ├── exchange/       # X3DH, QR, proximity, BLE (NFC Active + NFC Dead Drop planned)
│   │   ├── contact/        # Contact model + visibility
│   │   ├── contact_card/   # Shareable card fields
│   │   ├── storage/        # SQLite persistence
│   │   ├── identity/       # Identity + backup/restore
│   │   ├── network/        # Transport trait + WebSocket
│   │   ├── sync/           # Delta sync + Merkle reconciliation
│   │   ├── recovery/       # Social recovery protocol
│   │   ├── social/         # Social network validation
│   │   └── content/        # Remote content updates
│   └── tests/              # Integration + property tests
└── vauchi-mobile/          # UniFFI bindings for iOS/Android
    └── src/
        ├── lib.rs           # uniffi::setup_scaffolding!()
        ├── types.rs         # Mobile* wrapper types
        └── error.rs         # MobileError
```

## Cargo Features

```toml
# vauchi-core features
network           # (default) WebSocket transport
network-native-tls # tungstenite + native-tls (default with network)
network-rustls    # Pure Rust TLS (used by vauchi-mobile)
secure-storage    # Platform keychain (keyring)
audio-cpal        # Audio proximity verification
content-updates   # Remote content (reqwest + tokio)
testing           # Expose internals for integration tests
```

**vauchi-mobile forces `network-rustls`** — no OpenSSL for cross-compilation.

## Crypto Rules (MANDATORY)

**Primary: `ring` only.** Documented exceptions:

| Crate | Reason |
|-------|--------|
| `ring 0.17` | HMAC, Ed25519, AES-256-GCM, HKDF (audited) |
| `x25519-dalek 2.0` | X25519 DH (spec-mandated) |
| `chacha20poly1305 0.10` | XChaCha20-Poly1305 (spec-mandated cipher) |
| `argon2 0.5` | Argon2id KDF (spec-mandated for backup) |

**Never mock crypto in tests.** Use real signatures, real encryption, real KDF.

### Key Types

```rust
// crypto/encryption.rs
pub struct SymmetricKey { bytes: [u8; 32] }  // Implements Drop + Zeroize
// Encrypt output: [0x02 | nonce(24) | ciphertext | tag(16)]
// Decrypt handles both XChaCha20 (0x02) and legacy AES-GCM (0x01)

// crypto/signing.rs
pub struct SigningKeyPair { keypair: Ed25519KeyPair, seed: [u8; 32] }
// generate() uses SystemRandom, from_seed() for deterministic recovery

// crypto/ratchet.rs — Signal Protocol Double Ratchet
pub struct DoubleRatchetState { root_key, our_dh_secret, their_dh, chains, skipped_keys }

// exchange/x3dh.rs — X25519 key agreement
pub struct X3DHKeyPair { secret: StaticSecret, public: PublicKey }
```

**Memory safety**: All crypto types `Zeroize` on `Drop`. `SymmetricKey::Debug` shows `[REDACTED]`. All randomness via `ring::rand::SystemRandom`.

## Module Visibility Pattern

```rust
// Most modules use conditional exposure for testing:
#[cfg(feature = "testing")]
pub mod contacts;
#[cfg(not(feature = "testing"))]
mod contacts;
pub use contacts::*;  // Re-export public API
```

## Error Handling

- `thiserror` for all error enums with `#[derive(Error)]`
- `#[from]` attributes for automatic conversions
- Unified `VauchiError` at API layer consolidates all error types
- `VauchiResult<T> = Result<T, VauchiError>`

```rust
// api/error.rs — top-level error
pub enum VauchiError {
    Validation(ValidationError),
    Exchange(ExchangeError),
    Storage(StorageError),
    Sync(SyncError),
    Network(NetworkError),
    ContactNotFound(String),
    IdentityNotInitialized,
    // ...
}
```

## Trait Abstractions

| Trait | Module | Purpose |
|-------|--------|---------|
| `Transport` | `network::transport` | Abstract network I/O (MockTransport, WebSocketTransport) |
| `ProximityVerifier` | `exchange::proximity` | Physical proximity check (audio, BLE, manual) |
| `AudioBackend` | `exchange::audio` | Cross-platform audio I/O |
| `SecureStorage` | `storage::secure` | Platform keychain (iOS/Android/desktop) |
| `EventHandler` | `api::events` | Async event callbacks |

## Naming Conventions

- **Types**: `CamelCase` — `ContactCard`, `SyncManager`, `DoubleRatchetState`
- **Traits**: Suffixed — `Verifier`, `Backend`, `Handler`, `Transport`, `Storage`
- **Errors**: `*Error` enum — `ExchangeError`, `StorageError`, `RatchetError`
- **Mobile wrappers**: `Mobile*` prefix — `MobileContact`, `MobileError`
- **Functions**: `snake_case`
- **Constants**: `SCREAMING_SNAKE_CASE`

## Derive Patterns

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]  // Data models
#[derive(thiserror::Error)]                       // Error enums
#[derive(uniffi::Record)]                         // Mobile data types
#[derive(uniffi::Enum)]                           // Mobile enums
#[derive(uniffi::Error)]                          // Mobile errors
```

## UniFFI Binding Pattern

```rust
// vauchi-mobile/src/types.rs — wrapper with From/Into
#[derive(Debug, Clone, uniffi::Record)]
pub struct MobileContactField {
    pub id: String,
    pub field_type: MobileFieldType,
    pub label: String,
    pub value: String,
}

impl From<&ContactField> for MobileContactField { /* field accessors */ }
impl From<MobileContactField> for FieldType { /* reverse */ }

// vauchi-mobile/src/error.rs
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum MobileError {
    #[error("Library not initialized")]
    NotInitialized,
    // Converts from core errors via From impls
}
```

## Storage

- **SQLite** via `rusqlite` (bundled) with application-level encryption
- **Migrations** in `storage/migration.rs` for schema evolution
- **In-memory** for tests: `Storage::in_memory(SymmetricKey::generate())`

## Build Profiles

```toml
[profile.release]   # Size-optimized: opt-level = "z", LTO, panic = "abort"
[profile.dev]       # Fast: full debug info
[profile.ci]        # Balanced: thin LTO, 16 codegen units
```

## Test File Layout

```
tests/
├── common/
│   ├── helpers.rs      # create_vauchi_with_identity(), setup_alice_bob_exchange()
│   ├── fixtures.rs     # TEST_PASSWORD, sample_contact_card(), unicode data
│   └── strategies.rs   # Proptest strategies (display_name, bytes32, etc.)
├── integration/        # Multi-unit workflows
├── e2e/                # Full scenario workflows
├── crypto_*.rs         # Crypto operation tests
├── property_tests.rs   # proptest + quickcheck
└── fuzz_tests.rs       # Fuzzing
```

## Key Dependencies

| Crate | Purpose |
|-------|---------|
| `serde` + `serde_json` + `bincode` | Serialization |
| `rusqlite` (bundled) | SQLite storage |
| `zeroize` | Sensitive memory wiping |
| `zxcvbn` | Password strength |
| `qrcode` | QR code generation |
| `thiserror` | Error derive |
| `tokio` | Async runtime (optional) |
| `tempfile` | Test temp dirs |
| `proptest` + `quickcheck` | Property testing |
| `criterion` | Benchmarking |
