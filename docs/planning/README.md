# Planning Documentation

## Entry Point

**[roadmap.md](roadmap.md)** - Single source of truth for all planned work.

## Planning Workflow

```
                    ┌─────────────────┐
                    │   roadmap.md    │  ◄── Entry point
                    │  (top level)    │
                    └────────┬────────┘
                             │ references
                             ▼
┌─────────────┐  Accept  ┌─────────────┐  Done  ┌─────────────────┐  Approve  ┌─────────────┐
│ proposals/  │ ───────► │   todo/     │ ─────► │ ready-for-review│ ────────► │   done/     │
│   Drafts    │          │  In Progress│        │  Awaiting Review│           │  Reference  │
└─────────────┘          └─────────────┘        └─────────────────┘           └─────────────┘
```

### Steps

1. **Propose** - Create `proposals/YYYY-MM-DD-<name>.md` for significant work
2. **Accept** - User reviews; move to `todo/NN-<name>.md` with next number
3. **Roadmap** - Add entry to `roadmap.md`
4. **Implement** - Work on the plan
5. **Ready** - Implementation done; move to `ready-for-review/`
6. **Approve** - User verifies; move to `done/`

### When to Create Proposals

- New features spanning multiple files
- Infrastructure changes (CI, tooling, deployment)
- Architecture decisions
- Multi-platform implementations
- Anything taking more than a few hours

## Structure

```
planning/
├── roadmap.md             # Entry point - single source of truth
├── README.md              # This file
├── proposals/             # Draft plans awaiting review
├── todo/                  # Accepted plans in progress
│   ├── 09-e2e-testing-infrastructure.md
│   ├── 10-accessibility-i18n.md
│   └── ...
├── ready-for-review/      # Implementation done, awaiting approval
└── done/                  # Completed and approved (reference)
    ├── phases-completed.md
    └── contact-recovery.md
```

## Quick Links

### In Progress (todo/)
- [E2E Testing Infrastructure](todo/09-e2e-testing-infrastructure.md) - Multi-user, multi-device testing
- [Accessibility & i18n](todo/10-accessibility-i18n.md) - A11y and localization for all frontends
- [Monorepo Split](todo/11-monorepo-split.md) - Extract relay, cli, tui, desktop, e2e; rename code→core
- [Cross-Platform E2E](todo/06-cross-platform-e2e.md) - E2E test checklist

### Proposals (proposals/)
- *(none pending)*

### Ready for Review (ready-for-review/)
- *(none pending)*

### Reference (done/)
- [Phases Completed](done/phases-completed.md) - Development history
- [Contact Recovery Architecture](done/contact-recovery.md) - Social vouching design

## Proposal Template

When creating a proposal, include:

```markdown
# <Feature Name>

## Goal
Brief description of what this achieves.

## Current State
What exists today.

## Proposed Solution
High-level approach.

## Files to Create/Modify
- `path/to/file.rs` - Description

## Implementation Phases
1. Phase 1: ...
2. Phase 2: ...

## Verification
How to test the implementation.

## Open Questions
- Question 1?
- Question 2?
```
