<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Claude Errors & Misjudgments Log

Track recurring Claude mistakes and misjudgments to identify patterns, reduce token waste,
and find opportunities for hooks or rules that prevent recurrence.

**Format**: Each entry has: what happened → tokens wasted → root cause → fix

---

## Session 2026-03-19: Master Plan Audit + SP-32 Implementation

### E1: Linter reverted edits silently (3 occurrences, ~2000 tokens wasted)

**What**: Applied edits to `relay_client.rs`, `sync_controller.rs`, and `anonymous.rs`. The
post-edit linter (`cargo fmt` or similar) silently reverted the changes. Had to re-read and
re-apply each edit, sometimes 3 times for the same file.

**Root cause**: The Edit tool triggers a linter hook that can reformat (expected) but in this
case it appears to have restored the original file content. Likely the linter's rewrite
overwrites the edit when the file is re-read from disk.

**Tokens wasted**: ~2000 (3× read-edit-verify cycles per file, 3 files)

**Fix**: After editing a file, immediately verify with `grep` that the change is present
before proceeding. If reverted, investigate the hook rather than blindly retrying. Consider
a rule: "After editing Rust files, always verify the edit took hold before building."

---

### E2: `sent_messages()` return type wrong in tests (~500 tokens)

**What**: Wrote test code assuming `MockTransport::sent_messages()` returns `Vec<Vec<u8>>`.
It actually returns `Vec<MessageEnvelope>`. Had to recompile, diagnose, and fix.

**Root cause**: Didn't read the `MockTransport` API before writing tests. Assumed bytes-based
API from the name.

**Tokens wasted**: ~500 (compile error → read error → fix → recompile)

**Fix**: Always read the mock/test infrastructure types before writing wire-level tests. Or
use a rule: "Before writing tests that use MockTransport, read its API first."

---

### E3: Master plan SP-32 percentage stale after implementation (~300 tokens)

**What**: Updated SP-32 to ~60% in the master plan during housekeeping. Then implemented
code that brought it to ~75%. The master plan still said ~60% when I updated the problem
record to 75%. Cross-document inconsistency.

**Root cause**: Updated docs at two different times. The master plan was updated first
(housekeeping phase), then implementation happened, then only the problem record and roadmap
were updated. The master plan was forgotten.

**Tokens wasted**: ~300 (inconsistency found during audit, extra doc update MR)

**Fix**: When implementation changes a percentage, update ALL documents that reference it
in a single commit. Use `grep` to find all references: `grep -r "SP-32" _private/docs/`.

**Status**: Master plan still says ~60% (line 153). **Needs fix.**

---

### E4: WASM problem record says "storage" feature but code uses "network-native-tls/network-rustls" (~200 tokens)

**What**: The WASM gating problem record (created by me) says the fix is to gate behind
`#[cfg(feature = "storage")]` and `#[cfg(feature = "network")]`. The actual implementation
(by Stream B agent) used `#[cfg(any(feature = "network-native-tls", feature = "network-rustls"))]`.
The problem record's fix strategy is wrong.

**Root cause**: Guessed the feature names from the error messages (`could not find network`)
instead of reading the actual `#[cfg]` patterns used in the codebase. The feature gate names
are more specific than the module names.

**Tokens wasted**: ~200 (incorrect documentation, not actionable since code is correct)

**Fix**: Always check existing `#[cfg]` patterns in the file before proposing new ones.
`grep -r 'cfg.*feature.*network' src/` would have shown the correct names.

**Status**: Problem record has wrong fix strategy. But it's marked `done` so low impact.

---

### E5: ConsentType::Analytics reported as "needs removal" but was already removed (~1500 tokens)

**What**: Identified `ConsentType::Analytics` removal as a P0 task (Stream D). Launched a
background agent to do it. Agent discovered the variant was already removed from the enum.
Wasted agent execution time on a solved problem.

