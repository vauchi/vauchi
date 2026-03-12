<!--
SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
SPDX-License-Identifier: GPL-3.0-or-later
-->

---
name: proptest-match-exhaustiveness
description: proptest files contain explicit match arms on ActionResult; the validate_result helper in phase3_engine_proptest.rs is the key exhaustiveness checkpoint for new variants
type: project
---

Two proptest files match on `ActionResult` exhaustively:

1. `tests/onboarding_engine_proptest.rs` — `random_actions_never_panic` contains a direct `match &result` block at line ~464.
2. `tests/phase3_engine_proptest.rs` — `validate_result` helper function at line ~135 is shared across all 5 Phase 3 engine tests.

Both use `|` arm grouping for "pass-through" variants. New ActionResult variants must be added to both match sites or the code will fail to compile (exhaustiveness check).

**Why:** These are the primary "engine never panics" invariant tests — they must cover every valid ActionResult the engine can produce.

**How to apply:** On every PR adding an ActionResult variant, grep `tests/onboarding_engine_proptest.rs` and `tests/phase3_engine_proptest.rs` for the existing variant names to confirm the new one was added. The branch commit fixes were correct for ShowToast but this pattern should be checked each time.
