<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Audit Scope & Coverage Manifest

Source of truth for **which subsystems have been audited, when, and how**.
Future architecture or design audits MUST cite this document and update
it. Prevents the silent-blind-spot failure mode that produced the
2026-05-08 deep-modules audit (which covered 4 of 14 core subsystems
and never said so).

## How to verify any claim about the public surface

Numbers in audit prose drift; numbers from a recipe do not. Two recipes
anchor every claim:

```bash
just public-api                 # workspace-wide snapshot, per crate + subsystem
just public-api vauchi-core     # full pub item dump for one crate
just consumers <symbol>         # downstream usage of a named export
```

Output of `just public-api` is deterministic and diffable. If a future
review claims "subsystem X has Y public items," that claim must match the
recipe output. If it doesn't, the prose is wrong (per
`verify-before-acting.md`).

`just consumers` covers every in-tree consumer (Rust frontends, native
frontends, binding crates, TS tools). Missing a consumer is what made
the 2026-05-08 audit drop `linux-qt` and `windows` entirely.

## vauchi-core subsystem inventory

Numbers are a 2026-05-08 snapshot. Re-run `just public-api` for current.

| Subsystem    | Files | LOC    | Pub-items | Last audited | Auditor / verdict |
|--------------|-------|--------|-----------|--------------|-------------------|
| api          | 36    | 11,848 | 74        | —            | unaudited         |
| avatar       | 1     | 90     | 2         | —            | unaudited         |
| backup       | 3     | 556    | 12        | —            | unaudited         |
| contact      | 12    | 2,876  | 39        | —            | unaudited         |
| contact_card | 6     | 2,501  | 29        | —            | unaudited         |
| crypto       | 11    | 2,114  | 30        | 2026-05-08   | deep ✓            |
| diagnostic   | 9     | 2,122  | 36        | —            | unaudited         |
| exchange     | 66    | 17,537 | 202       | 2026-05-08   | deep, wide surface — needs consumer-driven demotion pass |
| identity     | 4     | 1,456  | 18        | 2026-05-08   | deep ✓            |
| network      | 28    | 7,845  | 109       | —            | unaudited         |
| qr           | 2     | 424    | 5         | —            | unaudited         |
| recovery     | 3     | 1,513  | 19        | —            | unaudited         |
| social       | 2     | 260    | 2         | —            | unaudited         |
| storage      | 31    | 11,449 | 28        | —            | unaudited (likely deep — 28 pub items behind 11K LOC) |
| sync         | 7     | 3,356  | 35        | 2026-05-08   | mixed-leaning-deep ✓ |

**Coverage gap:** ~38,000 LOC of core (storage, api, network,
contact_card, recovery, diagnostic, contact, qr, backup, social, avatar)
remained unaudited in the 2026-05-08 round. Future audits must declare
their scope up-front against this table.

## Other crates

| Crate           | Files | LOC    | Pub-items | Notes |
|-----------------|-------|--------|-----------|-------|
| vauchi-cabi     | 11    | 5,164  | 16 (fn) + 140 extern | C ABI; count `#[no_mangle]` separately from `pub fn` |
| vauchi-platform | 43    | 20,778 | 254       | UniFFI bindings — surface is large by tooling constraint, not classitis |
| vauchi-protocol | 4     | 1,084  | 52        | Serde-only contract surface |

## 2026-05-08 deep-modules audit — failure modes recorded

These are the audit failure modes from this round. Future audits should
read this list before starting; subagent prompts should explicitly
forbid them.

1. **Criterion drift.** "Shallow" was operationalized as "small method
   bodies." Ousterhout's criterion is *cognitive load at the call
   site*. Newtypes with serde-validated invariants (`ExchangeId`,
   `CardSnapshot`, `ExchangeModePayload`) have small method bodies but
   carry hidden invariants — they are deep. Verdicts based on
   line-counts inside `impl` blocks are unreliable.
2. **Single-file sampling.** `vauchi-cabi` was judged from `lib.rs`
   alone (14 extern fns), missing 10 sibling files containing 126 more
   extern fns. Always run `find core/<crate>/src -name '*.rs'` first.
3. **Cfg-gating blindness.** `exchange/mod.rs:13-22` defines a
   `test_pub_mod!` macro that gates 21 sub-modules behind
   `feature = "testing"`. Counting `pub mod` lines without reading the
   surrounding macro overstates the production surface.
4. **Unfiltered `find`.** `drift-detector` was reported at "75.7 KLOC"
   because the `find` swept `node_modules`. Always exclude `node_modules`,
   `target`, `build`, `dist`, `.next`, `.gradle` for size measurements.
5. **Wrong glob.** `linux-qt` was reported as "0 files" because the
   audit globbed `*.rs`/`*.swift`/`*.kt`. linux-qt is C++. Always check
   the repo's actual file extensions before declaring it empty.
6. **Cross-subsystem hallucination.** A "crypto/merkle.rs" was cited
   that does not exist (merkle is in `sync/`). Verify file paths
   exist before quoting them.
7. **Unsupported ratios.** "75% of vauchi-platform exports are
   pass-throughs" was quoted without sampling the 58 exports. If a
   ratio is reported, list the sample.

## Audit prompt template (for future runs)

When dispatching a deep-module / architecture audit, include in the
prompt:

> Scope: subsystems X, Y, Z (cite this manifest's table). Anchor every
> count to the output of `just public-api <crate>`. For "shallow"
> verdicts on Rust types, distinguish between *small method bodies* and
> *small caller-visible complexity* — only the latter is shallow per
> Ousterhout. Cite file:line for every named symbol. Run `just consumers
> <symbol>` before recommending demotion. Final report must end with the
> updated row(s) for this manifest.

## See also

- `.claude/rules/verify-before-acting.md` — code is the source of truth.
- `.claude/rules/wire-humble.md` — why some "wide" surfaces are required.
- `.claude/rules/file-size.md` — structural exemptions (state machines etc.).
- `_private/docs/decisions/adr-021.md`, `adr-043.md`, `adr-044.md` — humble-UI architecture.
