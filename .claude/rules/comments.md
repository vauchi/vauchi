---
paths:
  - "**/*.rs"
  - "**/*.swift"
  - "**/*.kt"
  - "**/*.cpp"
  - "**/*.h"
  - "**/*.hpp"
  - "**/*.cs"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.py"
---
## Code Comments (MANDATORY)

**Code should self-document wherever possible.** A comment is a cost: it
ages independently of the code, drifts toward lying, and signals that the
code failed to say what it means. Pay that cost only when naming and
structure genuinely cannot.

### The rule

1. **Prefer naming over commenting.** Before writing a comment, try to
   delete the need for it: rename the variable, function, method, class,
   file, or folder until the code reads as the comment would have. A
   well-named symbol never goes stale; a comment does.
2. **Keep a comment only if it is strictly necessary** to explain a
   *strange or uncommon* pattern — something a competent reader of this
   codebase would not expect from the code alone (a non-obvious
   workaround, an external constraint, a deliberate deviation, a subtle
   invariant, an ADR-mandated choice).
3. **When a comment is necessary, state the *why*, not the *how*.** The
   code already shows *how*. The comment exists to capture intent,
   rationale, trade-off, or constraint the code cannot express — the
   reason this code is shaped this way.

### Litmus test before writing a comment

- Could a rename or extraction make this comment redundant? → Do that
  instead, don't comment.
- Does the comment restate what the next line of code plainly does? →
  Delete it.
- Does it explain *why* (a decision, a constraint, a gotcha, a link to an
  ADR/issue)? → Keep it, make it concise.

### How a comment earns its keep

The litmus above governs *writing*. Keeping is the inverse problem: a
sweep, refactor, or reviewer must be able to tell a load-bearing comment
from noise **without re-deriving the author's judgment** — otherwise good
comments rot and bad ones survive. A comment earns its keep by passing
two gates:

1. **Irreplaceable** — deleting it loses information that *cannot be
   recovered from the code*. "How" comments fail (the code is the
   authority on how); "why" comments pass (intent, a rejected
   alternative, an external constraint, a historical bug, an ordering
   requirement live nowhere else).
2. **Verifiable** — a reader can *check whether the claim is still true*.
   `// 7 days` asserts nothing checkable; `// escrow TTL must outlast the
   weekend re-exchange window (ADR-035)` can be validated and falsified.

To make a keep *durable* instead of re-litigated every sweep, carry an
**anchor** — something that makes the justification legible:

| Anchor | Example | Bright-line? |
|---|---|---|
| External reference | `ADR-035`, `#1284`, `RFC 9180`, `CVE-…`, problem-record link | yes (greppable) |
| Sanctioned prefix | `// SAFETY:`, `// INVARIANT:`, `// WHY:` | yes (greppable) |
| Falsifiable phrasing | contains *because / otherwise / so that / not X because* | mostly |
| Bare assertion | `// store total on first chunk` | no — pure judgment |

**Sweep rule (bright line).** A sweep may delete a comment only if it
restates the adjacent statement **and** carries no anchor (no external
ref, no sanctioned prefix, no *because/otherwise/so-that* clause).
Anything anchored is keep-by-rule, not keep-by-judgment. When you keep an
unanchored "why" because you *know* the rationale, prefer to add the
anchor so the next reader doesn't have to know it too.

### Examples

```rust
// BAD — restates the code (the "how"); naming already carries it.
// increment the retry counter by one
retries += 1;

// BAD — comment compensates for a poor name.
// the number of days the token stays valid
let n = 1;

// GOOD — name carries the meaning, no comment needed.
let token_validity_days = 1;

// GOOD — explains a non-obvious "why" the code cannot express.
// Daily rotation: stable mailbox tokens are linkable across days (ADR-029).
let token = rotating_token_for(epoch);
```

### Always-allowed (not subject to this rule)

- **Doc comments** (`///`, `//!`, Swift `///`, KDoc, docstrings) that
  form the public/library API contract — these are documentation, not
  inline narration. Still prefer *why/intent* over restating signatures.
- **License/SPDX headers**, lint directives (`#[allow(...)]`,
  `// clippy::`), codegen markers, and `// SAFETY:` justifications for
  `unsafe` (these are *why* by construction).
- **`TODO`/`FIXME`** with an issue or problem-record reference.

Full rationale and worked examples:
`_private/docs/reference/2026-06-08-code-comment-rule.md`
