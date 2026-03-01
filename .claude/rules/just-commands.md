---
apply: always
---

## Tool Usage: Always Use Just Recipes (MANDATORY)

**Run all commands from the workspace root** (the `vauchi` directory containing the justfile).
Just recipes handle correct working directories, toolchain detection, and multi-repo orchestration.

### Build, Test, Lint

| Instead of... | Use... |
|---------------|--------|
| `cargo build` | `just build [repo]` |
| `cargo test` / `cargo nextest` | `just test [repo]` |
| `cargo fmt` | `just fmt [repo]` |
| `cargo clippy` | `just lint [repo]` |
| `cargo fmt && cargo clippy && cargo test` | `just check [repo]` |
| `cargo test -p <crate>` | `just test-crate <crate>` |
| `cargo test --test <name>` | `just test-file <name> [repo]` |
| `cargo test <pattern>` | `just test-name <pattern> [repo]` |

### Searching (PREFER just recipes over built-in Grep/Glob tools)

Use `just grep` and `just concept` via Bash instead of the built-in Grep and Glob tools.
This reduces token usage, avoids permission prompts, and searches across all repos in one call.

| Instead of... | Use... |
|---------------|--------|
| Grep tool (content search) | `just grep <pattern> [glob]` |
| Glob tool (file search) | `just grep` with a filename pattern, or `ls`/`find` via just |
| Searching by domain concept | `just concept <name>` |
| Finding API consumers (CC-05) | `just consumers <pattern>` |
| `grep -P` (Perl regex) | `just grep <pattern>` (uses ripgrep, supports full regex) |
| Multiple Grep calls | Single `just grep <pattern>` (searches all repos at once) |

**When to use built-in Grep/Glob instead:** Only when searching within a single known file or a very narrow path (e.g., reading a specific function). For cross-repo or broad searches, always use just recipes.

### GitLab & Git

| Instead of... | Use... |
|---------------|--------|
| `glab mr list` / `glab mr create` | `just gitlab mr-list [repo]` / `just gitlab mr-create [repo]` |
| `glab ci status` | `just gitlab pipeline-status [repo]` |
| Raw `git -C <repo>` for multi-repo | `just git status` / `just git main` |
| `git diff origin/main...HEAD` | `just git diff-main [repo]` |
| `git log origin/main..HEAD` | `just git log-branch [repo]` |

### Repo argument rules

- **Omit** → auto-detect from pwd (inside sub-repo) or run all (from workspace root)
- **Explicit name** → `just test core`, `just lint relay`, `just check desktop`
- **`all`** → `just test all` runs across all applicable repos
