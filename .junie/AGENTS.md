<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Vauchi Project Guidelines

Privacy-focused updatable contact cards via in-person exchange. E2E encrypted, decentralized.

## Quick Start

```bash
just setup         # Clone all repos (first time only)
just session-init  # Sync, fetch, show work board + dashboard (every session)
just build         # Build Rust workspace
just check         # Run all checks
just session-end   # Verify pushed, release board claims, check staleness (every session end)

# Local dev feedback loops
cargo watch -x check           # ~1s incremental with mold — fastest feedback
cargo watch -x 'nextest run'   # re-run tests on file save
```

## Tool Usage (MANDATORY)

**Always use `just` recipes instead of raw commands.** Run `just help` for commands.
Full reference: `.claude/docs/just-commands.md`

Key mappings: `cargo build` -> `just build [repo]`, `cargo test` -> `just test [repo]`,
`cargo fmt && clippy && test` -> `just check [repo]`, `grep -r` -> `just grep <pattern>`,
`glab mr create` -> `just gitlab mr-create [repo]`

## Shell & Cargo Rules

- Verify correct working directory before sub-repo commands.
- **CWD gotcha**: `just` recipes use `scripts/scripts/` (double-nested). Recipes fail if CWD is not the workspace root. Always run `just` from the root, never from a sub-repo.
- Check what's installed before suggesting tool installations.

## Multi-Repo Awareness & Git Conventions (MANDATORY)

- This is a **multi-repo project** -- each subdirectory is its own git repo.
- **Commit format**: `{type}: {Short description}` -- types: `feat`, `fix`, `refactor`, `tidy`, `docs`, `test`, `chore`
- **Co-author**: Always add `Co-Authored-By: Junie <noreply@jetbrains.com>`
- **Atomic commits**: One logical change per commit. TDD order: `tidy:` (optional) -> `test:` -> `feat:`/`fix:`
- **Branches**: `feature/`, `bugfix/`, `refactor/`, `tidy/`, `investigation/`
- **Pre-MR rebase**: Always `git fetch origin main && git rebase origin/main` before creating an MR
- **No direct push to main**: Merge via MR only. Sync branch names across repos.
- **NEVER `cd` into sub-repo directories** -- use `git -C <dir>` for git commands and `just <recipe> [repo]` for everything else.
- **Stay at workspace root** -- the directory containing this file.
- **Use `just git *` recipes for all multi-repo git operations** -- never write raw bash loops over repos
  - Key recipes: `status`, `branch <name>`, `branch-inspect <name>`, `push-all`, `wip [msg]`, `wip-undo`, `resume <branch>`, `fetch`, `sync`, `cleanup`, `branch-health`
- **Use `just gitlab *` for all GitLab operations** -- never use raw `glab` commands
  - Key recipes: `mr-create [repo]`, `mr-list [repo]`, `pipeline-status [repo]`, `pipeline-retry <id> [repo]`
- Keep `Cargo.toml` git dependency branch refs pointing to `main`
- Push upstream repos first (core -> cli/tui/e2e and other downstream), mark downstream MRs as Draft
- **Branch inspection: ALWAYS check ALL repos** before reporting status or taking action on a branch. Use `just git branch-inspect <name>`.

## Dependencies & Repo Layout

| Crate | Consumers | Notes |
|-------|-----------|-------|
| `vauchi-core` | cli, tui, e2e, android, ios, macos, windows, linux-gtk, linux-qt, web-demo | Git dep, `branch = "main"` |
| `vauchi-platform` | ios, macos, android | UniFFI bindings (SPM via vauchi-platform-swift; Maven AAR from core) |
| `vauchi-cabi` | linux-qt, windows | C ABI exports |
| `vauchi-protocol` | relay | Shared types only (serde) |

Local dev uses `.cargo/config.toml` path overrides. `vauchi-platform-kotlin` is archived.

Sub-repo names: core, relay, cli, tui, android, ios, macos, windows, linux-gtk, linux-qt, web-demo, e2e, features, docs, website, scripts, locales, themes, assets, _private, drift-detector, vauchi-platform-swift, gitlab-profile

## Visibility Boundary (CRITICAL)

