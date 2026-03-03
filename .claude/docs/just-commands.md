<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

---
apply: always
---

## Tool Usage: Always Use Just Recipes (MANDATORY)

**Run all commands from the workspace root** (the `vauchi` directory containing the justfile).
Just recipes handle correct working directories, toolchain detection, and multi-repo orchestration.

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
This reduces token usage, avoids permission prompts, and searches across all repos in one call.

| Instead of... | Use... |
|---------------|--------|
| Grep tool (content search) | `just grep <pattern> [glob]` |
| Glob tool (file search) | `just grep` with a filename pattern, or `ls`/`find` via just |
| Searching by domain concept | `just concept <name>` |
| Finding API consumers (CC-05) | `just consumers <pattern>` |
| `grep -P` (Perl regex) | `just grep <pattern>` (uses ripgrep, supports full regex) |
| Multiple Grep calls | Single `just grep <pattern>` (searches all repos at once) |

**When to use built-in Grep/Glob instead:** Only when searching within a single known file or a very narrow path (e.g., reading a specific function). For cross-repo or broad searches, always use just recipes.

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
| `git stash list` across repos | `just git stash-list` |
| `git stash clear` across repos | `just git stash-clear` |
| Health check / housekeeping | `just housekeeping` |

### Repo argument rules

- **Omit** → auto-detect from pwd (inside sub-repo) or run all (from workspace root)
- **Explicit name** → `just test core`, `just lint relay`, `just check desktop`
- **`all`** → `just test all` runs across all applicable repos
- **`desktop`** → expands to both `desktop-rust` and `desktop-ui`

**Valid repo names:** `root`, `core`, `cli`, `relay`, `tui`, `e2e`, `desktop` (or `desktop-rust`/`desktop-ui`), `android`, `ios`, `docs`, `locales`, `themes`, `features`, `website`, `scripts`, `_private`

### Full Command Reference

```bash
# Daily workflow
just check [repo]           # Format-check + lint + test
just build [repo]           # Build
just test [repo]            # Run tests
just fmt [repo]             # Format code
just lint [repo]            # Run lints
just fix [repo]             # Auto-fix formatting + lint
just commit                 # Interactive commit across repos
just commit-repo <repo> <msg> # Non-interactive commit (for automation)
just housekeeping            # Run all health checks (changes, snapshots, stashes, branches, drift)

# Repo targeting
just test core              # Test core only
just lint desktop           # Lint desktop (Rust + frontend)
just check                  # Check all (from workspace root)

# Extended
just test-crate <crate>     # Test specific crate in core workspace
just test-file <name> [repo] # Run single test file
just test-name <pattern> [repo] # Run tests matching name pattern
just audit [repo]           # Security audit (Rust repos)
just coverage               # Coverage report (core)
just watch                  # Watch + test (core)
just build-release          # Release build (core)

# Drift detection
just drift                  # Audit drift (human-readable, fail on high)
just drift medium           # Audit drift (fail on medium+)
just drift-ci               # Audit drift (JSON output for CI)
just drift-ci medium        # Audit drift CI (fail on medium+)

# Task tracking (markdown-plan)
just plan-validate [file|dir]  # Validate .plan.md files
just plan-list [dir]           # List plans with task counts
just plan-history <file>       # Task history as JSON
just plan-plot <file>          # Burn-up chart in browser
just plan-stale [days]         # Show stale plans (default: 30 days)

# GitLab
just gitlab mr-list [repo]          # List open MRs
just gitlab mr-view <id> [repo]     # View MR details
just gitlab mr-create [repo] [title] # Create MR from current branch
just gitlab mr-approve <id> [repo]  # Approve MR
just gitlab mr-merge <id> [repo]    # Merge MR
just gitlab mr-status [repo]        # MR status for current branch
just gitlab pipeline-status [repo]  # Pipeline status
just gitlab pipeline-list [repo]    # Recent pipelines
just gitlab pipeline-log <id> [repo] # Job log
just gitlab pipeline-jobs <id> [repo] # List jobs in a pipeline
just gitlab pipeline-wait [repo]    # Wait for pipeline to finish
just gitlab pipeline-cancel <id> [repo] # Cancel running pipeline
just gitlab pipeline-retry <id> [repo] # Retry failed pipeline
just gitlab issue-list [repo]       # List issues
just gitlab issue-view <id> [repo]  # View issue details
just gitlab issue-create <title> [repo] # Create issue
just gitlab issue-close <id> [repo] # Close issue

# Git (multi-repo)
just git sync               # Fetch all + pull where on main
just git main yes           # Checkout main + pull (non-interactive)
just git status             # Status across all repos
just git branch-status      # Branch state: ahead/behind/merged
just git diff-main [repo]   # Diff current branch vs main
just git log-branch [repo]  # Commits on branch not on main
just git rebase-main [repo] # Rebase branch on origin/main
just git main               # Save → checkout main → pull (prompts: wip/stash/abort)
just git main wip           # WIP-commit → checkout main → pull (non-interactive)
just git wip [msg] [repos]  # Save WIP checkpoint commits (safer than stash)
just git wip-undo [repos]   # Undo WIP commits (soft reset, keeps changes)
just git resume <branch> [repos] # Switch to branch + auto-undo WIP commits
just git stale-branches [days] # Find branches with no recent activity (default: 14d)
just git pull-all           # Pull latest in all repos
just git push-all           # Push repos with commits ahead
just git push-all skip-tests # Push without running tests
just git fetch              # Fetch all repos
just git branches           # Show branches across repos
just git branch <name> [repos] # Create branch across repos (safety gate for dirty repos)
just git stash-list         # Show stashes across all repos
just git stash-clear        # Clear all stashes across all repos
just git cleanup            # Preview merged branch cleanup
just git cleanup run        # Delete merged branches + prune refs
just git checkout-main      # Checkout main in all repos

# Worktrees (parallel development)
just worktree create <branch> [repos] # Create parallel checkout in .worktrees/
just worktree list          # List all active worktrees
just worktree remove <branch> # Remove worktree (interactive, warns about dirty)
just worktree remove-force <branch> # Remove worktree (non-interactive, for Claude)

# Cross-repo tools
just grep <pattern> [glob]  # Search across all repos
just concept <name>         # Search by drift concept + aliases
just check-refs             # Verify Cargo.toml branch refs → main
just check-annotations [repo] # Check @scenario annotation coverage
just check-lifecycle        # Validate feature lifecycle tags
just consumers <pattern>    # Find downstream usage of core API
just reuse [repo]           # REUSE / SPDX license header check
just lint-docs              # Lint docs: naming, broken links, license text
just sync-locales           # Validate locale files (missing/extra keys)
just problem-list [phase]   # List problem records by status
just task-list              # Show remaining tasks from master plan

# Setup
just setup                  # Clone all repos, init workspace
just install-dev-deps       # Install toolchain
just clean                  # Clean all build artifacts
just help                   # Show all commands
```