**Root cause**: Read the problem record (which said "implementing — Analytics still in
consent.rs") but didn't verify against the actual code. The problem record was stale — the
variant had been removed in a previous session.

**Tokens wasted**: ~1500 (full agent execution reading files, discovering it's done, only
doing test comment cleanup)

**Fix**: Before launching an implementation agent, always verify the actual code state with
a quick grep: `grep "Analytics" core/vauchi-core/src/api/consent.rs`. Trust code over docs.
**Rule candidate**: "Before implementing a fix, verify the bug still exists in code."

---

### E6: Proximity audio priority said "LAST P0 GAP" but there are now 3 P0 gaps (~100 tokens)

**What**: Updated the proximity audio problem record to say `P0 — LAST P0 SECURITY GAP`.
But during the same session, I also added two more P0 items (proximity unidirectional +
MockProximityVerifier). So "LAST" is no longer accurate.

**Root cause**: Updated the problem record before updating the master plan with the new items.
Sequential edits created a temporal inconsistency.

**Tokens wasted**: ~100 (minor wording issue)

**Fix**: The master plan now says "4/7 CLOSED" which is correct. The problem record should
not say "LAST" — it should just say "P0 SECURITY GAP". **Needs fix.**

---

### E7: Created problem record in wrong location (~100 tokens)

**What**: WASM gating problem record created at `_private/docs/problems/2026-03-19-wasm-compilation-gating/`
but it's now `done`. Done records should be in `_private/docs/problems/done/`. It was never moved.

**Root cause**: Created the record while it was `implementing`, then changed status to `done`
without moving the directory.

**Tokens wasted**: ~100 (will need a separate commit to move it)

**Fix**: When changing a problem record status to `done`, also move it to `done/` in the
same commit. **Rule candidate**: "Closing a problem record = change status + move to done/."

---

### E8: `replace_all` on non-unique strings hit wrong call sites (~300 tokens)

**What**: Used `replace_all: true` to update `send_update()` callers but the replacement
pattern `.send_update(&update.contact_id, ratchet, &update.payload, &update.id)` only
matched one of the two call sites. The second had slightly different formatting (different
first argument). Had to do a second pass.

**Root cause**: Assumed both call sites had identical text. They didn't.

**Tokens wasted**: ~300 (extra read-edit cycle)

**Fix**: When updating function signatures, use `grep` to find ALL call sites first, then
update each individually. `replace_all` is only safe for truly identical patterns like
variable renames.

---

## Aggregate Analysis

| Category | Occurrences | Tokens wasted | Fix type |
|----------|-------------|---------------|----------|
| Linter reverts edits | 3 | ~2000 | Verify after edit (habit) |
| Stale docs / code mismatch | 3 (E3, E5, E6) | ~1900 | Verify code before acting on docs |
| Wrong API assumptions | 1 (E2) | ~500 | Read API before writing tests |
| Wrong feature gate names | 1 (E4) | ~200 | Check existing patterns |
| Incomplete multi-doc update | 2 (E3, E7) | ~400 | Update all references atomically |
| **Total** | **10** | **~5000** | |

### Top Root Causes

1. **Trusting docs over code** (E3, E5, E6): Problem records and plans become stale. Always
   verify claims against actual code with grep before acting.

2. **Not verifying edits took hold** (E1): Linter hooks can silently revert changes. Always
   verify with grep after editing Rust files.

3. **Sequential document updates** (E3, E6, E7): Updating docs at different points in a
   session creates temporal inconsistencies. Batch all doc updates into one commit after
   implementation is complete.

### Recommended Rule Additions

```
## Pre-implementation verification (MANDATORY)
- Before launching an implementation agent, verify the bug still exists: `grep` the code
- Before writing tests, read the mock/test API you'll use
- After editing Rust files, verify the edit with grep before proceeding
```

### Recommended Hook Candidates

1. **Post-edit verify hook**: After Edit tool on `.rs` files, automatically grep for the
   new_string to confirm the edit took hold. Alert if not found.

2. **Problem record done → move hook**: When a problem record's status changes to `done`,
   warn if it's not in the `done/` directory.
