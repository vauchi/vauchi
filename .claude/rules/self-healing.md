---
apply: always
---

## Self-Healing (MANDATORY)

Leave the codebase healthier than you found it. When your work path crosses something broken, fix it — don't work around it, don't just log it.

### Disposition

Fixing stale state is not "going beyond what was asked" — it's maintenance. A stale doc reference, an outdated status field, a broken example: these are not someone else's problem. If you read it, you own it for the duration of your path through it. The cost of a small fix now is always less than the cost of rediscovering the same problem later.

### Scope: Three Tiers

| Tier | When | How | Commit |
|---|---|---|---|
| **Inline** | Problem is in a file you're already editing | Fix it in place | Part of current commit if trivially small, otherwise own `tidy:` commit |
| **Tidy** | Problem is in a file you read or a command you ran, not your edit target | Fix with a separate `tidy:` commit | Before or after your feature commit, never mixed |
| **Flag** | Problem is systemic, cross-cutting, or requires design decisions | Create or update a problem record | No code commit — document only |

**Scope boundary**: Heal what you encounter, not what you imagine. Don't go hunting for problems — heal things in your path (files you read, commands you run, docs you consult, status you verify).

### What to Heal

- **Stale problem records**: Status doesn't match code reality → update status, `git mv` to `done/` if resolved, update plan refs
- **Stale plan items**: `[x]` but code missing from main, or `[ ]` but code merged → update the checkbox, adjust percentage
- **Outdated references**: Path changed, command renamed, example broken → fix the reference in place
- **Pre-existing issues in files you touch**: Lint warnings, format violations, dead imports → `tidy:` commit before your change
- **Inconsistent state across docs**: Same fact stated differently in two places → reconcile to the source of truth (code > plan > problem record > doc)
- **Workflow artifacts**: Stale `.workcontext`, orphan branches encountered during branch inspection → clean up
- **Recipe/tool failures with known fixes**: If you diagnose a recipe failure and the fix is small and correct, apply it

### What NOT to Heal

- **Outside your path**: Don't scan the codebase for problems to fix
- **Architectural decisions**: Changes needing ADRs are design work, not healing
- **Security issues**: Flag as problem records with containment — don't inline-fix
- **Uncertain fixes**: If you can't verify the fix is correct, flag (Tier 3) instead of guessing
- **Other people's in-progress work**: Branches, draft MRs, WIP commits — leave them alone

### The Verify-Heal Loop

Detection and correction are two halves of one act:

1. **Verify** (per `verify-before-acting.md`): Before acting on any artifact, check it matches reality
2. **Heal**: If it doesn't match, fix the stale artifact at the appropriate tier
3. **Continue**: Proceed with your original task using the corrected state

Healing is not extra work — it's the completion of verification. An unhealed verification is a problem deferred.

### Truth Hierarchy

When sources conflict, trust in this order: **code → git log → CI → plan → problem record → doc**. Heal the lower-trust source to match the higher one.
