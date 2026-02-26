---
apply: always
---

## Multi-Repo Awareness

- This is a **multi-repo project** — each subdirectory is its own git repo
- Always verify correct working directory before running commands
- Use `git -C <dir>` for cross-repo operations, never blind `cd`
- Keep `Cargo.toml` git dependency branch refs pointing to `main`
- Push upstream repos first (core → cli/tui/desktop/e2e), mark downstream MRs as Draft
- iOS/Android binding repos are auto-generated — never edit manually
