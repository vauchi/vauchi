<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Audit Scope & Methodology

Source of truth for **how** audits are run: surface-claim verification,
recorded failure modes, the audit-prompt template, and the
standing-ratchet registry. Future architecture or design audits MUST
read this file for method.

The **coverage manifest** — which subsystems have been audited, when,
with what verdict, plus size metrics — lives privately at
`_private/docs/audit/2026-06-01-core-subsystem-coverage.md`. It is not
public because the "unaudited" column is a soft-spot map: publishing
which security subsystems have never been audited hands an attacker a
prioritised target list. Future audits update **that** file for coverage
and cite **this** one for method.

This split prevents the silent-blind-spot failure mode that produced the
2026-05-08 deep-modules audit (which covered 4 of 14 core subsystems and
never said so).

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

## Subsystem inventory & coverage

The per-subsystem table (files, LOC, pub-items, last-audited, verdict)
and the coverage-gap summary live privately at
`_private/docs/audit/2026-06-01-core-subsystem-coverage.md` — see the
rationale in the header. Update that file when an audit changes
coverage; anchor every count to `just public-api` output.

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

> Scope: subsystems X, Y, Z (cite the coverage table in
> `_private/docs/audit/2026-06-01-core-subsystem-coverage.md`). Anchor
> every count to the output of `just public-api <crate>`. For "shallow"
> verdicts on Rust types, distinguish between *small method bodies* and
> *small caller-visible complexity* — only the latter is shallow per
> Ousterhout. Cite file:line for every named symbol. Run `just consumers
> <symbol>` before recommending demotion. Final report must end with the
> updated row(s) for that private coverage manifest.

## Standing ratchet audits

Some audits are not one-shot deep dives — they are *quantitative
ratchets* attached to ongoing retirement programs. Each is anchored to
a baseline JSON snapshot in `_private/docs/audit/`; subsequent MRs may
only reduce the counters.

| Audit | Script | Baseline | Anchored program |
|---|---|---|---|
| Legacy mobile / Mobile\* surface | `scripts/scripts/audit-mobile-surface.sh` | [`_private/docs/audit/2026-05-11-legacy-baseline.md`](../../_private/docs/audit/2026-05-11-legacy-baseline.md) | [`pure-functional-core-program`](../../_private/docs/problems/2026-05-11-pure-functional-core-program/README.md) — see plan Phase 0 / Task 0.1 |

When adding a new ratchet audit, append a row here and link the
baseline. A standing audit without a row in this table is a blind spot
of the same shape as the 2026-05-08 deep-modules gap.

## See also

- `.claude/rules/verify-before-acting.md` — code is the source of truth.
- `.claude/rules/wire-humble.md` — why some "wide" surfaces are required.
- `.claude/rules/file-size.md` — structural exemptions (state machines etc.).
- `_private/docs/decisions/adr-021.md`, `adr-043.md`, `adr-044.md` — humble-UI architecture.
