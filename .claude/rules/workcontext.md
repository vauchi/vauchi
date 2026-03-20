---
apply: always
---

## Work Context Tracking (MANDATORY)

The file `.claude/.workcontext` tracks the current problem and workflow phase for the statusline.

### Format

```json
{"problem": "slug-from-problem-record", "phase": "implementing"}
```

Valid phases: `intake`, `investigating`, `planning`, `implementing`, `testing`, `done`

### When to update

- **Session start**: If continuing work, set to the active problem and phase
- **Problem switch**: When the user says "I'm working on X" or starts work on a different problem
- **Phase transition**: When the user says "moving to testing" or when work naturally transitions
- **Problem completion**: Set phase to `done`, then clear the file on next problem
- **No active problem**: Delete the file or set `{"problem": "", "phase": ""}`

### Rules

- The file is `.gitignore`-d (machine-local, not committed)
- Do NOT update the file on every commit — only on problem/phase changes
- When creating a new problem record, also set `.workcontext`
- The statusline reads this file to show the combined next-action indicator
