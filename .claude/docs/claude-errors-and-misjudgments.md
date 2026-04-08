<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Claude Errors & Misjudgments Log

Track recurring mistakes to identify patterns. Each entry:
what happened → root cause → prevention → **test guard**.

**Numbering**: Global sequential (E31, E32, ...). Check last
E## before adding.

**Format per entry:**

- **What**: Observable symptom
- **Root cause**: Why it happened
- **Prevention**: Rule or behavioral change
- **Test guard**: Test file:function that prevents recurrence
  (or `none — manual discipline` if not automatable)

**Archive**: Entries E1-E30 archived to `archive/claude-errors-2026-03.md`
after verifying all preventions are encoded in rules, hooks, or code.

**Known bias**: Claude optimizes for task completion over process
compliance under friction. This drove 15 of the first 30 errors.
Counter: `verify-before-acting.md`, CC-21 Chesterton's Fence.

---

## Remaining Gaps (from E1-E30 analysis)

1. **MEDIUM**: `just gitlab mr-create` doesn't auto-populate Related MRs
   from branch inspection (caused E13→E14→E15 cascade)
2. **LOW**: Pre-push hook doesn't handle platform-limited repos
   (linux-gtk on macOS) — E16

---

*New entries below this line.*
