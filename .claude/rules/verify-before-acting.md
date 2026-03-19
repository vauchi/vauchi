---
apply: always
---

## Verify Before Acting (MANDATORY)

Code is the source of truth. Plans, problem records, and search results become stale.

- **Before implementing a fix from a problem record**: `grep` the actual source to verify the bug still exists. If it's already fixed, update the problem record instead of implementing.
- **Before claiming something is missing**: A "not found" search is not proof of absence. Use `Glob` for file existence, check CI configs, verify with a second search method.
- **Before launching background agents**: One verification grep is cheaper than a wasted agent. Trust code over docs.
- **After parallel agents complete on the same repo**: Re-read any files you plan to edit — another process may have triggered `rustfmt` on the workspace.
- **When a recipe fails**: Debug the recipe. Don't bypass it with raw commands — the recipe has safety checks and conventions that raw commands skip. One bypassed recipe caused a 3-error cascade (E11→E12→E13).
