<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Claude Errors & Misjudgments Log

Track recurring Claude mistakes to identify patterns and reduce token waste.
Each entry: what happened → root cause → prevention.

---

## Session 2026-03-19: Master Plan Audit + SP-32 Implementation

### E1: Edits lost during parallel agent work (3 files, 3 re-read cycles)

**What**: Edits to `relay_client.rs`, `sync_controller.rs`, `anonymous.rs` didn't persist.
Had to re-read and re-apply each edit multiple times.

**Root cause**: Three background agents were editing files in the same `core/` repo
simultaneously. When one agent's edit triggers `rustfmt` on the workspace, it can touch
files another agent (or the main conversation) just edited. The Edit tool's stale-read
detection rejects the next edit, appearing as a "reversion."

**Prevention**: Don't run parallel agents that edit files in the same repo. After parallel
agents complete, re-read before editing. Rule: `verify-before-acting.md`.

### E2: Wrong MockTransport return type in tests

**What**: Assumed `sent_messages()` returns `Vec<Vec<u8>>`. It returns `Vec<MessageEnvelope>`.

**Root cause**: Wrote tests without reading the mock API first.

**Prevention**: Read mock/test infrastructure types before writing wire-level tests.

### E3: SP-32 percentage inconsistent across 3 documents (FIXED)

**What**: Master plan said ~60%, problem record said ~75%, roadmap said ~75%.

**Root cause**: Updated docs at different points in the session. Master plan was updated
first, then implementation happened, then only problem record and roadmap were updated.

**Prevention**: Use `just doc-refs "SP-32"` after implementation to find all references.
Update all in one commit. Fixed in private!432.

### E4: WASM problem record had wrong feature gate names

**What**: Problem record proposed `#[cfg(feature = "storage")]` and `#[cfg(feature = "network")]`.
Actual code uses `#[cfg(any(feature = "network-native-tls", feature = "network-rustls"))]`.

**Root cause**: Guessed feature names from error messages instead of checking existing
`#[cfg]` patterns in the codebase.

**Prevention**: `grep -r 'cfg.*feature' src/` before proposing new gates. Problem record
is `done` — low impact.

### E5: Launched agent for already-fixed bug (ConsentType::Analytics)

**What**: Launched background agent to remove `ConsentType::Analytics`. Agent discovered
it was already removed. Full agent execution wasted.

**Root cause**: Trusted the problem record ("implementing — Analytics still in consent.rs")
without verifying the code. The record was stale.

**Prevention**: `grep "Analytics" core/vauchi-core/src/api/consent.rs` before launching.
Rule: `verify-before-acting.md`.

### E6: "LAST P0 GAP" label wrong after adding 2 more P0 items (FIXED)

**What**: Labeled proximity audio as "LAST P0 SECURITY GAP" then added two more P0 items.

**Root cause**: Updated problem record before updating master plan with new items.

**Prevention**: Update all documents atomically after finishing a batch of changes.
Fixed in private!432.

### E7: Done problem records not moved to done/ (FIXED)

**What**: Changed WASM gating and MockProximityVerifier status to `done` without moving
to `done/` directory.

**Root cause**: Changed status field without the corresponding directory move.

**Prevention**: "Closing a problem record = change status + `git mv` to done/" in same
commit. Fixed in private!432.

### E8: `replace_all` missed call sites with different formatting

**What**: Used `replace_all` to update function callers. Only matched one of two sites
because they had different first arguments.

**Root cause**: Assumed identical text at all call sites without checking.

**Prevention**: `grep` all call sites first, update each individually.

---

## Aggregate

| Root Cause | Occurrences | Prevention |
|---|---|---|
| Trusted stale docs over code | 3 (E3, E5, E6) | Rule: verify-before-acting.md |
| Parallel agents in same repo | 1 (E1, 3 files) | Don't parallelize edits in same repo |
| Sequential doc updates | 3 (E3, E6, E7) | `just doc-refs` + atomic commits |
| Didn't read API before using | 2 (E2, E4) | Read before writing |

### Implemented fixes

1. **Rule**: `.claude/rules/verify-before-acting.md` — verify code before acting on docs
2. **Recipe**: `just doc-refs <pattern>` — find all planning doc references for batch update
3. **Errors doc**: This file — track patterns across sessions
