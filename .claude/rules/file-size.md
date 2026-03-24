---
paths:
  - "**/*.rs"
apply: always
---
## File Size Convention

- Source files: warn >500 lines, split at 800 (aspirational), hard limit 1000
- Test files: warn >800 lines, split at 1000, hard limit 1200
- Functions: max 100 lines (clippy `too_many_lines`, advisory)
- When creating new files, target <300 lines
- When splitting, use `tidy:` commits — no behavior change
- Check locally: `just lint-file-size [repo]`
- Churn analysis: `just churn [repo]`
- Grandfathered files listed in `.file-size-baseline` per repo — must not grow beyond baseline

### Structural Exemptions (do NOT split)

These file types are large by design — splitting would create worse problems:
- **UniFFI facades** (`vauchi-platform/lib.rs`): splitting breaks binding generation
- **Migration ledgers** (`storage/migration.rs`): version history must be co-located
- **State machines** (`exchange/session.rs`): scattered transitions create protocol bugs
- **Security-critical flows** (`recovery/mod.rs`): crypto + verification belong together
- **Well-structured test files** (internal `mod` blocks): already organized, just large

### Do NOT extract sub-crates for file size

Sub-crate extraction hurts incremental compilation (Cargo only does incremental within crates).
No external consumers exist. See PRB-2026-032 investigation for full analysis.

### Architectural boundary splits are a separate concern

The no-extraction rule applies to file-size motivated splits. Extracting a crate to enforce
an architectural boundary (e.g., separating security-critical modules from app-layer) is
evaluated on merit — compilation improves because unrelated modules stop triggering each
other's rebuilds.
