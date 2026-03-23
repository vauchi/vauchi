---
paths:
  - "core/**"
apply: always
---

## Core Repo

- **Crates**: `vauchi-core` (crypto, protocols, data models), `vauchi-platform` (UniFFI bindings — keep surface minimal), `vauchi-protocol` (shared relay/client types, serde-only), `vauchi-cabi` (C ABI exports for FFI consumers)
- **Downstream**: cli, tui, e2e, macos, windows, linux-gtk, linux-qt, web-demo depend on `vauchi-core`. relay depends on `vauchi-protocol` only.
- `vauchi-core`: RustCrypto audited crates (`ed25519-dalek`, `sha2`, `hmac`, `hkdf`), `aws-lc-rs` retained for TLS only (via rustls), no `unsafe`, 90%+ coverage, security-critical (key generation, E2E encryption, signatures, protocol state machines)
- **CI release flow**: `build-bindings.sh → package-*.sh → publish-packages.sh → publish:maven → update:swift-bindings → trigger:ios/macos/android`
- **NFC**: Two planned features (0% implemented, post-MVP). See problem records in `_private/docs/problems/`.
