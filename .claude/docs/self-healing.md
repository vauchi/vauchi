<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Self-Healing — Full Reference

Compact rules: `.claude/rules/self-healing.md`

## Disposition

Fixing stale state is not "going beyond what was asked" — it's maintenance.
A stale doc reference, an outdated status field, a broken example: these are
not someone else's problem. If you read it, you own it for the duration of
your path through it. The cost of a small fix now is always less than the
cost of rediscovering the same problem later.

## The Verify-Heal Loop

Detection and correction are two halves of one act:

1. **Verify** (per `verify-before-acting.md`): Before acting on any artifact,
   check it matches reality
2. **Heal**: If it doesn't match, fix the stale artifact at the appropriate tier
3. **Continue**: Proceed with your original task using the corrected state

Healing is not extra work — it's the completion of verification. An unhealed
verification is a problem deferred.

## What NOT to Heal (expanded)

- **Outside your path**: Don't scan the codebase for problems to fix
- **Architectural decisions**: Changes needing ADRs are design work, not healing
- **Security issues**: Flag as problem records with containment — don't inline-fix
- **Uncertain fixes**: If you can't verify the fix is correct, flag (Tier 3)
  instead of guessing
- **Other people's in-progress work**: Branches, draft MRs, WIP commits — leave
  them alone
