---
paths:
  - "drift-detector/**"
apply: always
---

## Drift Detector

- **Stack**: TypeScript, vitest, SQLite + FTS5
- **Modes**: MCP server (default) for interactive use, `audit --ci --fail-on=<severity>` for pipelines
- **Parsers**: Rust, TypeScript, Gherkin, TOML
- **Testing**: `npm test` (vitest with in-memory SQLite)
