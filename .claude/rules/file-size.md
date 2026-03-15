---
paths:
  - "**/*.rs"
apply: always
---
## File Size Convention

- Source files: warn >500 lines, split at 1000
- Test files: warn >800 lines, split at 1200
- Functions: max 100 lines (clippy `too_many_lines`, advisory)
- Structural exemptions (migrations, FFI): `// allow(large_file)` on line 1
- When creating new files, target <300 lines
- When splitting, use `tidy:` commits — no behavior change
- Check locally: `just lint-file-size [repo]`
- Churn analysis: `just churn [repo]`
- Grandfathered files listed in `.file-size-baseline` per repo — must not grow beyond baseline
