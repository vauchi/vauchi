# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Vauchi, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

Email: security@vauchi.app

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (optional)

### What to Expect

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 7 days
- **Resolution timeline**: Depends on severity, typically 30-90 days

### Safe Harbor

We will not take legal action against researchers who:
- Report vulnerabilities in good faith
- Avoid privacy violations, data destruction, or service disruption
- Give us reasonable time to fix issues before public disclosure

## Scope

### In Scope

- `vauchi-core` library
- Relay server (`relay/`)
- Mobile apps (Android, iOS)
- Desktop app
- CLI/TUI

### Out of Scope

- Social engineering attacks
- Physical attacks
- Denial of service attacks
- Third-party dependencies (report to upstream)

## Security Design

### Cryptography

| Component | Algorithm | Library |
|-----------|-----------|---------|
| Key exchange | X3DH | ring |
| Message encryption | Double Ratchet + AES-256-GCM | ring |
| Signatures | Ed25519 | ring |
| Key derivation | HKDF-SHA256 | ring |

### Trust Model

- **Device is identity**: No accounts, no passwords
- **In-person exchange**: Trust established via physical presence
- **Zero-knowledge relay**: Server sees only encrypted blobs
- **Forward secrecy**: Compromised keys don't expose past messages

### Threat Model

See [docs/2026-01-22-THREAT_ANALYSIS.md](docs/2026-01-22-THREAT_ANALYSIS.md) for the full threat model.

## Security Audits

- **Last audit**: 2026-01-22 (internal)
- **cargo-audit**: 0 vulnerabilities
- **External audit**: Planned (seeking funding)

## Acknowledgments

We thank the following researchers for responsible disclosure:

(None yet — be the first!)