- **Design documents** (`*-design.md`) -> `_private/docs/designs/`
- **Implementation plans, task DAGs** -> `_private/docs/planning/todo/`
- **Investigations, audits, assessments** -> `_private/docs/investigations/`
- **Post-mortems** -> `_private/docs/post-mortems/`
- **ADRs** -> `_private/docs/decisions/` (numbered `adr-NNN-slug.md`)
- **Reference docs** -> `_private/docs/reference/`
- **Never write plans to `docs/`** -- the `docs/` repo is public and deployed to docs.vauchi.app
- **Never embed local absolute paths** (`/Users/...`, `/home/...`) in any document
- **Never reference `_private/` paths from public docs**

## TDD, Code Structure & Crypto (MANDATORY)

- **TDD**: Tidy->Commit->Red->Green->Commit->Refactor->Commit. Test FIRST.
  - **Tidy First** (optional): small structural-only improvement before starting a cycle. Own `tidy:` commit. No behavior change.
  - Commit immediately when tests go green
  - Commit after each refactor if tests still green
- **Structure**: `src/` = prod, `tests/` = tests (siblings). Never mix. Test helpers in `tests/common/` or `tests/helpers/`
- **Coverage**: 90%+ for vauchi-core. Measure with `just coverage`.

## ADR Constraints (MANDATORY)

### Crypto (ADR-002, ADR-019)

- **Never mock crypto in tests** -- use real crypto operations
- **Approved crates only**: RustCrypto primary (`ed25519-dalek`, `x25519-dalek`, `sha2`, `hmac`, `hkdf`), spec-mandated (`chacha20poly1305`, `argon2`), transport (`snow`, `aws-lc-rs` via rustls), privacy (`ohttp` via ADR-037). New crypto crates require ADR amendment
- **XChaCha20-Poly1305 for all new encryption** -- AES-256-GCM is legacy decryption only
- **Always use HKDF domain separation** -- every derivation path has a unique info string
- **Identity signing key uses raw seed directly** -- not HKDF-derived (Ed25519 requirement)
- **Zeroize key material after use** -- all secret keys must implement `ZeroizeOnDrop`
- **Never expose plaintext to the relay** -- relay sees encrypted blobs only
- **Always encrypt sensitive fields at rest**

### Architecture (ADR-021, ADR-022, ADR-023)

- **Core owns all business logic** -- frontends never duplicate data logic, filtering, validation, or computation
- **Frontends are pure renderers** -- they render `ScreenModel` components natively and forward `UserAction`s to core
- **Never put `DisplayHint` on `ScreenModel`** -- it's a construction parameter, not screen data
- **Frontends must never branch on form factor** -- core handles form-factor differences via `DisplayHint`
- **Use `InlineConfirm` for irrevocable actions, `ShowToast` for reversible feedback**

### Hardware & Platform (ADR-030, ADR-031)

- **Core must never call hardware directly** -- uses command/event protocol: core emits `ExchangeCommand`, frontends execute and return `ExchangeHardwareEvent`
- **Never create a Platform trait in core**
- **Never reintroduce the Transport generic parameter** -- `Box<dyn Transport>` is the final form
- **Exchange tests must be pure input/output** -- events in, commands out, no mock traits

### Bindings (ADR-025, ADR-026)

- **Frontend repos must never run `cargo`** -- except Rust-native repos (linux-gtk, windows, CLI, TUI)
- **UI types are in `core/vauchi-app/src/ui/`** -- not `vauchi-core/src/ui/`

### Design (ADR-038)

- **All visual properties** (colors, spacing, typography) **defined in `themes/` or `tokens.json`** -- never hardcoded in frontend code
- **All user-visible strings** in `locales/*.json` via `t("key")` -- never hardcoded
- **`tokens.json` is the single source of truth for design tokens**

### Desktop (ADR-027)

- **Desktop = 4 native repos** (`linux-gtk`, `macos`, `windows`, `linux-qt`) -- not single `desktop/` Tauri repo (archived)
- **Never reference** `desktop/`, `SolidJS`, `Tauri`, or ARIA in active plans -- these are stale

### Security (ADR-032 through ADR-037)

- **Trust level is never user-editable** -- pure deterministic derivation from exchange facts
- **Duress alerts disguised as card updates** -- no special message type, no metadata flag
- **SMK derived once at identity creation, stored in SecureStorage, never re-derived**
- **Device link QR codes expire after 5 minutes**
- **OHTTP gateway and relay operators must be distinct entities**

## Test Quality Rules (MANDATORY)

