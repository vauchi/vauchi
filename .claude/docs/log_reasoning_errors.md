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
