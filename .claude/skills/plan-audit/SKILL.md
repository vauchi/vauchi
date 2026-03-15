---
name: plan-audit
description: Audit planning documents against actual code. Verifies percentages, task checkboxes, file references, status claims, and test counts. Use before MRs, after plan updates, or for periodic housekeeping.
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Plan Audit

Audit planning documents against actual codebase state.

## Usage

- `/plan-audit` — audit all active plans in todo/
- `/plan-audit sp-6` — audit a specific SP
- `/plan-audit --problems` — audit active problem records
- `/plan-audit --done` — check done/ for premature closures

## What It Checks

1. **Task checkboxes** — `[x]` items exist in code, `[ ]` items genuinely missing
2. **Percentages** — Count `@implemented`/`@planned` tags, not subjective estimates
3. **Test counts** — Search BOTH `tests/` AND inline `src/` `#[test]` functions
4. **File references** — Verify paths and line numbers with `ls` and `grep -n`
5. **Status claims** — Cross-check plan status, master plan, folder location, and retrospectives
6. **Stale references** — Flag archived Tauri/SolidJS/desktop refs, wrong migration versions
7. **"Core done" ≠ "Feature done"** — Report per-layer: core % | platform UI % | E2E %

## Workflow

1. Read the plan document
2. Launch `plan-auditor` agent(s) to verify claims against code
3. **Spot-check agent findings** — agents have been wrong about:
   - Test counts (missed inline tests in `src/`)
   - File existence (claimed missing when file exists)
   - Percentage methodology (inconsistent scoring)
4. Apply corrections with evidence (file:line references)
5. Commit as `docs: plan corrections from audit`
