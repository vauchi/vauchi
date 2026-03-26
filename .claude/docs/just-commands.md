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
- **Explicit name** → `just test core`, `just lint relay`, `just check ios`
- **`all`** → `just test all` runs across all applicable repos

**Valid repo names:** `root`, `core`, `cli`, `relay`, `ohttp-relay`, `tui`, `e2e`, `android`, `ios`, `macos`, `windows`, `linux-gtk`, `linux-qt`, `web-demo`, `docs`, `locales`, `themes`, `features`, `website`, `scripts`, `_private`, `drift-detector`, `markdown-plan`

### Full Command Reference

#### Daily Commands

```bash
just check [repo]               # Format-check + lint + test (alias: c)
just build [repo]               # Build workspace or specific repo (alias: b)
just test [repo]                # Run tests (alias: t)
just fmt [repo]                 # Format code (alias: f)
just fmt-check [repo]           # Check formatting without changes
just lint [repo]                # Run lints
just fix [repo]                 # Auto-fix lint issues
just commit                     # Interactive commit across repos with changes
just commit-repo <repo> <msg>   # Non-interactive commit for a single repo
just housekeeping               # Run all non-destructive health checks and print summary
just tmp-clean                  # Clean orphaned vauchi test temp dirs (skips Claude session data)
just sweep [days]               # Remove stale cargo artifacts older than N days (default: 30)
```

#### Extended Commands

```bash
just test-crate <crate>           # Test specific crate in core workspace
just test-file <name> [repo]      # Run single test file (default repo: core)
just test-name <pattern> [repo]   # Run tests matching name pattern (default repo: core)
just build-release                # Build release binaries
just audit [repo]                 # Security audit (Rust repos)
just coverage [repo]              # Run tests with coverage
just bench [repo]                 # Run Criterion benchmarks
just watch                        # Watch for changes and run tests (core only)
just docs                         # Generate and open Rust docs
just install-hooks                # Install git hooks (pre-commit + pre-push) across all repos
just metrics [args]               # Engineering metrics dashboard
just metrics-push [args]          # Push engineering metrics to Prometheus pushgateway
just exec-in-repo <repo> <cmd>    # Run arbitrary command inside a sub-repo directory
```

#### Release

```bash
just release-dev [repo] [version]     # Create a dev release (default repo: core)
just release-rc [repo] [version]      # Create a release candidate (default repo: core)
just release-prod [repo]              # Create a production release (reads version from Cargo.toml)
just release-history [repo] [version] # Show release history
just release-chain-status [version]   # Show status of a release chain across repos
```

#### Git Operations (multi-repo)

```bash
just git status                       # Status across all repos
just git sync                         # Fetch all + pull where on main
just git fetch                        # Fetch all repos
just git pull-all                     # Pull latest in all repos
just git push-all [mode]              # Push repos with commits ahead (mode: full|skip-tests)
just git main [mode]                  # Save → checkout main → pull (mode: wip|discard or interactive)
just git checkout-main                # Checkout main in all repos
just git branches                     # Show branches across all repos
just git branch <name> [repos]        # Create branch across repos (safety gate for dirty repos)
just git branch-status                # Branch state: ahead/behind/merged
just git branch-health [mode]         # Audit all branches (mode: audit|cleanup)
just git branch-inspect <name>        # Inspect a branch across all repos (ahead/behind/age/status)
just git stale-branches [days]        # Find branches with no recent activity (default: 14 days)
just git diff-main [repo]             # Diff current branch vs main
just git log-branch [repo]            # Commits on branch not on main
just git rebase-main [repo]           # Rebase branch on origin/main
just git wip [msg] [repos]            # Save WIP checkpoint commits (safer than stash)
just git wip-undo [repos]             # Undo WIP commits (soft reset, keeps changes)
just git resume <branch> [repos]      # Switch to branch + auto-undo WIP commits
just git stash-list                   # Show stashes across all repos
just git stash-clear                  # Clear all stashes across all repos
just git cleanup [mode]               # Preview or run merged branch cleanup (mode: dry-run|run)
```

#### Worktrees (parallel development)

```bash
just worktree create <branch> [repos]  # Create parallel checkout in .worktrees/
just worktree list                     # List all active worktrees
just worktree remove <branch>          # Remove worktree (interactive, warns about dirty)
just worktree remove-force <branch>    # Remove worktree (non-interactive, for Claude)
```

#### GitLab Operations

