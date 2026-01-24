# NFC Tag as User Device - Feature Investigation

**Date**: 2026-01-22
**Status**: Accepted
**Priority**: Post-MVP
**Author**: Claude (Investigation)

## Problem Statement

Users want to share their contact information without needing their phone present. An NFC tag (sticker, card, ring, etc.) could serve as a passive "device" that allows contact exchange when tapped.

**Key constraint**: NFC tags are passive - they cannot perform cryptographic operations, store secrets securely, or initiate network connections.

## Current Architecture Context

The current device model assumes active devices that can:
- Store and derive keys from a master seed
- Perform X3DH key agreement
- Sign and verify data
- Connect to relay servers for updates
- Sync with other devices

An NFC tag cannot do any of these. This requires a fundamentally different approach.

## Design Options

### Option 1: Static Contact Card (No Encryption)

**How it works:**
- NFC tag stores a pre-signed, readable contact card
- Scanner gets contact info directly (like a digital business card)
- No key exchange, no E2E encryption, no updates

**Tag contents:**
```
Magic: "VCHI" (4 bytes)
Version: 1 (1 byte)
Signed Card: ~200-500 bytes
Signature: 64 bytes (Ed25519)
```

**Pros:**
- Simplest implementation
- Works with any NFC-capable phone
- No app required to read (just NDEF text record)

**Cons:**
- No privacy: anyone who taps gets all info
- No bidirectional exchange
- No updates: card is frozen at write time
- No E2E encryption for future communications
- Violates Vauchi's privacy-first principle

**Verdict**: Not recommended - defeats the purpose of Vauchi.

---

### Option 2: QR-Equivalent Exchange Payload

**How it works:**
- NFC tag stores an `ExchangeQR` equivalent payload
- Scanner's app processes it like a scanned QR code
- Requires Vauchi app on scanner's phone
- Proximity verified by NFC tap (centimeter range)

**Tag contents:**
```
Magic: "VBEX" (4 bytes)
Version: 2 (1 byte)
Signing Public Key: 32 bytes
Exchange Public Key: 32 bytes
Exchange Token: 32 bytes
Audio Challenge Seed: 16 bytes (ignored for NFC)
Timestamp: 8 bytes
Signature: 64 bytes
Total: ~190 bytes (fits in most NFC tags)
```

**Flow:**
1. User writes exchange payload to NFC tag
2. Contact taps tag with Vauchi app
3. App processes payload, performs X3DH with user's static exchange key
4. Contact card sent to user's relay mailbox (encrypted)
5. User's real device fetches and decrypts later

**Pros:**
- Leverages existing exchange protocol
- E2E encrypted exchange
- Bidirectional possible via relay

