---
apply: always
---

## Verify Before Acting (MANDATORY)

Problem records and plans become stale. Code is the source of truth.

- **Before implementing a fix from a problem record**: `grep` the actual source to verify the bug still exists. If it's already fixed, update the problem record instead of implementing.
- **Before launching background agents**: One verification grep is cheaper than a wasted agent. Trust code over docs.
- **After parallel agents complete on the same repo**: Re-read any files you plan to edit — another process may have triggered `rustfmt` on the workspace.
