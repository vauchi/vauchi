# Problem: Responder cannot send card updates after exchange

## Status: done

## Problem Statement

After a contact exchange, the responder (QR displayer) cannot send card updates until they first receive a message from the initiator (QR scanner). This is because the Double Ratchet protocol requires the responder to receive a message first to establish a sending chain.

**Error message:**
```
crypto error: InvalidMessage("Cannot send: no sending chain (responder must receive first)")
```

## Origin

- **Source**: E2E smoke test `smoke_card_update` failure
- **Date Created**: 2026-01-23
- **Discovered by**: Running `just e2e-smoke`

## Impact

- **Severity**: HIGH (MVP blocker)
- Card updates fail for ~50% of exchanges (whoever displayed the QR)
- Users cannot update their card after exchanging contacts until they receive an update first
- Breaks the expected UX flow

## Technical Analysis

### Root Cause

The Double Ratchet protocol is correctly implemented:

1. `initialize_initiator()` creates a ratchet WITH a `send_chain` → can send immediately
2. `initialize_responder()` creates a ratchet WITHOUT a `send_chain` → must receive first

This is standard Signal protocol behavior for forward secrecy.

### Current Flow

```
Alice (QR displayer) ←→ Bob (QR scanner)

1. Bob scans Alice's QR
2. Bob: create_ratchet_as_initiator() → has send_chain
3. Alice: create_ratchet_as_responder() → no send_chain
4. Alice updates card → FAILS (no send_chain)
```

### Expected Flow

```
1. Bob scans Alice's QR
2. Bob: create_ratchet_as_initiator()
3. Alice: create_ratchet_as_responder()
4. Bob sends initial message (his contact card) → Alice receives
5. Alice now has send_chain via DH ratchet
6. Alice can now send updates
```

## Solution Implemented

**Chosen Solution: A - Initiator sends card immediately after exchange**

### Changes Made

1. **`cli/src/commands/exchange.rs`**:
   - Added `send_initial_card_update()` function that:
     - Creates a CardDelta from empty card to the initiator's card
     - Signs and encrypts it using the newly created ratchet
     - Sends it to the responder via relay
   - Called this function after `create_ratchet_as_initiator()` in `complete()`

2. **`e2e/src/device/cli.rs`**:
   - Fixed `parse_card()` function to correctly parse space-separated card output format
   - The previous parser looked for colons/table separators but the actual format is: `icon   label        value`

### How It Works

1. Bob (initiator/QR scanner) completes exchange and creates ratchet with send_chain
2. Bob immediately sends his encrypted card to Alice (responder/QR displayer)
3. Alice syncs and receives:
   - Exchange message → creates ratchet as responder (no send_chain)
   - Bob's encrypted card → decrypts, which triggers DH ratchet → gets send_chain
4. Alice can now send card updates to Bob

### Verification

- `just e2e-smoke` passes (both `smoke_cli_exchange` and `smoke_card_update`)

## Artifacts

- [x] Investigation document (this README)
- [ ] Knowledge documents
- [ ] Rejected solutions
- [x] Implementation plan (Solution A chosen)
- [ ] Gherkin feature
- [x] E2E tests (smoke_card_update)
- [ ] Retrospective

## Possible Solutions

### Solution A: Initiator sends card immediately after exchange
After completing exchange, the initiator automatically sends their contact card. This triggers a DH ratchet on the responder side, giving them a send chain.

### Solution B: Sync before send
Modify the update flow to sync (receive) first before attempting to send. If responder, ensure we've received at least one message.

### Solution C: Bidirectional handshake during exchange
Exchange both contact cards during the QR exchange flow itself, ensuring both parties have established ratchets.

## Investigation Questions

1. Does the current exchange flow send any messages?
2. Is there already an "exchange complete" message that should trigger this?
3. What do other Signal-protocol implementations do?

## Related Files

- `core/vauchi-core/src/crypto/ratchet.rs:186` - `initialize_responder()`
- `core/vauchi-core/src/crypto/ratchet.rs:209` - Error location
- `core/vauchi-core/src/api/vauchi.rs:326` - `create_ratchet_as_responder()`
- `e2e/tests/multi_device_sync.rs:44` - Failing test

## Child Problems

(To be populated from investigation)
