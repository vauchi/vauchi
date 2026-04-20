<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

## Tool Usage: Always Use Just Recipes (MANDATORY)

**Run all commands from the workspace root** (the `vauchi` directory
containing the justfile). Just recipes handle correct working directories,
toolchain detection, and multi-repo orchestration.

### Build, Test, Lint

| Instead of... | Use... |
|---------------|--------|
| `cargo build` | `just build [repo]` |
| `cargo test` / `cargo nextest` | `just test [repo]` |
| `cargo fmt` | `just fmt [repo]` |
| `cargo clippy` | `just lint [repo]` |
| `cargo fmt && cargo clippy && cargo test` | `just check [repo]` |
| `cargo test -p <crate>` | `just test-crate <crate>` |
| `cargo test --test <name>` | `just test-file <name> [repo]` |
| `cargo test <pattern>` | `just test-name <pattern> [repo]` |

### Searching (PREFER just recipes over built-in Grep/Glob tools)

Use `just grep` and `just concept` via Bash instead of the built-in Grep and Glob tools.
Reduces tokens, avoids permission prompts, searches all repos at once.

| Instead of... | Use... |
|---------------|--------|
| Grep tool (content search) | `just grep <pattern> [glob]` |
| Glob tool (file search) | `just grep` with a filename pattern, or `ls`/`find` via just |
| Searching by domain concept | `just concept <name>` |
| Finding API consumers (CC-05) | `just consumers <pattern>` |
| `grep -P` (Perl regex) | `just grep <pattern>` (uses ripgrep, supports full regex) |
| Multiple Grep calls | Single `just grep <pattern>` (searches all repos at once) |

**When to use built-in Grep/Glob instead:** Only for a single known file or
very narrow path. For cross-repo or broad searches, always use just recipes.

### GitLab & Git

