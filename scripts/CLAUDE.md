# CLAUDE.md - Dev Tools

Cross-project development tools, scripts, and utilities.

## Structure

| Path | Purpose |
|------|---------|
| `scripts/` | General dev scripts |
| `scripts/coverage/` | Coverage reporting |
| `scripts/dev/` | Multi-instance testing |
| `scripts/ide/` | IDE setup scripts |
| `hooks/` | Git hooks for all repos |
| `archive/` | Deprecated scripts |

## Key Scripts

| Script | Purpose | Just Command |
|--------|---------|--------------|
| `commit-interactive.sh` | Interactive commit across repos | `just commit` |
| `sync-all.sh` | Pull/fetch all repos | `just pull-all` |
| `tell-me-about.sh` | Explore codebase with local LLM | `just tell-me-about` |

## Multi-Instance Testing (`scripts/dev/`)

For testing sync/exchange between multiple "devices":

| Script | Purpose | Just Command |
|--------|---------|--------------|
| `local-relay.sh` | Start local relay (memory storage) | `just dev-relay` |
| `multi-cli.sh` | Run CLI with isolated data | `just dev-cli <name>` |
| `multi-tui.sh` | Run TUI with isolated data | `just dev-tui <name>` |
| `cleanup.sh` | Clean test data and caches | `just dev-clean` |

## Git Hooks

Install with `just install-hooks`. Checks:
- Rust formatting
- Inline test markers
- Potential secrets

## See Also

- Root justfile: `../justfile`
- Feature specs: `../features/`
