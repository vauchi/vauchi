---
apply: always
---

## Multi-Repo Awareness

- This is a **multi-repo project** — each subdirectory is its own git repo
- **Use `just git *` recipes for all multi-repo git operations** — never write raw bash loops over repos
  - `just git status` — status across all repos
  - `just git branch-status` — branches with ahead/behind info
  - `just git stash-list` — stashes across repos
  - `just git stash-clear` — drop all stashes
  - `just git cleanup` / `just git cleanup run` — prune merged branches
  - `just git fetch` / `just git sync` — fetch/pull all repos
  - `just git branches` — list branches across repos
  - `just git branch <name> [repos]` — create branch across repos
  - `just git push-all` — push repos with commits ahead
- Fall back to `git -C <dir>` only for single-repo ops not covered by a recipe
- Keep `Cargo.toml` git dependency branch refs pointing to `main`
- Push upstream repos first (core → cli/tui/desktop/e2e), mark downstream MRs as Draft
- iOS/Android binding repos are auto-generated — never edit manually
