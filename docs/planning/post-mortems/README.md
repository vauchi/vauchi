# Post-Mortem Documents

This directory contains post-mortem analysis documents for unforeseen errors and regressions.

## Purpose

When implementation encounters unforeseen errors or regressions that weren't caught by initial testing:

1. Write a post-mortem document
2. Analyze what went wrong
3. Distill new problem descriptions
4. Feed problems back into the problem-to-solution flow

## Naming Convention

`YYYY-MM-DD-<incident-name>.md`

## Template

```markdown
# Post-Mortem: [Incident Name]

## Incident Summary
[Brief description of what happened]

## Timeline
- [Time]: [Event]
- [Time]: [Event]

## Root Cause Analysis
[What caused the issue]

## Impact
[What was affected]

## Detection
[How was the issue discovered]

## Resolution
[What was done to fix it]

## New Problem Descriptions
[Problems distilled from this incident]

1. **[Problem Title]**
   - Description: [...]
   - Root cause relation: [...]
   - Suggested investigation area: [...]

## Prevention
[How to prevent similar issues]

## Action Items
- [ ] [Action 1]
- [ ] [Action 2]

## Related Documents
- [Links to relevant docs]
```
