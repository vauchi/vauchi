<!--
SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Rust Reviewer Agent Memory

## Project Memories

- [frontend-convergence-phase2](project_frontend_convergence.md) — Phase 2 adds 3 Component variants + ActionResult::ShowToast + UserAction::UndoPressed; schemas and contract tests must stay in sync

## Recurring Patterns

- [schemas-and-contract-tests](pattern_schemas_contract_tests.md) — JSON schemas in `schemas/` and contract tests in `tests/contract_tests.rs` must be updated whenever ActionResult or UserAction variants are added
- [proptest-match-exhaustiveness](pattern_proptest_exhaustive_match.md) — proptest files use explicit `match` arms on ActionResult; the validate_result helper is the key location to check on every new variant
- [group-label-naming-split](pattern_group_label_naming.md) — GroupManager/Group structs renamed but LabelError + several methods (all_labels, label_count, labels_for_contact, insert_loaded_label) still use the old "label" vocabulary; flag on every review of contact/labels.rs
