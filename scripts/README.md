# Vauchi Dev Tools

Helper scripts, hooks, and utilities for Vauchi development.

## Structure

```
_dev-tools/
├── hooks/          # Git pre-commit and pre-push hooks
├── scripts/        # Development scripts
│   ├── dev/        # Multi-instance testing helpers
│   ├── coverage/   # Coverage reporting
│   └── ide/        # IDE setup scripts
└── archive/        # Deprecated scripts (kept for reference)
```

## Key Scripts

| Script | Purpose | Just Command |
|--------|---------|--------------|
| `commit-interactive.sh` | Interactive commit across repos | `just commit` |
| `sync-all.sh` | Pull latest from all repos | `just pull-all` |
| `feature-audit.sh` | Audit test coverage vs Gherkin | - |
| `tell-me-about.sh` | Explore codebase with local LLM | `just tell-me-about` |

### Multi-Instance Testing (`scripts/dev/`)

Test sync/exchange between multiple "devices":

```bash
# Terminal 1: Start relay
just dev-relay

# Terminal 2: Alice
just dev-cli alice init "Alice Smith"
just dev-cli alice exchange start

# Terminal 3: Bob
just dev-cli bob init "Bob Jones"
just dev-cli bob exchange complete <qr-data>
```

| Script | Purpose |
|--------|---------|
| `local-relay.sh` | Start local relay (memory storage) |
| `multi-cli.sh` | Run CLI with isolated data |
| `multi-tui.sh` | Run TUI with isolated data |
| `cleanup.sh` | Clean test data |

## Git Hooks

Install with:

```bash
just install-hooks
```

**Pre-commit** checks:
1. Rust formatting (`cargo fmt`)
2. Inline test markers
3. Potential secrets

## Archived Scripts

Large scripts moved to `archive/` for reference:
- `ios-simulators.sh` - iOS simulator management
- `android-emulators.sh` - Android emulator management
- `tdd-template.sh` - Test template generator

## See Also

- Main justfile: `../justfile` (run `just help`)
- Root CLAUDE.md: `../CLAUDE.md`
