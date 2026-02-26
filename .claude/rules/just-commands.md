---
apply: always
---

## Tool Usage: Always Use Just Recipes

- **Never use raw `cargo` commands** — use `just` recipes instead
- `cargo test` → `just test [repo]` or `just test-crate <crate>`
- `cargo fmt` → `just fmt [repo]`
- `cargo clippy` → `just lint [repo]`
- `cargo build` → `just build [repo]`
- `cargo fmt && cargo clippy && cargo test` → `just check [repo]`
- GitLab operations → `just gitlab <command> [repo]`
- Multi-repo git → `just git status`, `just git main`
- Omit repo arg to auto-detect from pwd, or pass `all` for everything
