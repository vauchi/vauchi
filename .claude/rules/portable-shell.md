---
paths:
  - "**/*.sh"
  - "**/*.bash"
  - ".claude/hooks/**"
  - "scripts/**"
---

## Portable Shell (MANDATORY)

Shell must run on **three** dialects, not two:

- **GNU coreutils** (Linux hosts, most self-hosted runners)
- **BSD coreutils** (macOS)
- **BusyBox** (alpine-based CI images — `alpine:3.21` in this project)

A script that works on the first two can still fail on the third. BusyBox
accepts unknown long options silently in some builds and rejects them
loudly in others; either way, a GNU-only flag in an alpine CI job is a
latent bug.

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

### BusyBox gotchas (alpine CI)

Alpine's default `grep`, `sed`, `awk`, `find`, and `tar` are BusyBox
applets — a minimal subset of GNU. Even flags that work on both GNU and
BSD may be absent. In 2026-04 this caused `lint:claude-md` to flag
every doc as orphan when `grep --exclude=` short-circuited the
recursive search.

| Forbidden in alpine CI | Portable alternative |
|---|---|
| `grep --exclude=<pat>` | `grep -rl <pat> <paths> \| grep -v "<self>"` |
| `grep --include=<pat>` | `find <paths> -name '<pat>' -print0 \| xargs -0 grep …` |
| `grep -P` | `grep -E` or `sed -n 's/…/\1/p'` |
| `sed --in-place=…` | `sed -i.bak … && rm …bak` |
| `awk 'gensub(…)'` | plain `sub`/`gsub` + intermediate variable |
| `find … -printf '…'` | `find … -exec <cmd> {} \;` |

**Verification rule**: before pushing any shell that runs in an
`alpine:*` CI image, run it inside the same image:

```sh
docker run --rm -v "$PWD":/work -w /work alpine:3.21 sh -c '<your-script>'
```

"It works on my host" is not evidence when the host is Linux/GNU and
CI is alpine/BusyBox.

**Detection rule**: if a scripted check suddenly flags "everything" as
wrong (e.g. every doc is orphan, every file fails lint), suspect the
tool before suspecting the data. Apply the sanity threshold pattern:

```sh
if [ "$errors" -gt 5 ]; then
    echo "POSSIBLE TOOL BUG: $errors issues — check flags, not data"
    exit 2
fi
```
