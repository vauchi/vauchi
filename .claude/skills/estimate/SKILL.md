---
name: estimate
description: Estimate effort for tasks using empirical calibration from project history. Produces focused-day estimates, blocker buffers, and confidence intervals. Use when planning new features, phases, or sprints.
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Estimation Skill

Produce calibrated effort estimates using empirical data from this project's history.

## Usage

- `/estimate <task description>` — estimate a single task
- `/estimate --plan <plan-file>` — estimate all incomplete items in a plan
- `/estimate --audit <plan-file>` — compare plan estimates against actuals (post-hoc)
- `/estimate --velocity` — show current velocity metrics

## Calibration Data (from 2026-03-16 audit)

**Source**: `_private/docs/investigations/measurements/2026-03-16-estimation-accuracy-audit.md`

Based on 61 days of data across 25 repos, 1,163+ core commits, 42 completed plans, and 31 resolved problem records:

### Active Coding Calibration

| Task category | Naive estimate | Empirical actual | Multiplier |
|---------------|---------------|-----------------|------------|
| Trivial (single function, config change) | 1 day | 1 day | 1.0x |
| Small (single module, test suite) | 3 days | 1 day | 0.33x |
| Medium (cross-module, API change) | 1 week | 1-2 days | 0.2-0.3x |
| Large (new platform repo, architecture) | 6-8 weeks | 3-7 days | 0.1-0.15x |

### Blocker Buffer Rules

| Dependency depth | Buffer to add |
|-----------------|---------------|
| No blockers | +0 days |
| Blocked on 1 upstream MR | +3-7 days calendar |
| Blocked on ADR/architecture decision | +1-3 weeks calendar |
| Blocked on external (CI infra, app store) | +1-4 weeks calendar |
| Multiple chained blockers | multiply buffers |

### Completion Percentage Bias

Self-reported completion percentages are **pessimistic by 15-35%**. When auditing:
- If plan says "~40%" → likely ~60-75% actual
- If plan says "~80%" → likely ~95% actual (but remaining 5-20% may be blocked)
- If plan says "~95%" → likely done except for blockers

## Estimation Workflow

### Step 1: Classify the Task

Determine category (trivial/small/medium/large) based on:
- Number of files touched (1 → trivial, 2-5 → small, 5-15 → medium, 15+ → large)
- Number of repos touched (1 → reduce size, 2+ → increase size)
- Whether shared architecture exists (AppEngine/WorkflowEngine → reduce by 60-80%)
- Whether it's greenfield vs modification (modification → reduce by 50%)

### Step 2: Estimate Active Coding Days

1. Start with naive gut estimate
2. Apply calibration multiplier from table above
3. Adjust for:
   - **TDD overhead**: +30% (but prevents rework, so net positive)
   - **Cross-repo coordination**: +50% per additional repo
   - **New platform/toolchain**: +100% first time, +0% subsequent
   - **Crypto/security code**: +50% (review, property tests, audit)

### Step 3: Identify Blockers

Search for dependencies:
```bash
# Check if task depends on open MRs
just gitlab mr-list [repo]

# Check if task depends on ADRs or architectural decisions
grep -r "BLOCKED" _private/docs/planning/todo/

# Check dependency graph in master plan
grep "LAYER" _private/docs/planning/master-plan.plan.md
```

### Step 4: Produce Estimate

Output format:
```
## Estimate: <task name>

**Active coding**: X focused days (Y-Z range)
**Blocker buffer**: +N days (blocked on: ...)
**Calendar estimate**: X+N days (best case) to X+N*2 days (worst case)
**Confidence**: high/medium/low

**Assumptions**:
- ...

**Risks**:
- ...

**Comparable past work**:
- <similar completed task> took <N> days
```

### Step 5: Record for Future Calibration

After completion, update the estimate:
```markdown
**Actual active coding**: X days
**Actual calendar time**: Y days
**Accuracy**: estimate/actual = Zx
**Lesson**: ...
```

## Velocity Reference (as of 2026-03-16)

- **Core commits/week**: 29-204 (median ~130, accelerating)
- **Peak commit days**: 44-68 commits/day during burst coding
- **Problem resolution rate**: ~0.9 problems/day
- **Plan completion rate**: ~1 plan/day (42 plans in ~45 days)
- **Feature burst duration**: 1-3 days of intense work, then move on
- **Test count growth**: 2,843 → 10,975+ Rust tests over 61 days

## Anti-Patterns to Avoid

1. **Don't estimate in weeks** — use "focused days" to avoid conflating effort with calendar time
2. **Don't sum sub-estimates linearly** — shared architecture creates 60-80% reuse across platform repos
3. **Don't ignore blockers** — they dominate calendar time for the last 20% of work
4. **Don't add precision to large estimates** — "3-7 days" is more honest than "5.5 days"
5. **Don't forget the velocity curve** — current velocity is 2-3x higher than January; estimates based on old velocity are stale
6. **Don't treat percentages as linear** — 0→80% takes less calendar time than 80→100% due to blockers

## Integration with Other Skills

- Use `just risk` to surface blockers, stalled plans, and recurring failure patterns
- Use `/plan-audit` to verify completion percentages before estimating remaining work
- Use `/estimate --audit` after completing work to feed accuracy data back
- Reference `_private/docs/investigations/measurements/2026-03-16-estimation-accuracy-audit.md` for full methodology