- **CC-03 Specific Assertions**: Assert exact values. Forbidden: `assert!(result.is_ok())` without value check, `if let Ok(x)` (silently skips Err), zero-assertion tests
- **CC-04 Property-Based Tests**: `proptest` for crypto, serialization roundtrips, parsers
- **CC-06 No Real-Time Waits**: Never `sleep()` in tests. Use mockable time or event sync
- **CC-11**: Test at least one failure path per function
- **CC-13 Stateful Property Tests**: For state machines, verify invariants across random operation sequences
- **CC-14 Adversarial Test Data**: Security boundaries need parameterized tests with adversarial payloads
- **CC-17**: Every `#[test]` must contain `assert*!`, `prop_assert*!`, `.expect()`, or `#[should_panic]`
- **CC-21 Chesterton's Fence**: Before disabling a check, find root cause first

## File Size Convention

- Source files: warn >500 lines, hard limit 1000
- Test files: warn >800 lines, hard limit 1200
- Functions: max 100 lines
- When splitting, use `tidy:` commits -- no behavior change
- **Structural exemptions** (do NOT split): UniFFI facades, migration ledgers, state machines, security-critical flows

## Logging Rules

- **NEVER log PII**: contact names, public keys, tokens, card content, relay URLs with tokens
- No remote log shipping -- ever. Logs stay on-device.
- Never log QR data, even truncated -- it contains cryptographic material

## Feature Specifications

- Gherkin `.feature` files: one feature per file, `snake_case.feature`
- **Lifecycle tags** (MANDATORY on every Scenario): `@implemented`, `@planned`, `@wip`
- `@wip` must resolve before merge

## Locales & Themes

- `en.json` is source of truth -- all keys must exist here first
- All locales must have same keys (CI validates parity)
- 11 required color tokens in themes
- Validate: `python3 scripts/validate.py --strict`

## Portable Shell (MANDATORY)

All shell scripts must work on both macOS and Linux. **Never use `grep -P`** (Perl regex) -- use `grep -E` or `just grep`.

## Self-Healing

Leave the codebase healthier than you found it. Heal what you encounter, not what you imagine.

- **Inline**: Problem is in a file you're already editing -> current commit or own `tidy:`
- **Tidy**: Problem is in a file you read, not your edit target -> separate `tidy:` commit
- **Flag**: Systemic, cross-cutting, or needs design decisions -> problem record, no code

## Verify Before Acting (MANDATORY)

Code is the source of truth. Plans, problem records, and search results become stale.

- Before implementing a fix from a problem record: verify the bug still exists in code
- Before claiming something is missing: use multiple search methods
- When a doc contradicts code: the doc is wrong, fix the doc

## Session Hygiene

- Run `just session-init` at session start
- Run `just session-end` at session end
- All work must be committed + pushed, or explicitly abandoned with `just git wip`
- Never leave uncommitted changes across sessions

## Drift Detection

Run `just drift` after completing features or before MRs. Levels: `high`/`medium`/`low`.

## GitLab & Git

All repos have protected `main` -- merge via MR only, force push disabled.
Use `just gitlab mr-create [repo]` for MRs.

## Reference Docs

- `.claude/docs/`: `just-commands.md`, `repo-organization.md`, `commit-conventions.md`, `local-bindings.md`, `drift-naming.md`, `test-quality-rules.md`, `exchange-protocol.md`, `tls-backend-decisions.md`
- `_private/docs/testing/`: `manual-testing.md`, `device-automation/`
- Per-repo docs in `.claude/docs/`: `platform-bindings-rules.md`, `scripts-repo-rules.md`, `small-repos-rules.md`, `device-testing-rules.md`

## Problem Workflow

All significant work follows the Problem to Solution Flow.
Lifecycle: `intake -> investigating -> planning -> implementing -> testing -> done`

Every problem record must have: **status**, **priority**, **owner**, **goals**.

## Internal Documentation Structure

| Path | Content |
|------|---------|
| `_private/docs/problems/` | Active problem records (with `done/`) |
| `_private/docs/designs/` | Design documents |
| `_private/docs/planning/` | Lifecycle-tracked plans (`todo/`, `done/`, `deferred/`, `rejected/`, `archived/`) |
| `_private/docs/investigations/` | Research, audits, assessments |
| `_private/docs/decisions/` | ADR decision records |
| `_private/docs/reference/` | Guides, strategies, workflows |

## Work Context

The file `.claude/.workcontext` tracks the current problem and workflow phase.
Format: `{"problem": "slug", "phase": "implementing"}`
Valid phases: `intake`, `investigating`, `planning`, `implementing`, `testing`, `done`
