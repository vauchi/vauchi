# Funding Pitch & Announcement Templates

## Short Pitch (Twitter/Mastodon - 280 chars)

```
Vauchi: Privacy-first contact cards. Exchange via QR, update anytime, E2E encrypted. No accounts, no tracking.

Now open source. Help us build privacy-respecting software.

GitHub: github.com/vauchi/vauchi
Sponsor: github.com/sponsors/vauchi
```

## Medium Pitch (Reddit r/privacy, r/opensource)

```
# Vauchi: Open-source, E2E encrypted contact cards — now seeking community support

Hey r/privacy,

I've been building Vauchi — a privacy-focused way to exchange and update contact information.

**The problem**: Business cards go stale. Contact apps harvest your data. QR codes can't be updated after sharing.

**Vauchi's approach**:
- Exchange contacts in person via QR code
- Update your info anytime — everyone with your card sees changes
- End-to-end encrypted (Signal protocol: X3DH + Double Ratchet)
- Zero-knowledge relay (we can't read your data)
- No accounts — your device is your identity
- No tracking, no analytics, no data harvesting

**Tech stack**: Rust core, iOS (SwiftUI), Android (Kotlin/Compose), Desktop (Tauri)

**Why open source?** Privacy software should be auditable. We're not taking VC money — this is community-funded.

**What we need**:
- Test devices (iOS + Android) for real-world testing
- Security audit funding
- Development hardware

If you believe in privacy-respecting software, consider:
- ⭐ Star on GitHub: https://github.com/vauchi/vauchi
- 💜 Sponsor: https://github.com/sponsors/vauchi
- 🔍 Code review / contributions welcome

Happy to answer questions about the architecture or crypto implementation.
```

## Long Pitch (Hacker News "Show HN")

```
Show HN: Vauchi – Open-source E2E encrypted contact cards (Rust, Signal protocol)

https://github.com/vauchi/vauchi

I built Vauchi to solve a personal frustration: contact information goes stale, and existing solutions either don't update or require trusting a company with your data.

## How it works

1. Meet someone in person, scan their QR code
2. Your devices establish an encrypted channel (X3DH key agreement)
3. Contact cards sync via a relay that sees only encrypted blobs
4. Update your card anytime — all your contacts receive the update
5. Forward secrecy via Double Ratchet — compromised keys don't expose history

## Key principles

- **No accounts**: Your device keypair IS your identity
- **In-person exchange**: Trust is established face-to-face, not by platforms
- **Zero knowledge**: The relay routes encrypted messages, can't read content
- **No tracking**: No analytics, no telemetry, no advertising IDs

## Technical details

- Core library in Rust (`ring` for all crypto, no OpenSSL)
- Mobile via UniFFI bindings (iOS: SwiftUI, Android: Kotlin/Compose)
- Desktop via Tauri + SolidJS
- CLI and TUI for terminal users
- 966 tests, 90%+ coverage requirement for crypto code

## Why open source now?

I want this to be community-owned. Privacy software shouldn't depend on a company's business model. We're using Open Collective for transparent finances — you can see exactly where money goes.

## What's working

- ✅ E2E encryption
- ✅ Contact exchange (QR, audio proximity)
- ✅ Card updates with forward secrecy
- ✅ Multi-device sync
- ✅ Contact recovery (social vouching)
- ✅ Relay server (live at relay.vauchi.app)

## What's next

- Real device testing (need hardware)
- Security audit
- App store releases

## Links

- GitHub: https://github.com/vauchi/vauchi
- Sponsor: https://github.com/sponsors/vauchi
- Open Collective: https://opencollective.com/vauchi

Happy to discuss the crypto implementation, threat model, or architecture decisions.
```

## Email to Privacy-Focused Organizations

```
Subject: Vauchi — Open-source E2E encrypted contact sharing (seeking feedback/partnership)

Hi [Name],

I'm building Vauchi, an open-source tool for privacy-respecting contact sharing.

The core idea: exchange contact cards in person via QR code, with end-to-end encryption. When you update your phone number or email, everyone who has your card sees the change — without any central server having access to your data.

We use Signal protocol cryptography (X3DH + Double Ratchet) and run a zero-knowledge relay that sees only encrypted blobs.

Why I'm reaching out:
- [If applicable: Your organization's work on X aligns with our mission]
- Seeking feedback on our threat model and crypto implementation
- Open to partnerships with privacy-focused organizations
- Looking for security review from experienced cryptographers

Links:
- GitHub: https://github.com/vauchi/vauchi
- Threat Model: https://github.com/vauchi/vauchi/blob/main/docs/2026-01-22-THREAT_ANALYSIS.md
- Principles: https://github.com/vauchi/vauchi/blob/main/docs/2026-01-23-PRINCIPLES.md

Would you be open to a brief call or async review?

Best,
[Your name]
```

## For Grant Applications (NLnet, NGI, etc.)

```
## Project Summary

Vauchi is open-source software for privacy-respecting contact information exchange. Users exchange contact cards in person via QR code and receive updates when contacts change their information — all with end-to-end encryption and without requiring accounts or trusting a central server.

## Problem Statement

Current contact sharing solutions either:
1. Go stale immediately (business cards, static QR codes)
2. Require trusting a company with sensitive contact data
3. Harvest user data for advertising

There is no privacy-respecting solution for updatable contact information.

## Technical Approach

- End-to-end encryption using Signal protocol (X3DH + Double Ratchet)
- Zero-knowledge relay server (routes encrypted blobs only)
- Device-based identity (no accounts, no passwords)
- In-person exchange establishes trust (QR code with proximity verification)
- Forward secrecy ensures past messages remain secure if keys are compromised

## Current Status

- Core library complete (Rust, 966 tests)
- Mobile apps functional (iOS, Android)
- Desktop app functional (Tauri)
- Relay server deployed and operational
- Seeking funding for: security audit, test hardware, v1.0 release

## Requested Funding

[Amount] for:
- External security audit of cryptographic implementation
- Development hardware (macOS, Linux, Windows CI)
- Mobile test devices (iOS + Android coverage)
- [X months] of focused development toward v1.0

## Open Source Commitment

- MIT licensed
- Fully transparent development on GitHub
- Open Collective for financial transparency
- No proprietary dependencies
```
