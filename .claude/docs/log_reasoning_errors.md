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
