<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Security Policy

The canonical disclosure policy is the protocol specification's
[Disclosure Policy](https://gitlab.com/vauchi/spec/-/blob/main/src/disclosure.md)
page (served at spec.vauchi.app once that site is live). This file
is the short form the `security.txt` Policy field points to; where
the two differ, the specification's page wins.

## Reporting a Vulnerability

Write to **security@vauchi.app**. Do not open a public GitLab issue
for a vulnerability. Encrypt to the project's PGP key,
[pgp-key.txt](https://vauchi.app/.well-known/pgp-key.txt), fingerprint
`4347 B1C6 57A3 97E5 206E 4709 A84E 1AAB D783 0274`; `security.txt`
carries the same fingerprint, so you can check one against the other.
Only the maintainer's hardware tokens can decrypt. If you cannot use
PGP, write in clear and say so; the reply offers another channel.

Send what you found, how to reproduce it, which security claim it
breaks if it maps to one (the
[claims page](https://gitlab.com/vauchi/spec/-/blob/main/src/claims.md)
numbers them S1 to S17), and whether you want to be named.

What to expect: an acknowledgment within 48 hours, an initial
assessment within 7 days, and a fix in the open, credited if you
wish. There is no bug bounty.

## Scope

In scope: everything the specification describes and the code it is
extracted from: `vauchi-core` and the apps that embed it (Android,
iOS, macOS, Windows, Linux, CLI, TUI), the relay (`relay/`) and the
outer OHTTP relay, and the public relay at its published address when
tested with your own identities only.

Out of scope: the production relay's availability (no load or denial
of service testing), other people's data or identities, the website
and documentation hosting, social engineering of the maintainer or
users, and third-party dependencies (report those upstream).

## Safe Harbour

Research conducted in good faith, within the scope above, against
your own identities and test data, without degrading the service for
others and without exfiltrating data that is not yours, is authorised.
The project will not pursue legal action for such research and will
not report it to law enforcement.

## What the Design Promises

The security claims, each with its attacker, status and the test or
proof behind it, live in the specification's claims page and on the
docs site's
[security claims](https://vauchi.app/docs/developers/security-claims.html)
page. In short: the relay stores what it cannot read (S1); an update
is from the contact it claims, applied once, never rolled back (S2);
the relay does not learn your network address, with the alpha's
single-operator limit stated (S3); in-person exchanges bind both
identity keys so a watcher of the QR codes gets no key (S6); the link
exchange is weaker and says so (S9); old messages stay secret after a
device compromise (S11); destroying the storage key makes the data
unrecoverable (S12).

Cryptography: X25519 and Ed25519 (`x25519-dalek`, `ed25519-dalek`),
XChaCha20-Poly1305 (`chacha20poly1305`), HKDF-SHA256 (`hkdf`, `sha2`),
Argon2id (`argon2`), Shamir's secret sharing over GF(256) in Core, and
rustls on `aws-lc-rs` for TLS. Every derivation and wire format is in
the specification's protocol chapters.

## Prior Analysis

Formal models (Tamarin, Quint, Kani) and their lemmas are listed on
the
[formal verification](https://vauchi.app/docs/developers/formal-verification.html)
page of the docs site. `cargo-audit`, `cargo-deny` and `cargo-vet`
run on every push. An external reviewer went through the public
documentation in July 2026; no external audit of the code has taken
place yet, and the specification exists so that one can.
