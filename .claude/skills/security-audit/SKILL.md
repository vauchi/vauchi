---
name: security-audit
description: Security audit of vauchi-core crypto and protocol implementation. Use when reviewing crypto code, checking for vulnerabilities, running periodic security checks, auditing DH/signature/encryption/protocol code, or when external security research (blog posts, CVEs, audit reports) surfaces patterns to check against vauchi. Also use when the user mentions "audit", "security check", "vulnerability check", "crypto review", or "hardening". Use proactively after modifying any code in crypto/, exchange/, network/, or sync/.
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi Security Audit

Structured security audit for vauchi-core's cryptographic and protocol implementation.

This skill exists because crypto bugs are subtle and pattern-based — the same classes of flaws recur across projects. Rather than relying on memory, this checklist encodes lessons from real-world audits (Vodozemac, Signal, SimpleX, Trail of Bits reports) into repeatable checks.

## When to Use

- **Periodic audit**: Run the full checklist quarterly or before major releases
- **Targeted audit**: After modifying crypto/, exchange/, network/, or sync/ code
- **External trigger**: When a new CVE, audit report, or blog post surfaces a pattern that could apply to vauchi
- **Pre-MR**: Before merging changes that touch security-critical paths

## Audit Procedure

### Phase 1: Scope

Determine what to audit based on the trigger:

| Trigger | Scope |
|---------|-------|
| Periodic / full audit | All 7 checklist categories below |
| Code change in crypto/ | Categories 1-4 (DH, signatures, encryption, key management) |
| Code change in exchange/ | Categories 1, 5 (DH, protocol) |
| Code change in network/ | Categories 5-6 (protocol, transport) |
| External research | Map findings to specific checklist items |
| Pre-release | All 7 categories + dependency check |

### Phase 2: Run Checklist

For each applicable category, search the codebase for the patterns described. Use parallel Explore agents for independent categories. Report findings as PASS/FAIL/N-A with file:line references.

---

## Checklist

### 1. Diffie-Hellman Key Exchange

**Source**: Vodozemac audit (Soatok, Feb 2026), general X25519 best practice

| ID | Check | How to Verify |
|----|-------|---------------|
| DH-01 | DH outputs validated with `was_contributory()` | Grep for `diffie_hellman(` — every call site must check the return or the central method must validate |
| DH-02 | All-zero public keys rejected before DH | Grep for `PublicKey::from` — check if input is validated before use |
| DH-03 | Small-order point rejection | Check if X25519 implementation rejects the 8 known small-order points, or if `was_contributory()` covers them |
| DH-04 | DH errors propagated, not swallowed | Verify DH validation errors reach the caller (no silent fallback to a default key) |

**Key files**: `exchange/x3dh.rs`, `crypto/ratchet.rs`, `exchange/ble_handshake.rs`, `exchange/nfc_handshake.rs`, `exchange/transport/protocol.rs`, `exchange/multistage/session.rs`

### 2. Signature Verification

**Source**: Vodozemac audit (Ed25519 strict verification), ed25519-dalek (Trail of Bits audited)

| ID | Check | How to Verify |
|----|-------|---------------|
| SIG-01 | Ed25519 strict verification enabled (no lenient mode) | Verify `ed25519_dalek::VerifyingKey::verify()` is used (strict by default in dalek 2.x) |
| SIG-02 | No signature verification behind feature flags | Grep for `#[cfg(feature` near verify calls — verification must not be optional |
| SIG-03 | Signature checked before processing payload | In message handlers, verify signature check happens before any state mutation |
| SIG-04 | Tampered signature/message tests exist | Check test files for wrong-key, tampered-message, tampered-signature test cases |

**Key files**: `crypto/signing.rs`, `exchange/exchange_payload.rs`, `relay/src/handler/verify.rs`

### 3. Encryption (Nonces & AEAD)

**Source**: Vodozemac audit (deterministic IVs), general AEAD best practice

| ID | Check | How to Verify |
|----|-------|---------------|
| ENC-01 | Nonces are random (OS CSPRNG), never deterministic | Grep for nonce generation — must use `SystemRandom` or equivalent |
| ENC-02 | Nonce size matches algorithm (24 bytes for XChaCha20) | Check constants and nonce allocation |
| ENC-03 | No nonce reuse across encryptions with same key | Verify each `encrypt()` call generates a fresh nonce |
| ENC-04 | Associated data binding in AEAD where applicable | Verify `encrypt_with_ad()` binds identity/context where messages could be replayed |
| ENC-05 | Ciphertext format includes algorithm tag | Verify format: `tag \|\| nonce \|\| ciphertext \|\| auth_tag` |
| ENC-06 | No encryption in test-only code paths that bypass auth | Grep for `#[cfg(test)]` or `#[cfg(feature = "test` near crypto code |

**Key files**: `crypto/encryption.rs`, `crypto/ratchet.rs`, `exchange/ble_handshake.rs`

### 4. Key Management

**Source**: General crypto hygiene, Vauchi principles

