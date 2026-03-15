<!--
SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
SPDX-License-Identifier: GPL-3.0-or-later
-->
---
name: group-label-naming-split
description: GroupManager/Group are the struct names; LabelError is the error type; method names are split — some say "group" (create_group, delete_group), others say "label" (all_labels, label_count, labels_for_contact, insert_loaded_label). This inconsistency is a recurring review finding.
type: feedback
---

The rename from VisibilityLabel/LabelManager to Group/GroupManager was partial. The struct names and public API
changed (`Group`, `GroupManager`, `create_group`, `delete_group`, `merge_groups`) but several method and field
names still use the old "label" vocabulary:

- `LabelError` — error type kept the old name
- `all_labels()`, `label_count()`, `labels_for_contact()`, `unlabeled_contacts()`, `insert_loaded_label()`
- `GroupManager.labels: HashMap<String, Group>` — private field kept old name

**Why:** The rename was done incrementally; error type and helper method names were missed.

**How to apply:** Flag any `label`-named public items in `GroupManager` / `Group` as inconsistencies whenever
reviewing `contact/labels.rs` or any caller of these APIs. `LabelError` is the highest-priority because it is
re-exported in `lib.rs` and forms part of the public API contract.
