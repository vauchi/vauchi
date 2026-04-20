## Self-Healing (MANDATORY)

Leave the codebase healthier than you found it. Heal what you encounter,
not what you imagine — fix things in your path (files you read, commands
you run, docs you consult).

### Three Tiers

| Tier | When | Commit |
|---|---|---|
| **Inline** | Problem is in a file you're already editing | Current commit or own `tidy:` |
| **Tidy** | Problem is in a file you read, not your edit target | Separate `tidy:` commit |
| **Flag** | Systemic, cross-cutting, or needs design decisions | Problem record, no code |

### What to Heal

- **Stale problem records**: status vs code reality → update status,
  `git mv` to `done/` if resolved
- **Stale plan items**: `[x]` but code missing, or `[ ]` but code merged → fix checkbox
- **Outdated references**: path changed, command renamed → fix in place
- **Pre-existing lint/format issues in files you touch** → `tidy:` commit
  before your change
- **Inconsistent docs**: reconcile to source of truth
- **Workflow artifacts**: stale `.workcontext`, orphan branches → clean up

### Boundaries

- Don't scan for problems — only heal what you encounter on your path
- Security issues → flag as problem records, don't inline-fix
- Uncertain fixes → flag (Tier 3), don't guess
- Other people's WIP → leave alone

**Truth hierarchy**: code → git log → CI → plan → problem record → doc

Full rationale and examples: `.claude/docs/self-healing.md`
