---
apply: always
---

## Session Hygiene (MANDATORY)

### Session Start
- Run `just session-init` at the beginning of every session
- Review the dashboard: open MRs, local branches, uncommitted changes
- If continuing work from a previous session, use `just git resume <branch>`
- Never start new work if there's existing in-flight work on the same topic

### Session End
- Run `just session-end` before ending every session
- All work must be either: committed + pushed, or explicitly abandoned
- Never leave uncommitted changes across sessions
- If work is incomplete, save with `just git wip` and push
- **Update documentation** before declaring housekeeping complete:
  - Problem records: update status, last_updated, add notes for work done (`_private/docs/problems/`)
  - Plans: check off completed items, update percentages (`_private/docs/planning/todo/`)
  - Work context: clear or update `.claude/.workcontext`
  - Clean up stale memories in `.claude/projects/*/memory/`

### Cross-Machine Sync (CRITICAL)
- **Always push before switching machines or ending a session**
- Use Draft MRs for work-in-progress that may be continued elsewhere
- MRs are the handoff mechanism between machines — not local branches
- After pushing, verify with `just git status` that nothing is left behind

### Periodic Health
- Run `just git branch-health` to audit all branches across repos
- Run `just git branch-health cleanup` to delete merged/in-main branches

Branch naming, WIP commits, and commit conventions: see `.claude/rules/multi-repo-awareness.md`