```bash
just gitlab mr-list [repo]              # List open merge requests
just gitlab mr-view <id> [repo]         # View merge request details
just gitlab mr-create [repo] [title]    # Create MR from current branch
just gitlab mr-create-all [title]       # Create MR from current branch across all repos
just gitlab mr-approve <id> [repo]      # Approve a merge request
just gitlab mr-merge <id> [repo]        # Merge a merge request
just gitlab mr-close <id> [repo]        # Close a merge request
just gitlab mr-status [repo]            # MR status for current branch
just gitlab pipeline-status [repo]      # Pipeline status for current branch
just gitlab pipeline-list [repo]        # List recent pipelines
just gitlab pipeline-jobs <id> [repo]   # List jobs in a pipeline
just gitlab pipeline-log <id> [repo]    # View job log output
just gitlab pipeline-wait [repo]        # Poll until pipeline finishes (30s interval)
just gitlab pipeline-retry <id> [repo]  # Retry a failed pipeline
just gitlab pipeline-cancel <id> [repo] # Cancel a running pipeline
just gitlab issue-list [repo]           # List open issues
just gitlab issue-view <id> [repo]      # View issue details
just gitlab issue-create <title> [repo] # Create an issue
just gitlab issue-close <id> [repo]     # Close an issue
just gitlab published                   # Show published artifact versions
just gitlab metrics-refresh             # Trigger coverage, binary-size, design-drift, daily metrics CI jobs
just gitlab metrics-status              # Show status of metrics-related CI jobs across repos
```

#### Device Testing (mobile)

```bash
just prepare-device-test [core_dir]       # Build, package, and install both apps on physical devices
just rebuild-ios [core_dir]               # Rebuild + install iOS only (skip Android)
just rebuild-android [core_dir]           # Rebuild + install Android only (skip iOS)
just dt-verify-builds                     # Verify installed build versions on connected devices
just dt-logs-android                      # Capture Android logs (Vauchi + exchange tags)
just dt-logs-android-stream               # Clear and stream Android logs
just dt-logs-ios                          # Stream iOS device logs (pymobiledevice3 fallback)
just dt-screenshot-android [file]         # Take screenshot from Android device (default: screenshot.png)
just dt-screenshot-ios [file]             # Take screenshot from iOS device (default: screenshot.png)
just dt-relaunch-ios                      # Kill and relaunch iOS app
just dt-relaunch-android                  # Kill and relaunch Android app
just dt-deploy-ios                        # Install + relaunch iOS (build already done)
just dt-deploy-android                    # Install + relaunch Android (build already done)
just dt-wda-start                         # Start WebDriverAgent on connected iPhone
just dt-ios-tap <x> <y> [wda_url]         # Tap iOS screen at coordinates via WebDriverAgent
just dt-wda-screenshot [file] [wda_url]   # Take iOS screenshot via WebDriverAgent
```

#### Device Testing (macOS)

```bash
just dt-build-macos                       # Build and launch macOS app for manual testing
just dt-launch-macos                      # Launch macOS app (build first if needed)
just dt-relaunch-macos                    # Kill and relaunch macOS app
just dt-screenshot-macos [file]           # Capture screenshot of Vauchi window
just dt-screenshot-macos-named <name>     # Capture named screenshot into testing directory
just dt-macos-click <x> <y>              # Click at coordinates in Vauchi window
just dt-macos-type <text>                # Type text into focused field
just dt-macos-key <key>                  # Press a key (return, tab, escape, delete)
just dt-macos-return                     # Press Return key
just dt-macos-tab                        # Press Tab key
just dt-macos-escape                     # Press Escape key
just dt-macos-accessibility-tree         # Dump accessibility tree of Vauchi window
just dt-macos-find-element <label>       # Find UI element by accessibility label
just dt-macos-click-element <label>      # Click UI element by accessibility label
just dt-logs-macos                       # Stream macOS app logs (unified logging)
just dt-logs-macos-recent [minutes]      # Dump recent macOS app logs (default: 5 min)
just dt-verify-build-macos               # Verify installed macOS build version
just dt-macos-workflow <name>            # Run a named macOS test workflow (e.g., onboarding)
```

#### E2E Testing

