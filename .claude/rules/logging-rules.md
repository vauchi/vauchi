## Logging Rules (MANDATORY)

### Privacy

- **NEVER log PII**: contact names, public keys, tokens, card content, relay URLs with tokens
- **OK to log**: version strings, error types (without PII), startup diagnostics
- No remote log shipping — ever. Logs stay on-device.
- Future: opt-in diagnostic export with explicit user consent only

### Platform Conventions

- **Android**: `Log.i("Vauchi", ...)` for startup, `Log.e("Vauchi", ...)` for errors only
- **iOS**: `NSLog("[Vauchi] ...")` for startup, error-level only in catch blocks
- **Rust/Core**: No runtime logging in vauchi-mobile (zero log crate dependency)

### Guidelines

- Avoid step-by-step logging in hot paths — use only for error reporting
- Startup log format: `Build: v<version> (<build>) core=<core_version>`
- Error log format: `[<Module>] Failed: <error_type_only>`
- Never log QR data, even truncated — it contains cryptographic material