| Instead of... | Use... |
|---------------|--------|
| `glab mr list` / `glab mr create` | `just gitlab mr-list [repo]` / `just gitlab mr-create [repo]` |
| `glab ci status` | `just gitlab pipeline-status [repo]` |
| Raw `git -C <repo>` for multi-repo | `just git status` / `just git main` |
| `git diff origin/main...HEAD` | `just git diff-main [repo]` |
| `git log origin/main..HEAD` | `just git log-branch [repo]` |
| `glab mr approve` / `glab mr merge` | `just gitlab mr-approve <id> [repo]` / `just gitlab mr-merge <id> [repo]` |
| `git stash` (DON'T USE) | `just git wip [msg] [repos]` (WIP commits, safer) |
| `git stash pop` (DON'T USE) | `just git wip-undo [repos]` |
| Switch branch mid-work | `just git wip` then `just git branch <name>` |
| Return to branch + restore | `just git resume <branch> [repos]` |
| Parallel branch work | `just worktree create <branch> [repos]` |
| Health check / housekeeping | `just housekeeping` |

### Repo argument rules

- **Omit** → auto-detect from pwd (inside sub-repo) or run all (from
  workspace root)
- **Explicit name** → `just test core`, `just lint relay`, `just check ios`
- **`all`** → `just test all` runs across all applicable repos

**Valid repo names:** `root`, `core`, `cli`, `relay`, `ohttp-relay`, `tui`, `e2e`, `android`, `ios`, `macos`, `windows`, `linux-gtk`, `linux-qt`, `web-demo`, `docs`, `locales`, `themes`, `features`, `website`, `scripts`, `_private`, `drift-detector`, `markdown-plan`

## Daily Recipes (covers ~90% of sessions)

```bash
# Build / test / lint
just check [repo]               # fmt-check + lint + test (alias: c)
just build [repo]               # Build (alias: b)
just test [repo]                # Tests (alias: t)
just fmt [repo]                 # Format
just lint [repo]                # Clippy/lint
just fix [repo]                 # Auto-fix lint
just test-crate <crate>         # Test specific workspace crate
just test-file <name> [repo]    # Single test file (default: core)
just test-name <pattern> [repo] # Tests matching pattern (default: core)
just coverage [repo]            # Tests with coverage
just audit [repo]               # Security audit (Rust)
just commit                     # Interactive commit across repos
just commit-repo <repo> <msg>   # Single-repo commit
just housekeeping               # Non-destructive health checks
just exec-in-repo <repo> <cmd>  # Run a raw command inside a sub-repo

# Git (multi-repo)
just git status                 # Status across all repos
just git sync                   # Fetch all + pull where on main
just git fetch                  # Fetch all repos
just git push-all [mode]        # Push repos with commits ahead
just git main [mode]            # Save → checkout main → pull
just git branches               # Branches across repos
just git branch <name> [repos]  # Create branch across repos
just git branch-status          # Ahead/behind/merged
just git branch-health [mode]   # Audit (mode: audit|cleanup)
just git branch-inspect <name>  # Inspect branch across all repos
just git stale-branches [days]  # Branches with no recent activity
just git diff-main [repo]       # Diff vs main
just git log-branch [repo]      # Commits not on main
just git rebase-main [repo]     # Rebase on origin/main
just git wip [msg] [repos]      # WIP checkpoint commits
just git wip-undo [repos]       # Undo WIP (soft reset)
just git resume <branch> [repos] # Switch branch + auto-undo WIP
just git cleanup [mode]         # Merged-branch cleanup (dry-run|run)

# Worktrees
just worktree create <branch> [repos]
just worktree list
just worktree remove-force <branch>

# GitLab MRs / pipelines
just gitlab mr-list [repo]
just gitlab mr-view <id> [repo]
just gitlab mr-create [repo] [title]    # Auto-links sibling MRs
just gitlab mr-create-all [title]
just gitlab mr-approve <id> [repo]
just gitlab mr-merge <id> [repo]
just gitlab mr-status [repo]
just gitlab pipeline-status [repo]
just gitlab pipeline-list [repo]
just gitlab pipeline-jobs <id> [repo]
just gitlab pipeline-log <id> [repo]
just gitlab pipeline-wait [repo]        # Poll until finish (30s)
just gitlab pipeline-retry <id> [repo]
just gitlab pipeline-cancel <id> [repo]

# Release (3-tier promotion)
just release-dev [repo] [version]
just release-rc [repo] [version]
just release-prod [repo]
just release-history [repo] [version]
just release-chain-status [version]

# Apps
just run [platform] [args]      # cli|tui|linux-gtk|linux-qt|android|ios|relay
just relay
just tui

# Cross-repo discovery / quality
just grep <pattern> [glob]      # ripgrep across all repos
just concept <name>             # Search by drift concept + aliases
just consumers <pattern>        # Find downstream of core API (CC-05)
just check-refs                 # Cargo.toml branch refs point to main
just check-lockfile-consistency # Version skew across repos
just spellcheck
just reuse [repo]               # SPDX/REUSE check
just lint-docs
just lint-file-size [repo]
just churn [repo]               # File churn + size correlation
just drift [severity]           # Drift audit (default: high)
just doc-refs <pattern>
just tell-me-about <topic>      # Local-LLM codebase Q&A
```

## Specialized Recipes (read on demand)

The following categories live in `.claude/docs/just-commands-reference.md` —
**Read it only when working in the matching area**:

- **Device Testing** (mobile + macOS): `dt-*`, `prepare-device-test`, `rebuild-ios/android`
- **E2E Testing**: `e2e-*` (CLI/TUI/Desktop/Mobile/Maestro/relay/website variants)
- **Deployment**: `deploy*`, `mail-*`, `monitoring-*`, `validate`, `backup`
- **Mobile / Bindings**: `build-android`, `build-ios`, `bindings*`, `check-mobile`
- **Performance profiling**: `perf-*`, `sccache`
- **Planning / Problems**: `plan-*`, `problem-list`, `problems-tidy`, `risk`, `task-list`
- **Dev / Local Testing**: `dev-relay*`, `dev-cli`, `dev-tui`, `e2e-checklist`, `schema-check`
- **CI Runners** (local): `runners-*`
- **Setup / Maintenance**: `setup`, `session-init`, `session-end`, `install-*`, `clean*`, `git-compact`

For unknown commands: `just help` (interactive) or `just --list` (full).
