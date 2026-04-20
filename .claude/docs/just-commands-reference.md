<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Just Commands — Specialized Recipe Reference

Recipes for specialized contexts (device testing, E2E, deployment, perf,
etc.). For daily-use recipes (build/test/git/gitlab/grep/release), see
`just-commands.md` — that's auto-loaded into every session and covers ~90%
of work.

Read this file **only** when working in one of the categories below.

## Device Testing (mobile)

```bash
just prepare-device-test [core_dir]       # Build, package, install both apps on physical devices
just rebuild-ios [core_dir]               # Rebuild + install iOS only (skip Android)
just rebuild-android [core_dir]           # Rebuild + install Android only (skip iOS)
just dt-verify-builds                     # Verify installed build versions on connected devices
just dt-logs-android                      # Capture Android logs (Vauchi + exchange tags)
just dt-logs-android-stream               # Clear and stream Android logs
just dt-logs-ios                          # Stream iOS device logs (pymobiledevice3 fallback)
just dt-screenshot-android [file]         # Screenshot from Android (default: screenshot.png)
just dt-screenshot-ios [file]             # Screenshot from iOS (default: screenshot.png)
just dt-relaunch-ios                      # Kill and relaunch iOS app
just dt-relaunch-android                  # Kill and relaunch Android app
just dt-deploy-ios                        # Install + relaunch iOS (build already done)
just dt-deploy-android                    # Install + relaunch Android (build already done)
just dt-wda-start                         # Start WebDriverAgent on connected iPhone
just dt-ios-tap <x> <y> [wda_url]         # Tap iOS screen at coordinates via WDA
just dt-wda-screenshot [file] [wda_url]   # iOS screenshot via WDA
```

## Device Testing (macOS)

```bash
just dt-build-macos                       # Build and launch macOS app for manual testing
just dt-launch-macos                      # Launch macOS app (build first if needed)
just dt-relaunch-macos                    # Kill and relaunch macOS app
just dt-screenshot-macos [file]           # Capture screenshot of Vauchi window
just dt-screenshot-macos-named <name>     # Named screenshot into testing directory
just dt-macos-click <x> <y>               # Click at coordinates in Vauchi window
just dt-macos-type <text>                 # Type text into focused field
just dt-macos-key <key>                   # Press a key (return, tab, escape, delete)
just dt-macos-return                      # Press Return key
just dt-macos-tab                         # Press Tab key
just dt-macos-escape                     # Press Escape key
just dt-macos-accessibility-tree         # Dump accessibility tree of Vauchi window
just dt-macos-find-element <label>        # Find UI element by accessibility label
just dt-macos-click-element <label>       # Click UI element by accessibility label
just dt-logs-macos                       # Stream macOS app logs (unified logging)
just dt-logs-macos-recent [minutes]      # Dump recent macOS app logs (default: 5 min)
just dt-verify-build-macos               # Verify installed macOS build version
just dt-macos-workflow <name>             # Run a named macOS test workflow
```

## E2E Testing

```bash
# Core
just e2e                          # List available E2E tests
just e2e-build                    # Build E2E binaries with SHA-based caching (relay + CLI)
just e2e-run <name>               # Run E2E test(s) — use 'all' to run everything
just e2e-smoke                    # Smoke tests (fast, every push)
just e2e-release                  # Release tests (full validation)
just e2e-integration              # Integration tests only (excludes smoke)
just e2e-all                      # All E2E (CLI + Desktop + Mobile)
just e2e-status                   # Status across all platforms
just e2e-report                   # Latest test report
just e2e-coverage                 # Coverage against Gherkin features
just e2e-clean                    # Clean all test data
just e2e-setup                    # Setup guide
just e2e-map                      # Mermaid diagram of infra
just e2e-teardown-and-clean-infra # Teardown infrastructure

# Scenarios
just e2e-scenarios                # List scenarios
just e2e-scenario [name]          # Run scenario (use 'all')
just e2e-scenario-all             # Run all + show report

# YAML scenarios
just e2e-yaml <name>
just e2e-yaml-list
just e2e-yaml-manual <name>

# CLI testing
just e2e-cli <args>               # Run CLI for instance (e.g., alice init "Alice")
just e2e-cli-test [alice] [bob]   # Exchange test between two instances

# TUI testing
just e2e-tui <instance>
just e2e-tui-multi <instances>

# Desktop testing
just e2e-desktop [instance]
just e2e-desktop-dev [instance]
just e2e-desktop-build

# Mobile testing
just e2e-mobile                   # Mobile E2E (requires sim/emu + Maestro)
just e2e-deploy                   # Deploy to all mobile devices (iOS + Android)
just e2e-deploy-ios               # iOS app to macOS simulator
just e2e-deploy-android           # APK to local emulator
just e2e-android-start [avd]      # Start Android emulator (default: avd_android)
just e2e-test-mobile              # Interactive mobile E2E session
just e2e-screenshot               # Mobile screenshots
just e2e-logs                     # Mobile logs

# Maestro flows
just maestro-setup
just e2e-ios [flow]               # Default: create_identity
just e2e-android [flow]
just e2e-maestro [platform]       # platform: all|ios|android

# Relay / Website
just e2e-relay                    # Local TLS relay for E2E
just e2e-relay-setup              # Local CA for TLS
just e2e-website                  # Playwright tests locally
just e2e-website-deployed         # Playwright against deployed site
```

