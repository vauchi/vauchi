# CLAUDE.md - Documentation

Project documentation, architecture, planning, and guides.

## Purpose

This directory contains all project documentation outside of code comments and READMEs.

## Structure

| Path | Content |
|------|---------|
| `architecture/` | System design, data flows, component diagrams |
| `knowledge/` | External research documents (persisted learnings) |
| `planning/` | Problem records, proposals, retrospectives, post-mortems |
| `deployment/` | Deployment guides and configs |
| `development/` | Developer setup and contribution guides |
| `legal/` | Privacy policy, terms, licenses |

## Editing Rules

- Use GitHub-flavored Markdown
- All files must be prefixed with date: `YYYY-MM-DD-<name>.md`
- Keep files focused on single topics
- Include diagrams where helpful (Mermaid or ASCII)

## Problem Workflow (MANDATORY)

**All work follows the Problem to Solution Flow.**
See: `2026-01-23-problem-to-solution-flow.md`

```
intake → investigating → planning → implementing → testing → done
```

Key directories:
- `planning/problems/` - Problem records with all artifacts
- `planning/investigations/` - Problem analysis
- `planning/retrospectives/` - Post-completion learnings
- `planning/post-mortems/` - Failure analysis
- `knowledge/` - External research

## Git Workflow

This repo (`vauchi/docs`) follows the same branch strategy as other Vauchi repos.

### Branch Types

| Type | Use Case | Example |
|------|----------|---------|
| `feature/` | New feature planning | `feature/remote-content-updates` |
| `investigation/` | Research documents | `investigation/webrtc-feasibility` |
| `refactor/` | Restructuring docs | `refactor/planning-structure` |
| `bugfix/` | Fixing doc errors | `bugfix/outdated-api-docs` |

### Cross-Repo Changes

When documentation accompanies code changes in other repos, use the **same branch name** across repos:

```bash
# Example: feature spanning docs + features + core
git -C _docs checkout -b feature/remote-content-updates
git -C features checkout -b feature/remote-content-updates
git -C core checkout -b feature/remote-content-updates
```

### Linking MRs

In the MR description, link to related MRs in other repos:

```markdown
## Related MRs

- vauchi/features!42 - Gherkin specs for this feature
- vauchi/core!78 - Implementation
```

Use format: `{group}/{project}!{mr_number}`

This ensures reviewers can see the full scope of cross-repo changes.

## Key Documents

- [PRINCIPLES.md](../PRINCIPLES.md) - **Core principles** (single source of truth - at repo root)
- `2026-01-23-problem-to-solution-flow.md` - **The workflow** (read this first)
- `2026-01-22-TDD_RULES.md` - Test-driven development requirements
- `2026-01-22-THREAT_ANALYSIS.md` - Security threat model
- `2026-01-22-SECURITY_AUDIT.md` - Security review findings
