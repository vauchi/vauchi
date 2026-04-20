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
  move the item from a `## ... — Next` section to `## In Progress` with your session identifier

### Session End

- Run `just session-end` — all work must be committed + pushed, or `just git wip`-saved
- **Review staleness warnings** from session-end output
- **Update documentation** before declaring done:
  - Work board (`_private/docs/work-board.md`): release claims, move done
    items to `## Done`, incomplete items back to a `Next` section. Commit.
  - Problem records (`_private/docs/problems/`): update status, last_updated, notes
  - Plans (`_private/docs/planning/todo/`): tick completed items, update percentages
  - Work context: clear or update `.claude/.workcontext`
  - Auto-memory: review for stale entries (`~/.claude/projects/*/memory/`)

### Cross-Machine Sync (CRITICAL)

- **Always push before switching machines or ending a session**
- Use Draft MRs for work-in-progress that may be continued elsewhere
- MRs are the handoff mechanism between machines — not local branches
- After pushing, verify with `just git status` that nothing is left behind

### Periodic Health

- Run `just git branch-health` to audit all branches across repos
- Run `just git branch-health cleanup` to delete merged/in-main branches

Branch naming, WIP commits, and commit conventions: see `.claude/rules/multi-repo-awareness.md`