| ID | Check | How to Verify |
|----|-------|---------------|
| KEY-01 | Key material zeroized after use | Grep for `Zeroize`, `zeroize()`, or `Drop` impl on key types |
| KEY-02 | No key material in logs or error messages | Grep for `debug!`, `info!`, `warn!`, `error!` near key variables — keys must never appear in log output |
| KEY-03 | Symmetric keys reject all-zero values | Check `SymmetricKey::from_bytes()` validation |
| KEY-04 | Private keys not serializable by default | Check that `Serialize` is not derived on private key types without explicit reason |
| KEY-05 | Key derivation uses proper HKDF with domain separation | Check HKDF calls include unique `info` strings per use case |

**Key files**: `crypto/encryption.rs`, `crypto/signing.rs`, `crypto/hkdf.rs`, `exchange/x3dh.rs`

### 5. Protocol Versioning & Downgrade

**Source**: Vodozemac audit (V1/V2 downgrade), protocol security best practice

| ID | Check | How to Verify |
|----|-------|---------------|
| PROTO-01 | All message decoders validate protocol version | Grep for `decode_message`, `decode_simple_message` — each must reject unexpected versions |
| PROTO-02 | Version negotiation selects highest common version | Check `negotiate_version()` logic |
| PROTO-03 | No silent fallback to lower version | Verify failed negotiation returns error, not a default version |
| PROTO-04 | Negotiated version enforced on subsequent messages | After handshake, verify relay/client reject messages with wrong version |
| PROTO-05 | Version field cannot be stripped from messages | Check deserialization — missing version field must fail, not default to v1 |

**Key files**: `network/protocol.rs`, `network/simple_message.rs`, `vauchi-protocol/src/messages.rs`, `relay/src/handler/connection.rs`

### 6. Transport & Relay Security

**Source**: Vauchi architecture, zero-knowledge relay principles

| ID | Check | How to Verify |
|----|-------|---------------|
| RELAY-01 | Relay cannot decrypt message content | Verify relay only sees encrypted blobs — no plaintext key material passes through relay code |
| RELAY-02 | Authenticated handshake required before message exchange | Check relay handler rejects messages before handshake completion |
| RELAY-03 | Replay protection (timestamps, sequence numbers) | Check for nonce/timestamp validation in relay message handling |
| RELAY-04 | Rate limiting on relay endpoints | Check for rate limit middleware or per-connection throttling |
| RELAY-05 | Purge requests require authentication | Verify purge endpoint checks Ed25519 signature |

**Key files**: `relay/src/handler/`, `vauchi-protocol/src/messages.rs`

### 7. Dependencies & Supply Chain

**Source**: RustSec, cargo-audit, Vauchi dependency policy

| ID | Check | How to Verify |
|----|-------|---------------|
| DEP-01 | No RustSec advisories on direct dependencies | Run `cargo audit` or check `rustsec.org/advisories/` |
| DEP-02 | Crypto crates up to date | Check `ed25519-dalek`, `x25519-dalek`, `sha2`, `hmac`, `hkdf`, `chacha20poly1305`, `argon2` versions against crates.io |
| DEP-03 | No new crypto crates without approval | Diff `Cargo.lock` for new `*crypto*`, `*cipher*`, `*aes*`, `*rsa*` crates |
| DEP-04 | `cargo deny` passes (license + duplicate check) | Run `just deny` or `cargo deny check` |
| DEP-05 | No `unsafe` in vauchi-core (except documented FFI) | Run `cargo geiger` or grep for `unsafe` blocks |

---

## Phase 3: Report

After running the checklist, produce a summary table:

```markdown
## Security Audit — YYYY-MM-DD

| Category | Pass | Fail | N/A | Notes |
|----------|------|------|-----|-------|
| DH Key Exchange | X/4 | Y/4 | Z/4 | ... |
| Signatures | X/4 | Y/4 | Z/4 | ... |
| Encryption | X/6 | Y/6 | Z/6 | ... |
| Key Management | X/5 | Y/5 | Z/5 | ... |
| Protocol | X/5 | Y/5 | Z/5 | ... |
| Transport | X/5 | Y/5 | Z/5 | ... |
| Dependencies | X/5 | Y/5 | Z/5 | ... |
```

For each FAIL:
- File path and line number
- Description of the issue
- Suggested fix
- Priority (P0/P1/P2)

### Failure Priorities

| Priority | Criteria | Action |
|----------|----------|--------|
| P0 | Exploitable today, affects confidentiality/integrity | Create problem record immediately, containment required |
| P1 | Exploitable under specific conditions or becomes exploitable with future changes | Create problem record, schedule for next sprint |
| P2 | Defense-in-depth gap, no current exploitation path | Track in existing problem record or backlog |

## Phase 4: Problem Records

For P0 and P1 findings, create problem records in `_private/docs/problems/YYYY-MM-DD-<slug>/`:
- Follow the problem record template (see existing records for structure)
- Include containment assessment
- Include test strategy (CC-14: adversarial test data for security boundaries)
- Link to the source that triggered the audit

## Maintaining This Skill

When new security research surfaces patterns not covered by this checklist:
1. Add a new check ID under the appropriate category
2. Note the source in the category header
3. If it's a new category, add it with its own section

Known sources to watch (from `_private/docs/2026-02-03-websites-to-monitor.md`):
- Soatok / Dhole Moments — protocol analysis
- Trail of Bits — audit methodology, constant-time
- SimpleX Chat — closest architectural cousin
- Signal — protocol updates, PQ migration
- RustSec — dependency advisories
