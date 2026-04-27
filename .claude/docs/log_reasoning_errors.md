<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Reasoning Errors, Wrong Implementations, Tool Misuse — Session Log

Lightweight, append-only log of moments when reasoning, an
implementation, or a tool usage was found to be wrong. Read by future
sessions to avoid repeating the same dead ends — saves tokens by
short-circuiting analysis when a known pitfall is recognized.

## How this differs from `claude-errors-and-misjudgments.md`

| | `log_reasoning_errors.md` (this file) | `claude-errors-and-misjudgments.md` |
|---|---|---|
| Granularity | Quick, one-off entries | Distilled patterns (E##) |
| When to add | Anytime an error is caught | When a pattern recurs |
| Format | Lightweight prose | Structured (root cause → prevention → test guard) |
| Lifecycle | Append; promote after 3+ similar entries | Permanent reference |

## When to append an entry

- **Self-caught**: realized mid-task that a hypothesis or step was wrong
- **User-corrected**: user pointed out a misuse, wrong API, wrong tool
- **Discovery**: while reviewing past work, found a stale claim or buggy fix
- **Tool misuse**: invoked a tool with wrong args / wrong tool for job

If the same kind of entry appears 3+ times → promote to a numbered
entry in `claude-errors-and-misjudgments.md` and reference it from a
rule in `.claude/rules/`.

## Format

```markdown
### YYYY-MM-DD — short summary
- **What**: what I did or claimed
- **Trigger**: how it was caught (self / user / CI / review)
- **Root cause**: 1 line — why I was wrong
- **Lesson**: behavioral change going forward
- **Recurrence**: 1 (or N if cumulative)
```

Keep entries terse — they exist to be skimmed quickly across sessions.
If an entry needs more than ~6 lines, it probably belongs in a problem
record or design doc.

## Pruning

- Entries older than 6 months that never recurred → delete (noise)
- Entries promoted to E## → delete here, add a one-line back-reference
  to the E## entry

---

*New entries below this line. Newest first.*

### 2026-04-20 — Used GNU-only `grep --exclude=` in alpine-CI shell script

- **What**: After fixing the `check-claude-md` orphan-detector, I used
  `grep --exclude="$name"` to prevent a file from matching itself. Works
  locally (GNU grep). In CI the job runs in `alpine:3.21`, whose default
  `grep` is BusyBox — `--exclude` is unrecognized, the recursive search
  silently short-circuited, and *all 18 docs* were reported orphan on
  pipeline 2464648339.
- **Trigger**: User escalation ("fix this!!!!") after the pipeline went
  red again with a worse failure than the original.
- **Root cause**: Did not apply `portable-shell.md` rules before writing
  a shell script that runs on alpine. Verified the fix only against the
  host's GNU grep.
- **Lesson**: For any shell script that runs in `alpine:*` CI images,
  test inside the same image (`docker run --rm -v "$PWD":/work -w /work
  alpine:3.21 sh -c '...'`) before pushing. `portable-shell.md` lists
  the GNU-vs-BSD gotchas but BusyBox is a third dialect — when the CI
  image is alpine, trust only options listed in `grep --help` on that
  image (or switch to a portable two-step: `grep -rl` + `grep -v`).
- **Recurrence**: 1

### 2026-04-20 — Fixed justfile recipe, forgot the CI had its own inlined copy

- **What**: `lint:claude-md` CI job failed on MR 360 flagging
  `just-commands-reference.md` as orphan. Fixed the `check-claude-md`
  recipe in `justfile` (include `.claude/docs/` as search root), pushed,
  expected CI to pass. CI didn't even re-run because my change didn't
  touch the paths in the job's `rules: changes:` filter — and the CI
  script is a copy-paste of the recipe inlined directly in
  `.gitlab-ci.yml`, not a `just check-claude-md` call.
- **Trigger**: Self-caught by reading `.gitlab-ci.yml` after the new
  push failed to produce a pipeline.
- **Root cause**: Assumed the CI invoked the just recipe. Didn't grep
  `.gitlab-ci.yml` for the failure message before "fixing" the recipe.
- **Lesson**: When a CI job fails, first `grep` the failing string in
  `.gitlab-ci.yml` — inline scripts are a common pattern here. Before
  claiming a CI fix is done, verify the job's `rules: changes:` filter
  will actually trigger on the committed paths.
- **Recurrence**: 1

### 2026-04-20 — Auto-link regex matched its own marker inside commit bodies

- **What**: Wrote a regex to strip a previous auto-generated "## Related
  MRs (auto-linked)" section from MR descriptions before re-writing it.
  The regex matched the FIRST occurrence — but the literal text
  "## Related MRs (auto-linked)" also appeared in the commit body of
  the very feature that introduced the marker. Result: the description
  was silently truncated mid-sentence after the first match.
- **Trigger**: Self-caught while inspecting the resulting MR description.
- **Root cause**: Section markers chosen from natural prose — easy to
  collide with documentation about the marker itself.
- **Lesson**: Use machine-only markers (HTML comments) for any region a
  script needs to find/replace inside human-edited content. Treat
  prose-shaped markers as user-visible labels only.
- **Recurrence**: 1

### 2026-04-27 — "Local verification" of CI script meant `--help`/`--list`, not the real flag combo

- **What**: Fixed `mutation:nightly` failure by moving `--jobs $(nproc)`
  from a GitLab variable into `before_script` (so bash would actually
  evaluate `$(nproc)`). Claimed local verification by running
  `cargo mutants --jobs '$(nproc)' --help`, `cargo mutants --list
  --in-place --exclude-re theme.rs`, and a stubbed-shell simulation.
  Pushed to `core!673`, which merged. The next scheduled pipeline
  failed in ~10s with `error: the argument '--in-place' cannot be
  used with '--jobs <JOBS>'` — cargo-mutants 26.x rejects that
  combination, and we need `--in-place` to keep
  `include_bytes!("../../../themes/...")` resolving.
- **Trigger**: User pointed it out: "this means you have not tested
  the script locally before push."
- **Root cause**: `--help` and `--list` only exercise argument parsing.
  Many tools (cargo-mutants among them) defer flag-conflict checks
  until the action actually runs, so flag-incompatibility doesn't
  surface in either probe. The shell-substitution simulation also
  passed because it never invoked the real binary.
- **Lesson**: For a CI fix, run the real command with the same flag
  set the CI job will use, for at least one real iteration. Ctrl-C
  after the parse/startup phase is fine — flag-conflict errors
  surface in seconds. Captured as auto-memory
  `feedback_local_verification_real_flags.md` and as a soft hook at
  `.claude/hooks/check-ci-yaml-tested.sh` (blocks `git push` of CI
  yaml unless the command line carries `CLAUDE_CI_TESTED=...`).
- **Recurrence**: 1
