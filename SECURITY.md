<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

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
- Native desktop apps (macOS, Windows, Linux)
- CLI/TUI
- Web demo (WASM)

### Out of Scope

- Social engineering attacks
- Physical attacks
- Denial of service attacks
- Third-party dependencies (report to upstream)

## Security Design

### Cryptography

| Component | Algorithm | Library |
|-----------|-----------|---------|
| Key exchange | X25519 / X3DH | `x25519-dalek` |
| Message encryption | Double Ratchet + XChaCha20-Poly1305 | `chacha20poly1305` |
| Signatures | Ed25519 | `aws-lc-rs` |
| Key derivation | HKDF-SHA256 | `aws-lc-rs` |
| Password KDF | Argon2id | `argon2` |

### Trust Model

- **Device is identity**: No accounts, no passwords
- **In-person exchange**: Trust established via physical presence
- **Zero-knowledge relay**: Server sees only encrypted blobs
- **Forward secrecy**: Compromised keys don't expose past messages

### Threat Model

Key threats we defend against:
- **Relay compromise**: Cannot decrypt messages (zero-knowledge design)
- **Device theft**: Local data encrypted, keys in secure enclave
- **MITM attacks**: X3DH provides authenticated key exchange
- **Replay attacks**: Double Ratchet with message counters
- **Contact harvesting**: Proximity verification prevents remote attacks

## Security Audits

- **Last audit**: 2026-01-22 (internal)
- **cargo-audit**: 0 vulnerabilities
- **External audit**: Planned (seeking funding)

## Acknowledgments

We thank the following researchers for responsible disclosure:

(None yet — be the first!)