## Deployment

```bash
# Deploy
just validate [flags]             # Pre-flight validation
just deploy                       # Deploy relay + landing using pre-built CI images
just deploy-with-build            # Deploy with local build + push
just deploy-version <VERSION>     # Specific image version
just deploy-check                 # Check deployed versions vs source
just deploy-rollback              # Rollback to previous version
just deploy-all                   # Kamal services + mail config + monitoring
just relay-logs
just test-website-image
just backup                       # Backup on the VPS
just verify-backup                # Verify latest backup is restorable

# Mail
just deploy-mail                  # Sync mail config + restart changed services
just deploy-mail-dry              # Preview mail config changes
just mail-prepare                 # First-time setup
just mail-logs
just mail-status
just mail-webmail-logs
just mail-add-user <email>
just mail-update-password <email>
just mail-list-users

# Monitoring
just deploy-monitoring            # Prometheus + Grafana + node_exporter
just monitoring-status
just monitoring-logs              # Follow Grafana logs
just monitoring-relay-alias       # Re-create relay alias (run after relay deploy)
```

## Mobile / Bindings

```bash
just build-android [mode]         # debug|release
just android [mode]               # Android APK
just build-ios [mode]
just bindings                     # Generate UniFFI mobile bindings
just bindings-local               # Generate AND wire into local platform builds
just bindings-remote              # Revert to published (remote) bindings
just check-ios                    # Mirrors iOS CI pipeline
just check-android                # Mirrors Android CI pipeline
just check-mobile                 # Both iOS + Android
```

## Performance

```bash
just perf-build [repo]            # Measure build time (baseline, default: core)
just perf-test [repo]             # Measure test time
just perf-duplicates [repo]       # Duplicate dependencies
just perf-bloat [repo]            # Binary bloat / largest deps
just perf-report [repo]           # Full report (duplicates + bloat + build time)
just perf-compare [repo]          # Build time before/after a change
just perf-baseline-reset [repo]
just perf-sccache-stats           # Hit/miss rates
just perf-sccache-config
just perf-cold-cache [repo]       # Clear sccache + rebuild
```

## Planning / Problems

```bash
just plan-validate [target]       # Validate .plan.md (file or directory)
just plan-list [dir]              # List with task counts (default: _private/docs)
just plan-history <file>          # JSON task history
just plan-plot <file>             # Burn-up chart in browser
just plan-stale [days]            # No git changes in N days (default: 30)
just plan-sync [flags]            # Dry-run plan sync
just plan-sync-apply              # Apply plan sync
just task-list                    # Remaining tasks from master plan
just problem-list [phase]         # By status
just problems-tidy                # Move done/closed/resolved → done/
just risk [flags]                 # Risk dashboard
```

## Dev / Local Testing

```bash
just dev-relay                    # Local relay (memory storage)
just dev-relay-tls                # Local relay with TLS (iOS/Android)
just dev-relay-tls-setup          # Local CA for mobile TLS
just dev-cli <args>               # CLI with isolated data
just dev-tui <instance>           # TUI with isolated data
just dev-clean                    # Clean test data
just e2e-checklist [args]         # Manual device testing checklist
just schema-check                 # JSON schemas vs core UI types
just core-freshness               # Bindings + Rust consumers vs core
```

## CI Runners

```bash
just runners-start                # Start docker-local runner
just runners-stop
just runners-restart
just runners-status
just runners-logs                 # Follow mode
```

## Setup / Maintenance

```bash
just check-prerequisites          # Required tools before setup
just setup                        # Clone all repos (first time only)
just session-init                 # Sync + fetch + dashboard
just session-end                  # Pre-exit check
just install-dev-deps             # macOS via Homebrew + Cargo
just install-hooks                # pre-commit + pre-push across repos
just setup-fast-builds            # sccache + mold (idempotent)
just setup-path-overrides         # Wire local path overrides
just clean                        # All build artifacts
just clean-rust                   # Only Rust targets
just git-compact                  # git gc across repos
just tmp-clean                    # Orphaned vauchi test temp dirs
just sweep [days]                 # Stale cargo artifacts (default: 30 days)
```

## Stash (cross-repo)

```bash
just git stash-list               # Stashes across all repos
just git stash-clear              # Clear all stashes
just git pull-all                 # Pull latest in all repos
just git checkout-main            # Checkout main in all repos
```

## Misc / Specialized Tools

```bash
just check-annotations [repo]     # @scenario annotation coverage (default: core)
just check-lifecycle              # Validate Gherkin lifecycle tags
just check-just-docs [fix]        # Verify recipes are documented
just sync-locales                 # Validate locale files
just sync-locales-strict          # CI-strict mode
just vrt-gallery                  # Cross-platform VRT gallery
just design-check [args]          # Design consistency
just drift-ci [args]              # Drift JSON for CI
just docs                         # Rust docs
just bench [repo]                 # Criterion benchmarks
just watch                        # Watch + tests (core only)
just metrics [args]               # Engineering metrics dashboard
just metrics-push [args]          # Push to Prometheus pushgateway
just build-release                # Release binaries
```
