---
apply: always
---

## Crypto Policy (CRITICAL)

- **`ring`** is the primary crypto library — use it for all crypto operations
- **Exceptions** (spec-mandated only): `chacha20poly1305`, `argon2`, `x25519-dalek`
- **Never mock crypto** in tests — test with real crypto operations
- **Never introduce** new crypto libraries without explicit approval
- Zeroize key material after use