```bash
# Core
just e2e                          # List available E2E tests
just e2e-build                    # Build E2E binaries with SHA-based caching (relay + CLI)
just e2e-run <name>               # Run E2E test(s) — use 'all' to run everything
just e2e-smoke                    # Run E2E smoke tests (fast, for every push)
just e2e-release                  # Run E2E release tests (full validation)
just e2e-integration              # Run E2E integration tests only (excludes smoke)
just e2e-all                      # Run all E2E tests (CLI + Desktop + Mobile)
just e2e-status                   # Check E2E testing status (all platforms)
just e2e-report                   # Show latest E2E test report
just e2e-coverage                 # Show E2E test coverage against Gherkin features
just e2e-clean                    # Clean all E2E test data
just e2e-setup                    # Show E2E setup guide
just e2e-map                      # Show E2E infrastructure as Mermaid diagram
just e2e-teardown-and-clean-infra # Teardown E2E infrastructure (stop relay, clean data)

# Scenarios
just e2e-scenarios                # List available E2E test scenarios
just e2e-scenario [name]          # Run an E2E test scenario (use 'all' for all)
just e2e-scenario-all             # Run all automated scenarios and show results report

# YAML scenarios
just e2e-yaml <name>              # Run a YAML scenario by name
just e2e-yaml-list                # List available YAML scenarios
just e2e-yaml-manual <name>       # Show manual instructions for a YAML scenario

# CLI testing
just e2e-cli <args>               # Run CLI command for instance (e.g., just e2e-cli alice init "Alice")
just e2e-cli-test [alice] [bob]   # Run CLI exchange test between two instances

# TUI testing
just e2e-tui <instance>           # Launch TUI for instance
just e2e-tui-multi <instances>    # Launch multiple TUI instances in separate terminals

# Desktop testing
just e2e-desktop [instance]       # Launch desktop app for instance (default: default)
just e2e-desktop-dev [instance]   # Launch desktop in dev mode for instance
just e2e-desktop-build            # Build desktop release binary

# Mobile testing
just e2e-mobile                   # Run mobile E2E tests (requires simulator/emulator + Maestro)
just e2e-deploy                   # Deploy apps to all mobile devices (iOS + Android)
just e2e-deploy-ios               # Deploy iOS app to macOS simulator
just e2e-deploy-android           # Deploy Android APK to local emulator
just e2e-android-start [avd]      # Start Android emulator (default: avd_android)
just e2e-test-mobile              # Run interactive mobile E2E test session
just e2e-screenshot               # Take screenshots from mobile devices
just e2e-logs                     # Collect logs from mobile devices

# Maestro flows
just maestro-setup                # Verify Maestro CLI is installed
just e2e-ios [flow]               # Run Maestro iOS flows (default: create_identity)
just e2e-android [flow]           # Run Maestro Android flows (default: create_identity)
just e2e-maestro [platform]       # Run all Maestro flows (platform: all|ios|android)

# Relay
just e2e-relay                    # Start local TLS relay for E2E testing
just e2e-relay-setup              # Setup local CA for TLS relay

# Website
just e2e-website                  # Run website Playwright tests locally
just e2e-website-deployed         # Run website Playwright tests against deployed site
```

#### Deployment

```bash
# Deploy
just validate [flags]             # Run pre-flight validation checks
just deploy                       # Deploy relay + landing using pre-built CI images
just deploy-with-build            # Deploy relay + landing with local build + push
just deploy-version <VERSION>     # Deploy a specific image version
just deploy-check                 # Check deployed versions against source
just deploy-rollback              # Rollback to previous deployment version
just deploy-all                   # Deploy Kamal services + sync mail config + monitoring
just relay-logs                   # Show relay logs
just test-website-image           # Verify website image contains only expected files
just backup                       # Run backup on the VPS
just verify-backup                # Verify latest backup is restorable

# Mail
just deploy-mail                  # Sync mail config + restart changed services
just deploy-mail-dry              # Preview mail config changes (dry run)
just mail-prepare                 # Prepare mail server for first-time setup
just mail-logs                    # Show mail server logs
just mail-status                  # Mail server status
just mail-webmail-logs            # Webmail logs
just mail-add-user <email>        # Add mail user
just mail-update-password <email> # Update mail user password
just mail-list-users              # List mail users

# Monitoring
just deploy-monitoring            # Deploy / update monitoring stack (Prometheus + Grafana + node_exporter)
just monitoring-status            # Show monitoring stack status
just monitoring-logs              # Follow Grafana logs
just monitoring-relay-alias       # Re-create relay alias on monitoring network (run after relay deploy)
```

#### Mobile / Bindings

```bash
just build-android [mode]         # Build Android (mode: debug|release)
just android [mode]               # Build Android APK (mode: debug|release)
just build-ios [mode]             # Build iOS (mode: debug|release)
just bindings                     # Generate UniFFI mobile bindings
just bindings-local               # Generate bindings AND wire into local platform builds
just bindings-remote              # Revert to published (remote) bindings
just check-ios                    # Run iOS checks (lint, build, test) — mirrors CI pipeline
just check-android                # Run Android checks (lint, build, test) — mirrors CI pipeline
just check-mobile                 # Run all mobile checks (iOS + Android)
```

#### Performance

```bash
just perf-build [repo]            # Measure build time (baseline benchmark, default: core)
just perf-test [repo]             # Measure test time (default: core)
just perf-duplicates [repo]       # Check for duplicate dependencies in dependency graph
just perf-bloat [repo]            # Analyze binary bloat and find largest dependencies
just perf-report [repo]           # Full build performance report (duplicates + bloat + build time)
just perf-compare [repo]          # Compare build time before and after a change
just perf-baseline-reset [repo]   # Reset baseline for comparison
just perf-sccache-stats           # Show sccache statistics (hit/miss rates)
just perf-sccache-config          # Show current sccache configuration
just perf-cold-cache [repo]       # Clear sccache and rebuild to measure cold-cache performance
```

