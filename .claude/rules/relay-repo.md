---
paths:
  - "relay/**"
apply: always
---

## Relay

- **Stateless**: No persistent sensitive data. Forwards encrypted blobs, never decrypts.
- Uses `vauchi-protocol` (from `core/`) for shared message types. Does **not** depend on `vauchi-core`.
