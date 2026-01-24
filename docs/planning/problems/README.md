# Problem Records

This directory contains **Problem Records** - the central tracking unit for all work in the project.

## What is a Problem Record?

A Problem Record tracks a problem from inception to completion, accumulating all artifacts along the way. Every piece of work starts as a problem (ideas are restated as problems).

## Directory Structure

Each problem gets its own directory:

```
problems/
└── YYYY-MM-DD-problem-slug/
    ├── README.md              # Problem description, status, links
    ├── knowledge/             # Attached knowledge docs (or links)
    ├── investigation.md       # Problem analysis
    ├── rejected-solutions.md  # Solutions that didn't pass validation
    ├── implementation-plan.md # Approved solution plan
    ├── retrospective.md       # Post-completion learnings
    └── post-mortem.md         # If unforeseen errors occurred (optional)
```

## Problem Lifecycle

| Status | Description |
|--------|-------------|
| `intake` | Problem just created, awaiting discussion |
| `investigating` | Researching the problem, gathering knowledge |
| `planning` | Solution approved, planning implementation |
| `implementing` | Writing specs, features, tests, and code |
| `testing` | All code written, running final verification |
| `done` | Problem solved, retrospective complete |
| `archived` | Not a real problem, or cannot be solved now |

## Creating a New Problem

1. Create directory: `YYYY-MM-DD-problem-slug/`
2. Create `README.md` using template below
3. Follow the [Problem to Solution Flow](../2026-01-23-problem-to-solution-flow.md)

## Problem README Template

```markdown
# Problem: [Title]

## Status: intake

## Problem Statement

[Clear description of the problem. If this started as an idea, explain why it's actually a problem.]

## Origin

- **Source**: [How was this discovered? User feedback, retrospective, post-mortem, idea, etc.]
- **Parent Problem**: [Link to parent problem if spawned from retrospective/post-mortem]
- **Date Created**: YYYY-MM-DD

## Impact

[Why does this matter? Who is affected?]

## Artifacts

As the problem progresses, artifacts are added here:

- [ ] Knowledge documents
- [ ] Investigation document
- [ ] Rejected solutions (with reasoning)
- [ ] Implementation plan
- [ ] Gherkin feature: `features/xxx.feature`
- [ ] E2E tests: `e2e/tests/xxx`
- [ ] Retrospective
- [ ] Post-mortem (if needed)

## Child Problems

[Links to problems spawned from this one's retrospective or post-mortem]

## Links

- Implementation PR:
- Related issues:
```

## When Complete

When a problem is solved:
1. Ensure retrospective is written
2. Update status to `done`
3. Move directory to `../done/` (or link from done/)
4. Spawn any child problems identified in retrospective

## See Also

- [Problem to Solution Flow](../../2026-01-23-problem-to-solution-flow.md) - The complete workflow
- [Knowledge Documents](../../knowledge/) - Shared research
- [Retrospectives](../retrospectives/) - Shared learnings
- [Post-Mortems](../post-mortems/) - Failure analysis
