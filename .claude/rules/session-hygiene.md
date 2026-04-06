---
apply: always
---

## Session Hygiene (MANDATORY)

### Session Start

- Run `just session-init` at the beginning of every session
- Review the dashboard: open MRs, local branches, uncommitted changes
- **Read the work board output** — it shows BLOCKED, NEXT, and IN PROGRESS items
  - If another session has claimed work (IN PROGRESS), don't duplicate it
  - Pick from NEXT items in priority order (top = highest)
- If continuing work from a previous session, use `just git resume <branch>`
- Never start new work if there's existing in-flight work on the same topic
- **Claim work** on the board before starting: edit `_private/docs/work-board.md`,
  move the item from `## v0.5.0 Next` to `## In Progress` with your session identifier

### Session End

- Run `just session-end` before ending every session
- All work must be either: committed + pushed, or explicitly abandoned
- Never leave uncommitted changes across sessions
- If work is incomplete, save with `just git wip` and push
- **Release board claims**: move completed items to `## v0.5.0 Done`
  (or back to Next if incomplete) in `_private/docs/work-board.md`.
  Commit the board update.
- **Review staleness warnings** from `session-end` output — if docs reference
  repos you changed, verify they're still accurate
- **Update documentation** before declaring housekeeping complete:
  - Work board: release claims, move done items (`_private/docs/work-board.md`)
  - Problem records: update status, last_updated, add notes (`_private/docs/problems/`)
  - Plans: check off completed items, update percentages (`_private/docs/planning/todo/`)
  - Work context: clear or update `.claude/.workcontext`
  - Review auto-memory for stale entries (`~/.claude/projects/*/memory/`)

### Cross-Machine Sync (CRITICAL)

- **Always push before switching machines or ending a session**
- Use Draft MRs for work-in-progress that may be continued elsewhere
- MRs are the handoff mechanism between machines — not local branches
- After pushing, verify with `just git status` that nothing is left behind

### Periodic Health

- Run `just git branch-health` to audit all branches across repos
- Run `just git branch-health cleanup` to delete merged/in-main branches

Branch naming, WIP commits, and commit conventions: see `.claude/rules/multi-repo-awareness.md`
