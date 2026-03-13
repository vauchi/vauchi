# Bidirectional Face-to-Face Exchange Protocol

## Overview

Both devices exchange contacts in a single coordinated interaction using QR codes for identity/key exchange and ultrasonic audio for mutual scanning confirmation. No relay involved — fully local.

## Sequence Diagram

```
    Alice (iOS)                                    Bob (Android)
    ═══════════                                    ════════════

    ┌─────────────────── Phase 1: Display + Scan ───────────────────┐
    │                                                                │
    │  createSession()                          createSession()      │
    │  generateQr() → QR_A                      generateQr() → QR_B │
    │  (ephemeral key E_A,                      (ephemeral key E_B,  │
    │   challenge C_A)                           challenge C_B)      │
    │                                                                │
    │  ┌──────────┐  front cameras  ┌──────────┐                    │
    │  │ QR_A     │◄───────────────►│ QR_B     │                    │
    │  │ displayed │  scanning      │ displayed │                    │
    │  └──────────┘                 └──────────┘                    │
    │                                                                │
    │  emit C_A via ultrasonic )))  ((( emit C_B via ultrasonic     │
    └────────────────────────────────────────────────────────────────┘

    ┌─────────── Phase 2: QR Detected (order doesn't matter) ──────┐
    │                                                                │
    │  Camera detects QR_B                Camera detects QR_A       │
    │  session.processQr(QR_B)            session.processQr(QR_A)   │
    │  → extracts E_B, C_B, "bob"         → extracts E_A, C_A, "alice"
    │  → state: PeerScanned               → state: PeerScanned     │
    │                                                                │
    │  UI: "Found bob!"                   UI: "Found alice!"        │
    └────────────────────────────────────────────────────────────────┘

    ┌────────────── Phase 3: Ultrasonic Coordination ───────────────┐
    │                                                                │
    │  Loop:                               Loop:                    │
    │  emit C_B (250ms) )))────────────►  listen for C_B (2000ms)  │
    │  listen for C_A (2000ms) ◄────((( emit C_A (250ms)           │
    │                                                                │
    │  Hears C_A back!                    Hears C_B back!           │
    │  → "Bob scanned my QR"             → "Alice scanned my QR"   │
    │  → MUTUAL CONFIRMED ✓              → MUTUAL CONFIRMED ✓      │
    │                                                                │
    │  UI: "Verifying proximity..."       UI: "Verifying proximity..."
    └────────────────────────────────────────────────────────────────┘

    ┌─────────────── Phase 4: Complete (independently) ─────────────┐
    │                                                                │
    │  confirmProximity()                 confirmProximity()         │
    │  theyScannedOurQr()                 theyScannedOurQr()        │
    │  performKeyAgreement()              performKeyAgreement()     │
    │    DH(E_A_secret, E_B_pub)            DH(E_B_secret, E_A_pub)│
    │    = SHARED_KEY ←─── SAME! ───────►   = SHARED_KEY           │
    │  completeCardExchange("bob")        completeCardExchange("alice")
    │  finalizeExchange()                 finalizeExchange()        │
    │                                                                │
    │  Result: Contact "bob" saved        Result: Contact "alice" saved
    │  + double ratchet initialized       + double ratchet initialized
    │  + SAME shared key on both sides    + SAME shared key on both sides
    │                                                                │
    │  UI: "Contact exchanged! ✓"         UI: "Contact exchanged! ✓"│
    └────────────────────────────────────────────────────────────────┘
```

## Why It's Bidirectional

1. **Same session** — each device uses the session that generated its displayed QR (same ephemeral key), not a fresh one
2. **Both scan** — each camera independently detects the other's QR
3. **Ultrasonic confirms mutual scanning** — hearing your own challenge back proves the other device scanned your QR
4. **X25519 DH is commutative** — `DH(E_A, E_B) == DH(E_B, E_A)` → identical shared key
5. **Both finalize independently** — each device saves the other as a contact with matching crypto state

## Ultrasonic Coordination Protocol

After scanning peer's QR, each device independently runs:

```
function coordinateExchange(myChallenge, theirChallenge, timeout=12s):
    while elapsed < timeout:
        emit(theirChallenge, duration=250ms)   // "I scanned your QR"
        response = listen(duration=2000ms)      // waiting for "they scanned mine"
        if response == myChallenge:
            return CONFIRMED
    return TIMEOUT → manual fallback
```

- Audio is half-duplex (can't emit+receive simultaneously)
- 250ms emit / 2000ms listen asymmetry maximizes catch probability
- FSK modulation at 18.5-18.7 kHz (inaudible)
- Challenge is 16 bytes from QR code (bytes 101-117)

## Fallback

If ultrasonic times out (12s), a "Confirm face-to-face" button appears. Tapping it replaces the ultrasonic confirmation and proceeds with the same completion path (ManualConfirmationVerifier).

## UI States

```
scanning → scanned(peerName) → coordinating → completing → success
                                    ↓
                               manualFallback → completing → success
```

## QR Format Reference

```
wb://<base64(
  MAGIC(4)      "WBEX"
  Version(1)    0x02
  PubKey(32)    Ed25519 identity key
  ExchKey(32)   X25519 ephemeral (FRESH per session)
  Token(32)     Random exchange token
  Challenge(16) Audio proximity challenge seed
  Timestamp(8)  Unix timestamp (big-endian)
  NameLen(2)    Display name length
  Name(0-255)   UTF-8 display name
  Sig(64)       Ed25519 signature over all above
)>
```
