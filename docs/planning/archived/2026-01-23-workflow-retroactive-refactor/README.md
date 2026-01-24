# Problem: Should we retroactively refactor existing work to follow Problem Workflow?

## Status: archived

## Problem Statement

The project adopted the Problem to Solution Workflow after significant work was already completed. Should we retroactively refactor existing documentation (`done/`, `todo/`, `ready-for-review/`) to follow the new workflow structure?

## Origin

- **Source**: Discussion during workflow adoption
- **Date Created**: 2026-01-23

## Discussion

### Current State
- Many items already in `planning/done/`, `todo/`, `ready-for-review/`
- These have implementation plans but lack: problem records, investigation docs, rejected solutions, retrospectives
- Work is in various stages of completion

### Impact of NOT Refactoring
- Historical decisions lack full context (why alternatives were rejected)
- No retrospectives capturing learnings from completed work
- Inconsistent documentation structure

### Impact of Refactoring
- Significant effort for retroactive documentation
- May slow down current in-progress work
- Historical context may be hard to reconstruct accurately

## Decision: NOT A PROBLEM - Do not refactor

### Reasoning

1. **The workflow's main value is guiding active decisions**, not documenting history
2. Retroactive problem records would be reconstructed guesses, not actual decision trails
3. Current in-progress work has momentum - disrupting it adds risk
4. The `done/` docs still provide reference value even without full problem structure

### Approach Going Forward

1. **In-progress items** (`todo/`, `ready-for-review/`) → finish as-is
2. **New work starting today** → follow Problem Workflow strictly
3. **Optional**: Write brief retrospectives for recently completed major features (if learnings are still fresh)

## Archived

This problem was discussed and determined to not require action. The decision and reasoning are captured here for future reference.
