## Multi-Repo Awareness & Git Conventions

- This is a **multi-repo project** — each subdirectory is its own git repo
- **Commit format**: `{type}: {Short description}` — types: `feat`, `fix`,
  `refactor`, `tidy`, `docs`, `test`, `chore`
- **Co-author**: Always add `Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>`
- **Atomic commits**: One logical change per commit. TDD order: `tidy:`
  (optional) → `test:` → `feat:`/`fix:`
- **Branches**: `feature/`, `bugfix/`, `refactor/`, `tidy/`, `investigation/`
- **Pre-MR rebase**: Always `git fetch origin main && git rebase origin/main` before creating an MR
- **No direct push to main**: Merge via MR only. Sync branch names across repos.
- **No `@` in MR descriptions** (enforced by `.claude/hooks/check-mr-mentions.sh`):
  bare `@word` becomes a GitLab/GitHub user mention and emails the wrong person.
  Wrap every Gherkin tag, ADR ref, or `@`-marker in backticks
  (`` `@duress` ``, `` `@implemented` ``). Hook blocks `glab mr create/update`,
  `gh pr create/edit`, and `just gitlab mr-(create|update)` if any unescaped
  `@tag` is found in the description body. Emails (`foo@bar.tld`) are
  allowlisted.
- **NEVER `cd` into sub-repo directories** — use `git -C <dir>` for git
  commands and `just <recipe> [repo]` for everything else. `cd` drifts the
  working directory and causes wrong-repo commits/pushes.
- **Stay at workspace root** — the directory containing `CLAUDE.md`. All
  `just` recipes work from here.
- **Use `just git *` recipes for all multi-repo git operations** — never
  write raw bash loops over repos
  - Key recipes: `status`, `branch <name>`, `branch-inspect <name>`,
    `push-all`, `wip [msg]`, `wip-undo`, `resume <branch>`, `fetch`,
    `sync`, `cleanup`, `branch-health`
  - Non-interactive: `just git main wip` (not bare `just git main` which prompts)
- **Use `just worktree *` for parallel development** — `create <branch>`, `list`, `remove-force <branch>`
- **Use `just gitlab *` for all GitLab operations** — never use raw `glab` commands
  - Key recipes: `mr-create [repo]`, `mr-list [repo]`,
    `pipeline-status [repo]`, `pipeline-retry <id> [repo]`
- **Prefer WIP commits over stashing** — `just git wip` saves on the branch, `just git wip-undo` restores
- Keep `Cargo.toml` git dependency branch refs pointing to `main`
- Push upstream repos first (core → cli/tui/e2e and other downstream),
  mark downstream MRs as Draft
- iOS/Android binding repos are auto-generated — never edit manually
- **Branch inspection: ALWAYS check all repos** — same branch name spans
  many repos; one may be empty while another has real work. Use
  `just git branch-inspect <name>` before any action (status, delete,
  etc.); `just git branch-health` for broader audits. Acting on a single
  repo's view risks destroying work elsewhere.

Full recipe reference: `.claude/docs/just-commands.md`
MR template, multi-repo examples: `.claude/docs/commit-conventions.md`
