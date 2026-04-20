---
apply: always
---

---
paths:

- "**/*.sh"
- "**/*.bash"
- ".claude/hooks/**"
- "scripts/**"

---

## Portable Shell (MANDATORY)

All shell scripts and Bash tool commands must work on both macOS and Linux.

### Forbidden: `grep -P` (Perl regex)

`grep -P` is a GNU extension — macOS ships BSD grep which does not support it.

**Use instead:**

- `just grep <pattern>` — ripgrep, supports full regex, works everywhere
- `grep -E` — extended regex (POSIX, available on both platforms)
- `sed -n 's/pattern/\1/p'` — for extraction that would use `-oP`

The `check-bash-grep.sh` hook enforces this at runtime for Bash tool commands.

### Other GNU vs BSD pitfalls

| GNU (Linux) | macOS equivalent | Notes |
|---|---|---|
| `stat -c %Y` | `stat -f %m` | File modification time |
| `grep -oP '...\K...'` | `sed -n 's/pattern/\1/p'` | Perl lookbehind extraction |
| `md5sum` | `md5` or `shasum -a 256` | Prefer `shasum` for portability |
| `readlink -f` | `realpath` or manual resolution | Canonical path |
| `date -d` | `date -j -f` | Date parsing |
| `sed -i ''` (macOS) vs `sed -i` (GNU) | Use `sed -i.bak` + `rm` | In-place edit |
| `sed 's/\+//'` (GNU `\+`) | `sed 's/[X][X]*//'` or `sed -E 's/+//'` | `\+` is GNU-only; BSD sed silently fails |
