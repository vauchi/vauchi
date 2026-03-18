---
paths:
  - "relay/**"
  - "drift-detector/**"
  - "scripts/**"
---

## Relay

- **Stateless**: No persistent sensitive data. Forwards encrypted blobs, never decrypts.
- Uses `vauchi-protocol` (from `core/`) for shared message types. Does **not** depend on `vauchi-core`.

## Drift Detector

- **Stack**: TypeScript, vitest, SQLite + FTS5
- **Modes**: MCP server (default) for interactive use, `audit --ci --fail-on=<severity>` for pipelines
- **Parsers**: Rust, TypeScript, Gherkin, TOML
- **Testing**: `npm test` (vitest with in-memory SQLite)

## Dev Scripts

- **Structure**: `scripts/` (general), `hooks/` (git hooks), `ci-templates/` (shared CI), `archive/` (deprecated)
- Scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, executable, usage comments at top
- **pre-commit** hook blocks: formatting errors, inline test markers, potential secrets
- **pre-push** hook blocks: lint/test failures (Rust, iOS, Android)
