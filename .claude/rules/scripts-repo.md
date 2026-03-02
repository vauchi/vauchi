---
paths:
  - "scripts/**"
apply: always
---

## Dev Scripts

- **Structure**: `scripts/` (general), `hooks/` (git hooks), `ci-templates/` (shared CI), `archive/` (deprecated)
- Scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, executable, usage comments at top
- **pre-commit** hook blocks: formatting errors, inline test markers, potential secrets
- **pre-push** hook blocks: lint/test failures (Rust, iOS, Android)
