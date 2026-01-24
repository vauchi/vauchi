# Planning Proposals

Draft plans awaiting user review.

## Naming Convention

for documents in ./planning
```
YYYY-MM-DD-<descriptive-name>.md
```

Example: `2026-01-21-websocket-reconnection.md`

## Workflow

```
proposals/ → todo/ → ready-for-review/ → done/
   │           │            │              │
 Draft      Accepted    Implemented    Approved
```

1. Claude creates proposal here when planning significant work
2. User reviews and provides feedback
3. If accepted → move to `../todo/` with numbered prefix
4. Update `../roadmap.md` with entry
5. After implementation → move to `../ready-for-review/`
6. After user approval → move to `../done/`

## Alert Threshold

If 5+ proposals accumulate, Claude will alert the user to review them.

## Current Proposals

*(none)*
