---
name: problem-workflow
description: Create and manage problem records following the mandatory Problem to Solution Flow
disable-model-invocation: true
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

Start or advance a problem record following the mandatory Problem to Solution Flow. $ARGUMENTS describes the problem or references an existing problem slug.

See also: `_private/docs/2026-01-23-problem-to-solution-flow.md`

## Problem Lifecycle

```
intake → investigating → planning → implementing → testing → done (or archived)
```

## Creating a New Problem

1. **Create problem directory**: `_private/docs/problems/YYYY-MM-DD-<problem-slug>/`

2. **Create README.md** with:
   ```markdown
   # Problem: <Title>

   | Field | Value |
   |-------|-------|
   | **Status** | intake |
   | **Priority** | critical / high / medium / low |
   | **Owner** | <person or team> |
   | **Created** | YYYY-MM-DD |
   | **Last Updated** | YYYY-MM-DD |

   ## Problem Statement
   <Clear description of the problem. Ideas must be restated as problems.>

   ## Goals (Success Criteria)
   - [ ] <Measurable criterion 1 — how do we know this is solved?>
   - [ ] <Measurable criterion 2>

   ## Containment (if critical/high)
   - **Interim mitigation**: <what was done to contain the problem>
   - **Expiry**: <when can containment be removed — link to proper fix>

   (Omit this section for medium/low priority problems.)

   ## Artifacts
   - [ ] investigation.md
   - [ ] implementation-plan.md (with rejected approaches + test strategy)
   - [ ] *.feature (draft) → promoted_to: `features/<file>.feature`
   - [ ] e2e tests
   - [ ] retrospective.md
   - [ ] post-mortem.md (if needed)

   ## Child Problems
   - PRB-YYYY-NNN: <title> (spawned from retrospective/post-mortem)
   ```

3. **Ask the user**: Is this actually a problem worth solving? If no → archive with learnings.

### Priority Levels

| Priority | Criteria | Containment? |
|----------|----------|--------------|
| `critical` | Security vulnerability, data loss, complete feature breakage | **Required** — document interim mitigation before investigating |
| `high` | Blocks other work, affects users, or regression | Recommended |
| `medium` | Improvement, non-blocking bug, or technical debt | Not needed |
| `low` | Nice-to-have, cosmetic, or future consideration | Not needed |

## Advancing an Existing Problem

Based on current status, guide to the next step:

### intake → investigating
**Gate**: Problem discussed and confirmed real. Priority assigned. Goals defined. Owner assigned. Containment documented if critical/high.
- Define success criteria (goals) — what does "solved" look like?
- If critical/high priority: document containment action (interim mitigation) before proceeding
- Research the problem, identify possible solutions
- If external knowledge needed → create docs in `knowledge/` subdirectory
- Write `investigation.md` in the problem directory (include `### References` section)

### investigating → planning
**Gate**: Root cause or opportunity identified. `investigation.md` attached with references. At least one candidate solution identified.
- Validate solutions against [Principles](https://docs.vauchi.app/about/principles/):
  - Core Principles (Privacy, Trust, Quality)
  - Culture (Process Principles)
  - Current Implementation (Technical Principles)
  - Existing Features (UX Principles)
- Write `implementation-plan.md` with mandatory sections:
  - `### Rejected Approaches` — document each rejected solution with reasoning (or "N/A — first candidate passed validation")
  - `### Test Strategy` — unit, property-based, contract, acceptance, mutation testing impact

### planning → implementing
**Gate**: Solution validated against criteria. `implementation-plan.md` attached with test strategy and rejected approaches. Draft Gherkin scenarios written.
- Create companion `plan.md` in markdown-plan syntax:
  - Extract task structure from implementation-plan.md
  - Use ordered lists for sequential phases, unordered for parallel subtasks
  - Add `@(substring)` dependencies where tasks depend on non-parent tasks
  - Validate with `just plan-validate <path>/plan.md`
- Promote Gherkin feature from problem directory → `features/*.feature`
- Record `promoted_to: features/<file>.feature` in the problem README
- Write E2E tests → `e2e/tests/`
- Implement in strict TDD: Red → Green → Refactor

### implementing → testing
**Gate**: All TDD cycles complete. Gherkin promoted with `promoted_to:` tracked. E2E tests written. All unit + E2E tests green.
- All tests must be green
- Verify against success criteria (goals)

### testing → done
**Gate**: Retrospective written evaluating against goals. Child problems spawned if needed. Success criteria verified as met.
- Write `retrospective.md` — evaluate against goals (were success criteria met?)
- Spawn child problems from retrospective learnings
- Move planning doc from `_private/docs/planning/todo/` to `done/`

## On Errors/Regressions

If unforeseen errors occur during implementation:
1. Write `post-mortem.md` analyzing root cause
2. Distill new problem descriptions from post-mortem
3. New problems feed back into the workflow

## Staleness Rules

Problems that stall erode trust in the workflow. Flag these to the user:

| Phase | Stale after | Action |
|-------|-------------|--------|
| intake | 14 days | Decide: investigate or archive |
| investigating | 30 days | Reassess priority or archive |
| planning | 30 days | Check if blocked — spawn child problem or archive |
| implementing | 30 days | Check if blocked by upstream work |

## Directory Structure

```
_private/docs/problems/YYYY-MM-DD-slug/
├── README.md                 # Status, priority, owner, goals, links
├── knowledge/                # External research (if needed)
├── investigation.md          # Problem analysis (includes ### References)
├── implementation-plan.md    # Plan (includes ### Rejected Approaches + ### Test Strategy)
├── plan.md                   # Task DAG in markdown-plan syntax
├── retrospective.md          # Post-completion (evaluates against goals)
└── post-mortem.md            # If unforeseen errors occurred
```
