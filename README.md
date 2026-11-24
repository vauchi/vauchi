<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi

**Privacy-focused updatable contact cards via in-person exchange.**

Exchange contact info with people you meet in person. Update your details
anytime — everyone who has your card sees the changes. No accounts, no server
that can read your data, no tracking.

GitLab is canonical: [gitlab.com/vauchi](https://gitlab.com/vauchi) holds
every repository, issue and merge request. Most public repositories have a
read-only mirror on [github.com/vauchi](https://github.com/vauchi); this
workspace repository does not.

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

1. **Privacy is a right, not an option** — E2E encryption, oblivious
   privacy-preserving relay, no tracking
2. **Trust is earned in person** — QR exchange with physical proximity, not
   platform-mediated
3. **Quality through rigor** — Test-driven development, threat modeling, no
   shortcuts

See [Principles](https://vauchi.app/docs/about/principles) for the full philosophy.

## Architecture

```text
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

The relay sees only encrypted blobs. It cannot read contact names, phone
numbers, or any content.

## Repository Structure

| Repository | Description |
|------------|-------------|
| [core/](core/) | Core library (`vauchi-core`) + platform bindings (`vauchi-platform`) + C ABI (`vauchi-cabi`) |
| [relay/](relay/) | WebSocket relay server for message routing |
| [cli-display/](cli-display/) | Command-line interface |
| [tui-display/](tui-display/) | Terminal user interface |
| [macos/](macos/) | Native macOS app (SwiftUI) |
| [windows-app/](windows-app/) | Native Windows app (WinUI 3 / C#) |
| [gtk-display/](gtk-display/) | Native Linux app (GTK4 + libadwaita) |
| [qt-display/](qt-display/) | Native Linux app (Qt variant) |
| [android/](android/) | Android app (Kotlin/Compose) |
| [ios/](ios/) | iOS app (SwiftUI) |
| [linux-hw/](linux-hw/) | Hardware shell for Linux (BlueZ, PC/SC, PipeWire, mDNS) |
| [linux-app/](linux-app/) | Linux app: assembles Core, linux-hw and the GTK, Qt, CLI and TUI display shells (ADR-078) |
| [apple-hw/](apple-hw/) | Hardware shell for iOS and macOS (CoreBluetooth, Core NFC, AVFoundation) |
| [apple-display/](apple-display/) | Shared SwiftUI rendering library with iOS and macOS adapters |
| [android-hw/](android-hw/) | Hardware shell for Android (Bluetooth LE, NFC/HCE, CameraX) |
| [windows-hw/](windows-hw/) | Hardware shell for Windows (WinRT Bluetooth LE, WinSCard, MediaCapture) |
| [windows-display/](windows-display/) | WinUI 3 display shell library that renders the contract (ADR-078) |
| [contract/](contract/) | The shell contract: Command/Event schema, fixtures, generated types (ADR-078) |
| [web-demo/](web-demo/) | WASM-based web demo |
| [e2e/](e2e/) | End-to-end tests |
| [website/](website/) | Project website |
| [gitlab-profile/](gitlab-profile/) | The vauchi group README on GitLab |
| [scripts/](scripts/) | Shared CI templates, hooks and workspace scripts |
| [assets/](assets/) | Logos, icons and brand assets |
| [ohttp-relay/](ohttp-relay/) | OHTTP forwarding proxy for metadata privacy |
| [features/](features/) | Gherkin feature files, the executable specification |
| [docs/](docs/) | Public documentation site (mdBook) |
| [spec/](spec/) | Protocol specification and falsifiable claims (mdBook) |
| [locales/](locales/) | Translations, one catalogue per language |
| [themes/](themes/) | Design tokens and themes |
| [vauchi-platform-swift/](vauchi-platform-swift/) | Swift package of the platform bindings (XCFramework) |

## Quick Start

### Prerequisites

- Rust 1.93+
- [just](https://github.com/casey/just) command runner

### Build

```bash
git clone https://gitlab.com/vauchi/vauchi.git
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

Create a GitLab repository from a Maintainer account:

```bash
just create-repo apple-display --description "Shared SwiftUI rendering library"
```

The recipe applies and verifies merge settings and main protection.
An existing repository is checked without changing its configuration.
It stops on missing permissions or mismatched settings and keeps any
partially created project for inspection. Workspace registration and
package bootstrap remain separate reviewed changes.

## Security

Vauchi uses:

- **X3DH** key agreement (Signal protocol)
- **Double Ratchet** for forward secrecy
- **XChaCha20-Poly1305** for symmetric encryption
- **Ed25519** for signatures
- **RustCrypto** audited crates (`ed25519-dalek`, `sha2`, `hmac`, `hkdf`)

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

- [Contributing Guide](https://vauchi.app/docs/developers/contributing) — Development workflow
- [Principles](https://vauchi.app/docs/about/principles) — Core principles (mandatory)

All code must have tests. No exceptions.

## Support the Project

[![Sponsor on GitHub](https://img.shields.io/badge/sponsor-GitHub%20Sponsors-ea4aaa)](https://github.com/sponsors/vauchi)
[![Donate on Liberapay](https://img.shields.io/badge/donate-Liberapay-f6c915)](https://liberapay.com/Vauchi/donate)

Vauchi is open source and community-funded. No VC money, no data harvesting
business model.

If you believe in privacy-respecting software:

- **GitHub Sponsors**: [Sponsor Vauchi](https://github.com/sponsors/vauchi)
- **Liberapay**: [liberapay.com/Vauchi](https://liberapay.com/Vauchi/donate)

Funds go toward:

- Development hardware and testing devices
- Infrastructure costs (relay server)
- Security audits

See [Supporters](https://vauchi.app/docs/about/supporters) for sponsorship tiers.

## License

The core library (`core`), `relay` and `ohttp-relay` are licensed under
[AGPL-3.0-or-later](https://www.gnu.org/licenses/agpl-3.0.html); the apps
and tooling under [GPL-3.0-or-later](LICENSE).

## Links

- Website: [vauchi.app](https://vauchi.app)
- Relay: wss://relay.vauchi.app
