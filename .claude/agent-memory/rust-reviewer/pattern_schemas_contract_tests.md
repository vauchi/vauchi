<!--
SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
SPDX-License-Identifier: GPL-3.0-or-later
-->

---
name: schemas-and-contract-tests
description: JSON schemas and contract tests must be updated together whenever ActionResult or UserAction variants are added — they are the cross-boundary contract with iOS/Android frontends
type: project
---

This codebase maintains three JSON schemas in `core/vauchi-core/schemas/`:
- `screen-model.schema.json` — includes the full Component definition
- `action-result.schema.json` — ActionResult variants + Component definition
- `user-action.schema.json` — UserAction variants

These schemas are the serialisation contract between vauchi-core and all frontends (iOS, Android, TUI, macOS, Linux-GTK, Linux-Qt).

`tests/contract_tests.rs` validates every ActionResult and UserAction variant against these schemas at test time.

**Why:** Frontends deserialize these types. A missing schema entry means a new variant passes Rust tests but breaks frontend deserialization silently.

**How to apply:** Any PR adding a new ActionResult or UserAction variant must also update the relevant schema file AND add the variant to the `actions`/`results` vec in `contract_tests.rs`. Flag as Critical if either is missing.
