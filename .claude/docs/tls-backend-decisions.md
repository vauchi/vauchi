<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# TLS Backend Decisions

Component-by-component TLS backend mapping with rationale and selection criteria.

Source: TLS Backend Mismatch Audit (2026-03-14, verified 2026-03-18).

## Current State

| Component | TLS Library | Backend | Rationale |
|-----------|-------------|---------|-----------|
| vauchi-core (rustls feature) | rustls 0.23 | aws-lc-rs | FIPS 140-3 aligned; used by mobile bindings |
| vauchi-platform (iOS/Android) | rustls 0.23 | aws-lc-rs | No OpenSSL dependency; cross-compiles to ARM |
| relay | rustls 0.23 | aws-lc-rs | Server-side FIPS alignment; matches core |
| ohttp-relay | reqwest 0.12 | rustls-tls | Inherits reqwest's rustls; privacy relay |
| CLI | tokio-tungstenite 0.24 | native-tls | OS-provided; desktop-only, no cross-compile |
| TUI | tokio-tungstenite 0.24 | native-tls | Same as CLI |
| linux-gtk | vauchi-app | native-tls | OS-provided via feature flag |
| web-demo (WASM) | — | Browser TLS | No Rust TLS needed; browser handles transport |
| iOS/macOS (Swift) | — | Apple TLS | Consumes vauchi-platform via SPM; app-level HTTP uses URLSession |
| Android (Kotlin) | — | Android TLS | Consumes vauchi-platform via Maven AAR; app-level HTTP uses OkHttp |

## Design Rationale

### Why two TLS stacks?

**rustls + aws-lc-rs** for components that cross-compile or run on mobile/server:

- No system OpenSSL dependency — essential for iOS/Android NDK builds
- FIPS 140-3 aligned via aws-lc-rs (not yet certified, but on the path)
- Consistent crypto primitives across all platforms

**native-tls** for desktop CLI tools (CLI, TUI, linux-gtk):

- Uses the OS certificate store automatically (no cert bundle management)
- Simpler build — no C compilation for aws-lc-rs on developer machines
- Desktop-only, no cross-compilation requirement

### Why not ring?

`ring` was the original rustls backend. Replaced by `aws-lc-rs` across all
components (2026-03-18) because:

- aws-lc-rs is on the FIPS 140-3 certification path
- Eliminates ring/aws-lc-rs duplication in the dependency tree
- AWS maintains aws-lc-rs with active security response

### WASM

No Rust-level TLS. The browser's TLS stack handles all transport security.
`vauchi-wasm` uses `wasm-bindgen` for JS interop; HTTP goes through `fetch()`.

## Selection Criteria for New Components

When adding a new component that needs TLS:

1. **Cross-compiles to mobile/embedded?** → rustls + aws-lc-rs
2. **Server-side (relay, API)?** → rustls + aws-lc-rs
3. **Desktop-only CLI/GUI?** → native-tls (simpler build)
4. **WASM?** → No Rust TLS (browser handles it)
5. **Unsure?** → Default to rustls + aws-lc-rs

**Rule**: No new TLS/crypto backend dependencies without documented justification
and ADR amendment (see ADR-002).

## Cargo Feature Flags

vauchi-core exposes two mutually exclusive network features:

```toml
# For mobile/server (rustls + aws-lc-rs):
vauchi-app = { ..., features = ["network-rustls"] }

# For desktop (native-tls):
vauchi-app = { ..., features = ["network-native-tls"] }
```

Both features gate the same `NetworkTransport` implementation — only the TLS
handshake differs. Application-level behavior is identical.

## Related

- ADR-002: Crypto library selection (aws-lc-rs primary, amended 2026-03-27)
- ADR-037: OHTTP IP privacy (ohttp-relay transport)
- Problem: TLS Backend Mismatch Audit (done 2026-03-18)
