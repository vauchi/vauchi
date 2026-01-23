# Contributing to Vauchi

## Quick Start

```bash
# Clone and setup workspace
git clone https://github.com/vauchi/vauchi.git
# or: git clone git@gitlab.com:vauchi/vauchi.git
cd vauchi
just setup

# Build and test
just build
just check
```

## Development Workflow

### 1. TDD Required

All code changes must follow Test-Driven Development:

1. Write failing test first (Red)
2. Write minimal code to pass (Green)
3. Refactor
4. Tests must trace to `features/*.feature` scenarios

See [docs/2026-01-22-TDD_RULES.md](docs/2026-01-22-TDD_RULES.md) for details.

### 2. Before Committing

```bash
just check    # Runs fmt-check, lint, test
```

Or individually:
```bash
just fmt                    # Format code
just lint                   # Clippy (must pass)
just test                   # All tests green
```

### 3. Commit Messages

- Use imperative mood: "Add feature" not "Added feature"
- Reference issue numbers where applicable
- Keep first line under 72 characters

### 4. Multi-Repo Commits

Use `just commit` for interactive commits across all repos with changes.

### 5. Planning Docs

If implementing a feature from `docs/planning/todo/`:
- Update the planning doc as you go
- Move to `docs/planning/done/` when complete

## Code Guidelines

### Rust

- Use `ring` crate for all cryptography
- Never mock crypto in tests
- 90%+ test coverage for vauchi-core
- Use `Result`/`Option`, fail fast

### Structure

```
crate/
├── src/      # Production code only
└── tests/    # Integration tests only
```

## Repository Structure

| Repo | Purpose |
|------|---------|
| code/ | Rust monorepo |
| features/ | Gherkin specs (shared) |
| android/ | Android app |
| ios/ | iOS app |
| docs/ | Documentation |
| dev-tools/ | Build scripts, hooks |

## Useful Commands

```bash
just help              # Show all commands
just feature-audit     # Check test coverage vs features
just dev-relay         # Start local relay for testing
just dev-cli alice     # Run CLI with isolated data
just sync-repos        # Pull all repos
```

## Getting Help

- Check [docs/faq.md](docs/faq.md)
- Review existing issues
- Ask in discussions

## License

By contributing, you agree that your contributions will be licensed under MIT.