**Cons:**
- Static exchange key = no forward secrecy
- Token never expires (can't update NFC tag remotely)
- Replay concerns if someone copies the tag
- User must check relay to get new contacts

**Verdict**: Viable but has security tradeoffs.

---

### Option 3: One-Time Key Bundle (Pre-signed Keys)

**How it works:**
- User pre-generates N one-time exchange keys
- Each key is signed by identity signing key
- NFC tag cycles through keys (or uses counter)
- Each key can only be used once

**Tag contents:**
```
Magic: "VBNF" (4 bytes)
Version: 1 (1 byte)
Identity Signing Key: 32 bytes
Current Key Index: 4 bytes
One-Time Keys: 32 bytes x N
Signatures: 64 bytes x N
Relay Mailbox ID: 32 bytes
```

**Challenges:**
- NFC tags have limited write cycles
- Counter management is complex
- Tag capacity limits key count
- If keys exhausted, tag becomes useless

**Tag capacity examples:**
- NTAG213: 144 bytes → ~1-2 keys
- NTAG215: 504 bytes → ~6-8 keys
- NTAG216: 888 bytes → ~12-15 keys

**Verdict**: Technically interesting but impractical.

---

### Option 4: Relay Mailbox Pointer

**How it works:**
- NFC tag contains minimal info: identity key + relay mailbox address
- Scanner sends encrypted introduction to mailbox
- User's real device processes introductions asynchronously

**Tag contents:**
```
Magic: "VBMB" (4 bytes)
Version: 1 (1 byte)
Identity Signing Key: 32 bytes
Exchange Public Key: 32 bytes
Relay URL: ~50 bytes (compressed/hashed)
Signature: 64 bytes
Total: ~183 bytes
```

**Flow:**
1. Contact taps NFC tag
2. Vauchi app extracts mailbox info
3. Contact performs X3DH, encrypts their card
4. Contact sends encrypted payload to relay mailbox
5. User's phone later fetches mailbox, decrypts, approves contacts

**Pros:**
- Asynchronous - user doesn't need phone present
- Full E2E encryption
- User can approve/reject contacts later
- Simple tag contents

**Cons:**
- No immediate bidirectional exchange
- Static exchange key (same concern as Option 2)
- Requires relay availability
- Spam potential: anyone can send to mailbox

**Verdict**: Practical and aligns with Vauchi architecture.

---

### Option 5: Hybrid with Rate Limiting

**Enhancement to Option 4:**

Add anti-spam and freshness mechanisms:

**Tag contents (same as Option 4):**
```
Identity Signing Key + Exchange Key + Relay Mailbox + Signature
```

**Additional server-side features:**
- Rate limiting per mailbox (max 10 intros/day)
- Captcha or proof-of-work for introductions
- User can set mailbox to "closed" remotely
- Introductions queue with expiry (7 days)

**Client-side features:**
- User gets push notification for new intros
- Can approve/reject from notification
- Batch process multiple intros

**Verdict**: Most practical solution with spam protection.

---

## Recommended Approach: Option 4/5 (Relay Mailbox)

### Why this approach?

1. **Minimal tag requirements**: ~183 bytes fits any NFC tag
2. **Leverages existing infrastructure**: Uses relay server
3. **Preserves E2E encryption**: X3DH still applies
4. **Async-friendly**: Matches real-world NFC tag use cases
5. **Updateable**: Tag can be rewritten if identity changes
6. **Spam-manageable**: Server-side rate limiting

### Security Considerations

| Concern | Mitigation |
|---------|------------|
| Static exchange key | Accept tradeoff for NFC; real devices use ephemeral keys |
| Replay attacks | Each intro creates unique shared secret via X3DH ephemeral |
| Mailbox spam | Rate limiting, proof-of-work, user can close mailbox |
| Tag cloning | Signature prevents forgery; clones lead to same mailbox |
| No proximity proof | NFC tap range (~4cm) provides physical proximity |

---

## Password-Protected NFC Exchange (Enhanced Security)

### Concept

The NFC tag owner verbally gives a password/PIN to the person scanning. This adds **authorization** on top of proximity:

- **NFC tap** = "You are physically here"
- **Password** = "I (tag owner) authorized this specific exchange"

This prevents:
- Unauthorized scanning when tag is unattended (e.g., on a desk, bag)
- "Drive-by" scanning in crowds
- Malicious scanning while owner is distracted

### How It Works

**Tag contents (modified):**
```
Magic: "VBNP" (4 bytes) - "NFC Protected"
Version: 1 (1 byte)
Identity Signing Key: 32 bytes
Exchange Public Key: 32 bytes
Relay Mailbox ID: 32 bytes
Password Salt: 16 bytes
Password Verifier: 32 bytes (PBKDF2 hash)
Signature: 64 bytes
Total: ~213 bytes
```

**Exchange flow:**
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Tag Owner  │     │  Contact    │     │             │
│  (Alice)    │     │  (Bob)      │     │             │
└──────┬──────┘     └──────┬──────┘     │             │
       │                   │            │             │
       │  "Tap my tag,     │            │             │
       │   password is     │            │             │
       │   'coffee'"       │            │             │
       │──────────────────→│            │             │
       │                   │            │             │
       │            ┌──────┴──────┐     │             │
       │            │  NFC Tag    │     │             │
       │            │  (passive)  │     │             │
       │            └──────┬──────┘     │             │
       │                   │            │             │
       │              tap  │            │             │
       │            ←──────│            │             │
       │                   │            │             │
       │            App prompts:        │             │
       │            "Enter password"    │             │
       │                   │            │             │
       │            Bob enters          │             │
       │            "coffee"            │             │
       │                   │            │             │
       │            Password verified   │             │
       │            locally via         │             │
       │            PBKDF2(pwd, salt)   │             │
       │            == verifier         │             │
       │                   │            │             │
       │            If match:           │  Relay      │
       │            derive intro key    │  Server     │
       │            from password       │             │
       │                   │            └──────┬──────┘
       │                   │                   │
       │                   │ Send encrypted    │
       │                   │ intro (key =      │
       │                   │ pwd-derived)      │
       │                   │──────────────────→│
       │                   │                   │
```

### Cryptographic Details

**Password serves dual purpose:**

1. **Local verification** (spam prevention):
   ```
   verifier = PBKDF2(password, salt, 100000)
   if hash(entered) != verifier: reject locally
   ```

2. **Key derivation** (intro encryption):
   ```
   intro_key = HKDF(
     ikm = X3DH_shared_secret,
     salt = PBKDF2(password, salt, 100000),
     info = "Vauchi_NFC_Intro"
   )
   ```

This means:
- Wrong password → can't even send spam to mailbox (fails locally)
- Correct password → intro encrypted with password-derived component
- Server can't decrypt (doesn't know password)
- Tag owner's device derives same key to decrypt

### Password Options

| Type | Example | Security | UX |
|------|---------|----------|-----|
| Numeric PIN | "1234" | Low | Easy to share verbally |
| Word | "coffee" | Medium | Natural in conversation |
| Phrase | "blue-tiger-42" | High | Memorable, harder to overhear |
| Time-based | TOTP code | Very High | Requires app, changes every 30s |

**Recommendation**: Default to 4-6 character word, allow user to choose complexity.

### Tag Modes

User can create tags in different modes:

| Mode | Password | Use Case |
|------|----------|----------|
| **Open** | None | Public sharing (conferences, storefronts) |
| **Protected** | Static | Personal sharing (1:1 meetings) |
| **Rotating** | TOTP | High security (changes every 30s) |

### TOTP Mode (Advanced)

For maximum security, password could be time-based:

```
Tag stores: TOTP secret (encrypted to owner's key)
Password = TOTP(secret, current_time_window)
```

- Owner tells contact current code from their phone
- Code valid for 30 seconds
- Even if someone overhears, code expires quickly

**Tradeoff**: Requires owner to have phone nearby to give code (partially defeats "phone-free" goal).

### Feature Scenarios

```gherkin
@nfc @tag @password
Scenario: Create password-protected NFC tag
  Given Alice has Vauchi installed
  When Alice creates an NFC tag with password "meetup"
  Then the tag should contain a password verifier
  And the password should not be stored in plaintext
  And Alice should see "Share password verbally when exchanging"

@nfc @tag @password
Scenario: Scan protected tag with correct password
  Given Alice has a password-protected NFC tag (password: "meetup")
  And Bob has Vauchi installed
  When Bob taps Alice's NFC tag
  Then Bob should see "Enter password to connect"
  When Bob enters "meetup"
  Then password should be verified locally
  And Bob's introduction should be sent to Alice's mailbox
  And the introduction should be encrypted with password-derived key

@nfc @tag @password
Scenario: Scan protected tag with wrong password
  Given Alice has a password-protected NFC tag (password: "meetup")
  When Eve taps the tag and enters "wrong"
  Then password verification should fail locally
  And no introduction should be sent
  And Eve should see "Incorrect password"
  And Alice should not be notified

@nfc @tag @password
Scenario: Brute force protection
  Given Alice has a password-protected NFC tag
  When someone enters wrong password 5 times
  Then the app should enforce a 5-minute cooldown
  And show "Too many attempts, try again later"

@nfc @tag @totp
Scenario: Create TOTP-protected NFC tag
  Given Alice wants maximum security
  When Alice creates an NFC tag with TOTP protection
  Then the tag should store encrypted TOTP secret
  And Alice's app should show current TOTP code
  And the code should rotate every 30 seconds

@nfc @tag @totp
Scenario: Scan TOTP tag with current code
  Given Alice has a TOTP-protected NFC tag
  And Alice tells Bob the current code "847293"
  When Bob taps and enters "847293" within 30 seconds
  Then the introduction should succeed
  When Charlie tries "847293" after 60 seconds
  Then the introduction should fail with "Code expired"
```

### Comparison: With vs Without Password

| Aspect | Open Tag | Password-Protected |
|--------|----------|-------------------|
| Unauthorized scans | Possible | Blocked |
| Spam to mailbox | Rate-limited only | Impossible without password |
| Owner must be present | No | Yes (to give password) |
| UX complexity | Simple tap | Tap + enter password |
| Tag cloning risk | Full access | Useless without password |
| Use case | Public/broadcast | Personal/controlled |

### Data Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  NFC Tag    │     │  Contact's  │     │  Relay      │
│  (passive)  │     │  Phone      │     │  Server     │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │  ← tap →          │                   │
       │  read tag data    │                   │
       │──────────────────→│                   │
       │                   │                   │
       │                   │ X3DH key agreement│
       │                   │ (ephemeral + tag's│
       │                   │  static exchange) │
       │                   │                   │
       │                   │ encrypt contact   │
       │                   │ card + send       │
       │                   │──────────────────→│
       │                   │                   │
       │                   │                   │ store in
       │                   │                   │ mailbox
       │                   │                   │
                                               │
┌─────────────┐                                │
│  User's     │                                │
│  Phone      │←───────────────────────────────│
└──────┬──────┘   fetch mailbox               │
       │          decrypt intros               │
       │          approve/reject               │
       │                                       │
       │          if approved: send            │
       │          encrypted card back          │
       │──────────────────────────────────────→│
       │                                       │
       │                                       │ forward to
       │                                       │ contact
```

### Implementation Phases

**Phase 1: Core Protocol**
- [ ] Define `NfcTagPayload` struct (open mode)
- [ ] Define `ProtectedNfcTagPayload` struct (with password verifier)
- [ ] Define `Introduction` message type
- [ ] Add mailbox API to relay server
- [ ] Implement introduction encryption/decryption

**Phase 2: Tag Management**
- [ ] Add "Create NFC Tag" flow to mobile apps
- [ ] Tag mode selection: Open / Password-Protected / TOTP
- [ ] Password verifier generation (PBKDF2)
- [ ] Generate and sign NFC payload
- [ ] Write to tag via NFC API
- [ ] Store tag metadata in device registry

**Phase 3: Introduction Handling**
- [ ] Add introduction inbox to client
- [ ] Push notifications for new intros
- [ ] Approve/reject UI flow
- [ ] Convert approved intro to full contact

**Phase 4: Password Verification (Scanner Side)**
- [ ] Password entry UI after NFC tap
- [ ] Local password verification against verifier
- [ ] Brute-force protection (lockout after N attempts)
- [ ] Password-derived key incorporation into X3DH

**Phase 5: Spam Protection**
- [ ] Rate limiting per mailbox
- [ ] Mailbox open/closed state
- [ ] Block list for abusers

**Phase 6: TOTP Mode (Optional/Advanced)**
- [ ] TOTP secret generation and storage
- [ ] TOTP code display in owner's app
- [ ] TOTP verification on scanner side
- [ ] Time window tolerance (±1 window)

### Feature File Scenarios

```gherkin
@nfc @tag
Scenario: Create NFC tag for contact sharing
  Given Alice has Vauchi installed with identity "Alice"
  When Alice selects "Create NFC Tag"
  Then Alice should see NFC tag payload data
  And Alice can write it to an NFC tag
  And the tag should contain Alice's exchange public key
  And the tag should contain Alice's relay mailbox address

@nfc @tag
Scenario: Contact scans user's NFC tag
  Given Alice has created an NFC tag
  And Bob has Vauchi installed
  When Bob taps Alice's NFC tag
  Then Bob's app should parse the tag data
  And Bob should see "Send introduction to Alice?"
  When Bob confirms
  Then Bob's contact card should be encrypted
  And sent to Alice's relay mailbox

@nfc @tag
Scenario: User receives introduction from NFC tag scan
  Given Alice has an NFC tag
  And Bob has scanned Alice's tag and sent introduction
  When Alice opens Vauchi
  Then Alice should see "1 new introduction"
  When Alice views the introduction
  Then Alice should see Bob's contact card
  And Alice can "Accept" or "Decline"

@nfc @tag
Scenario: Accept introduction creates bidirectional contact
  Given Alice has received an introduction from Bob
  When Alice accepts the introduction
  Then Bob should be added to Alice's contacts
  And Alice's contact card should be sent to Bob
  And Bob should see "Alice accepted your introduction"

@nfc @tag @spam
Scenario: Rate limit introductions to mailbox
  Given Alice's NFC tag has been scanned 10 times today
  When Charlie scans Alice's NFC tag
  Then Charlie should see "Mailbox temporarily full"
  And the introduction should be queued for tomorrow

@nfc @tag
Scenario: Close mailbox to stop introductions
  Given Alice wants to stop receiving NFC introductions
  When Alice closes her NFC mailbox
  Then new tag scans should show "Mailbox closed"
  And Alice's existing NFC tags become inactive
```

## Open Questions

1. **Tag identification**: Should each tag have a unique ID to track/revoke individually?
2. **Tag expiry**: Should tags expire after a certain time (requiring re-write)?
3. **Multiple tags**: Can a user have multiple active NFC tags?
4. **Offline mode**: What if contact's phone has no internet when scanning?
5. **Non-app scanners**: Show info website if scanned without Vauchi app?
6. **Default mode**: Should tags be password-protected by default, or open by default?
7. **Password change**: Can user change password without rewriting tag? (No - password verifier is on tag)
8. **Password hints**: Should tag optionally store an encrypted hint?

## Alternatives Considered

- **Smart cards with crypto chip**: Too expensive, requires special hardware
- **BLE beacons**: Battery-powered, not truly passive
- **Deep link QR + NFC hybrid**: Overcomplicated

## Next Steps

1. User review and feedback on this proposal
2. If accepted, move to `todo/` and begin implementation
3. Start with Phase 1 (Core Protocol) in vauchi-core
