---
name: problem-workflow
description: Create and manage problem records following the mandatory Problem to Solution Flow
disable-model-invocation: true
---

Start or advance a problem record following the mandatory Problem to Solution Flow. $ARGUMENTS describes the problem or references an existing problem slug.

See also: `docs/2026-01-23-problem-to-solution-flow.md`

## Problem Lifecycle

```
intake → investigating → planning → implementing → testing → done (or archived)
```

## Creating a New Problem

1. **Create problem directory**: `_private/docs/problems/YYYY-MM-DD-<problem-slug>/`

2. **Create README.md** with:
   ```markdown
   # Problem: <Title>

   **Status**: intake
   **Created**: YYYY-MM-DD
   **Author**: <user>

   ## Problem Statement
   <Clear description of the problem. Ideas must be restated as problems.>

   ## Context
   <Why this matters, what triggered it>

   ## Success Criteria
   <How we know this is solved>
   ```

3. **Ask the user**: Is this actually a problem worth solving? If no → archive with learnings.

## Advancing an Existing Problem

Based on current status, guide to the next step:

### intake → investigating
- Research the problem, identify possible solutions
- If external knowledge needed → create `_private/docs/knowledge/YYYY-MM-DD-topic.md`
- Write `investigation.md` in the problem directory

### investigating → planning
- Validate solutions against `PRINCIPLES.md`:
  - Core Principles (Privacy, Trust, Quality)
  - Culture (Process Principles)
  - Current Implementation (Technical Principles)
  - Existing Features (UX Principles)
- Archive rejected solutions in `rejected-solutions.md` with reasoning
- Write `implementation-plan.md`

### planning → implementing
- Write Gherkin feature → `features/*.feature`
- Write E2E tests → `e2e/tests/`
- Implement in strict TDD: Red → Green → Refactor

### implementing → testing
- All tests must be green
- Manual verification against success criteria

### testing → done
- Write `retrospective.md`
- Spawn child problems from retrospective learnings
- Move planning doc from `_private/docs/planning/todo/` to `done/`

## On Errors/Regressions

If unforeseen errors occur during implementation:
1. Write `post-mortem.md` analyzing root cause
2. Distill new problem descriptions from post-mortem
3. New problems feed back into the workflow

## Directory Structure

```
_private/docs/problems/YYYY-MM-DD-slug/
├── README.md                 # Status, description, links
├── investigation.md
├── rejected-solutions.md
├── implementation-plan.md
├── retrospective.md
└── post-mortem.md            # If needed
```