#### Planning / Problems

```bash
just plan-validate [target]       # Validate .plan.md files (single file or directory)
just plan-list [dir]              # List all .plan.md files with task counts (default: _private/docs)
just plan-history <file>          # Show task history as JSON (requires git history)
just plan-plot <file>             # Open burn-up chart in browser (requires git history)
just plan-stale [days]            # Show .plan.md files with no git changes in N days (default: 30)
just plan-sync [flags]            # Dry-run plan sync — show what CI would update
just plan-sync-apply              # Apply plan sync changes to working tree (no commit)
just task-list                    # Show remaining tasks from master plan
just problem-list [phase]         # List problem records by status
just problems-tidy                # Move done/closed/resolved problem records to done/
just risk [flags]                 # Risk dashboard — surfaces blockers, stalled plans, recurring failures
```

#### Dev / Local Testing

```bash
just dev-relay                    # Start local relay (memory storage)
just dev-relay-tls                # Start local relay with TLS (for iOS/Android testing)
just dev-relay-tls-setup          # Setup local CA for mobile TLS testing
just dev-cli <args>               # Run CLI with isolated data (e.g., just dev-cli alice init "Alice")
just dev-tui <instance>           # Run TUI with isolated data
just dev-clean                    # Clean test data
just e2e-checklist [args]         # Run E2E test checklist (manual device testing)
just schema-check                 # Verify JSON schemas are up to date with core UI types
just core-freshness               # Check if mobile bindings and Rust consumers are up to date with core
```

#### Apps

```bash
just run [platform] [args]        # Run an application (cli|tui|linux-gtk|linux-qt|android|ios|relay)
just relay                        # Start relay server
just tui                          # Run TUI application
```

#### CI Runners

```bash
just runners-start                # Start docker-local runner service
just runners-stop                 # Stop docker-local runner service
just runners-restart              # Restart docker-local runner service
just runners-status               # Show status of all runners
just runners-logs                 # View docker-local runner logs (follow mode)
```

#### Setup / Maintenance

```bash
just check-prerequisites          # Check that required tools are installed before setup
just setup                        # Clone all repos and set up workspace (first time only)
just session-init                 # Sync + fetch + MR/branch/uncommitted dashboard
just session-end                  # Pre-exit check: uncommitted, unpushed, orphan branches
just install-dev-deps             # Install development dependencies (macOS via Homebrew + Cargo)
just install-hooks                # Install git hooks (pre-commit + pre-push) across all repos
just setup-fast-builds            # Configure sccache + mold for faster Rust builds (idempotent)
just setup-path-overrides         # Wire local path overrides after setup or branch switch
just clean                        # Clean all build artifacts
just clean-rust                   # Clean only Rust targets (faster)
just git-compact                  # Run git gc across repos to reduce pack size
```

#### Tools / Cross-Repo

```bash
just help                         # Show quick reference
just grep <pattern> [glob]        # Search across all repos (ripgrep)
just concept <name>               # Search by drift concept + aliases
just consumers <pattern>          # Find downstream usage of core API (CC-05)
just check-refs                   # Verify Cargo.toml branch refs point to main
just check-lockfile-consistency   # Catch version skew across repos (zeroize, chacha20, subtle, etc.)
just check-annotations [repo]     # Check @scenario annotation coverage (default: core)
just check-lifecycle              # Validate feature lifecycle tags on Gherkin scenarios
just check-just-docs [fix]       # Verify all recipes are documented (fix = auto-append missing)
just spellcheck                   # Run spellcheck across documentation
just reuse [repo]                 # REUSE / SPDX license header check
just lint-docs                    # Lint docs: naming convention, broken links, license text
just lint-file-size [repo]        # Check file sizes against thresholds (src: 500/1000, test: 800/1200)
just churn [repo]                 # File churn + size correlation (highest-risk files, default: core)
just sync-locales                 # Validate locale files (check for missing/extra keys)
just sync-locales-strict          # Validate locale files strictly (fail on any issues, for CI)
just vrt-gallery                  # Generate cross-platform VRT gallery (iOS, Android, Desktop, TUI)
just design-check [args]          # Run design consistency checks (--verbose for details)
just drift [severity]             # Audit drift (human-readable, fail on severity+, default: high)
just drift-ci [args]              # Audit drift for CI (JSON output, supports --severity, --category, --limit)
just tell-me-about <topic>        # Explore codebase with local LLM
just doc-refs <pattern>           # Find document references (e.g., "SP-32" or "anonymous-sender")
```
