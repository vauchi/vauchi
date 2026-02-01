<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi

**Privacy-focused updatable contact cards via in-person QR exchange.**

Exchange contact info with people you meet in person. Update your details anytime — everyone who has your card sees the changes. No accounts, no servers storing your data, no tracking.

## Why Vauchi?

Traditional contact sharing has problems:
- **Business cards** go stale the moment your number changes
- **Contact apps** require accounts and store your data on their servers
- **QR codes** are static — you can't update them after sharing

Vauchi solves this:
- **Exchange in person** — scan a QR code when you meet someone
- **Always current** — update your card, everyone sees the change
- **End-to-end encrypted** — only your contacts can read your info
- **No accounts** — your device is your identity
- **No data harvesting** — we can't read your contacts, even if we wanted to

## Core Principles

1. **Privacy is a right, not an option** — E2E encryption, zero-knowledge relay, no tracking
2. **Trust is earned in person** — QR exchange with physical proximity, not platform-mediated
3. **Quality through rigor** — Test-driven development, threat modeling, no shortcuts

See [PRINCIPLES.md](PRINCIPLES.md) for the full philosophy.

## Architecture

```
┌─────────────┐     ┌─────────────┐
│   Phone A   │     │   Phone B   │
│  (Alice)    │     │   (Bob)     │
└──────┬──────┘     └──────┬──────┘
       │                   │
       │  QR Exchange      │
       │  (in person)      │
       └─────────┬─────────┘
                 │
        ┌────────▼────────┐
        │  Relay Server   │
        │ (encrypted blob │
        │  routing only)  │
        └─────────────────┘
```

The relay sees only encrypted blobs. It cannot read contact names, phone numbers, or any content.

## Repository Structure

| Repository | Description |
|------------|-------------|
| [core/](core/) | Core library (`vauchi-core`) + mobile bindings (`vauchi-mobile`) |
| [relay/](relay/) | WebSocket relay server for message routing |
| [cli/](cli/) | Command-line interface |
| [tui/](tui/) | Terminal user interface |
| [desktop/](desktop/) | Desktop app (Tauri + SolidJS) |
| [android/](android/) | Android app (Kotlin/Compose) |
| [ios/](ios/) | iOS app (SwiftUI) |
| [e2e/](e2e/) | End-to-end tests |
| [website/](website/) | Project website |

## Quick Start

### Prerequisites

- Rust 1.75+
- [just](https://github.com/casey/just) command runner

### Build

```bash
git clone https://github.com/vauchi/vauchi.git
cd vauchi
just setup    # Clone all repos, set up workspace
just build    # Build Rust workspace
just check    # Run format, lint, and tests
```

### Run Tests

```bash
just test     # All tests
just e2e      # End-to-end tests
```

### Commands

```bash
just help     # Show all available commands
```

## Security

Vauchi uses:
- **X3DH** key agreement (Signal protocol)
- **Double Ratchet** for forward secrecy
- **AES-256-GCM** for symmetric encryption
- **Ed25519** for signatures
- **ring** crypto library (no OpenSSL)

All cryptographic operations are in `core/vauchi-core/src/crypto/`.

For security issues, see [SECURITY.md](SECURITY.md).

## Status

**Pre-release** — Core functionality works, undergoing testing.

- [x] E2E encryption
- [x] Contact exchange (QR, audio proximity)
- [x] Card updates with forward secrecy
- [x] Multi-device sync
- [x] Contact recovery
- [x] Relay server (live at relay.vauchi.app)
- [ ] Public beta release
- [ ] App store releases

## Contributing

We welcome contributions. Please read:
- [CONTRIBUTING.md](CONTRIBUTING.md) — Development workflow
- [PRINCIPLES.md](PRINCIPLES.md) — Core principles (mandatory)

All code must have tests. No exceptions.

## Support the Project

[![Sponsor on GitHub](https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa)](https://github.com/sponsors/vauchi)
[![Donate on Liberapay](https://img.shields.io/badge/donate-Liberapay-f6c915)](https://liberapay.com/Vauchi/donate)

Vauchi is open source and community-funded. No VC money, no data harvesting business model.

If you believe in privacy-respecting software:

- **GitHub Sponsors**: [Sponsor Vauchi](https://github.com/sponsors/vauchi)
- **Liberapay**: [liberapay.com/Vauchi](https://liberapay.com/Vauchi/donate)

Funds go toward:
- Development hardware and testing devices
- Infrastructure costs (relay server)
- Security audits

See [SUPPORTERS.md](SUPPORTERS.md) for sponsorship tiers.

## License

[GPL-3.0-or-later](LICENSE)

## Links

- Website: [vauchi.app](https://vauchi.app)
- Relay: wss://relay.vauchi.app
