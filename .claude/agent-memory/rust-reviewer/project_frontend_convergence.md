<!--
SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
SPDX-License-Identifier: GPL-3.0-or-later
-->

---
name: frontend-convergence-phase2
description: Phase 2 of frontend convergence adds 3 Component variants and 2 action type variants; schemas and contract tests must stay in sync
type: project
---

Phase 2 of the frontend convergence work (design doc: `_private/docs/plans/2026-03-12-frontend-convergence-design.md`) adds:
- `Component::ShowToast`, `Component::InlineConfirm`, `Component::EditableText`
- `ActionResult::ShowToast { message, undo_action_id }`
- `UserAction::UndoPressed { action_id }`

**Why:** Design specifies these as the first three new component types needed to drive guideline fixes across all 6 platforms. No backwards compatibility requirement — all platforms update in lockstep.

**How to apply:** When reviewing further changes in this area, check that:
1. JSON schemas in `schemas/` are updated for new variants
2. `tests/contract_tests.rs` exercises every new variant against the schema
3. `tests/onboarding_engine_proptest.rs` and `tests/phase3_engine_proptest.rs` `validate_result` helper covers new ActionResult arms
