# Docs Cleanup and Update Plan

**Date**: 2026-01-22
**Status: Done
**Scope**: Documentation structure, naming compliance, and content cleanup

## Problem Statement

The `docs/` directory has significant issues:
- **5.5% compliance** with the mandatory `YYYY-MM-DD-<name>.md` naming convention
- 69 of 73 markdown files lack date prefixes
- Metadata inconsistencies in planning workflow
- One empty file (`deployment/plan.md`)
- Conflicting/unclear file relationships
- Files in wrong workflow stages (done/ contains in-progress items)

## User Decisions

1. **architecture/** files: YES - require date prefixes
2. **diagrams/** files: NO - keep as-is (no dates, no numeric ordering change)
3. **planning/done/** format: Use DATED format going forward

## Summary of Findings

### Critical Issues (Blockers)

| Issue | Location | Impact |
|-------|----------|--------|
| Empty file | `deployment/plan.md` (0 bytes) | Confusing, serves no purpose |
| Metadata mismatch | `planning/ready-for-review/README.md` says "*(none)*" but folder has 5 files | Misleading status |
| Unclear relationship | `roadmap.md` vs `done-roadmap.md` in ready-for-review/ | Confusing workflow |
| Roadmap misplacement | `planning/ready-for-review/roadmap.md` should be `planning/roadmap.md` | Per CLAUDE.md, roadmap.md is the entry point |

### Workflow Violations Found

| File | Current Location | Status in File | Should Be |
|------|------------------|----------------|-----------|
| P6-recovery-mobile.md | done/ | "In Progress" | todo/ |
| P7-pre-production-checklist.md | done/ | Has pending items | todo/ |
| P8-github-governance.md | done/ | "Deferred" | proposals/ |
| P9-platform-requirements.md | done/ | "Proposed" | proposals/ |

### Files to Archive/Delete

| File | Action | Reason |
|------|--------|--------|
| `deployment/plan.md` | DELETE | Empty file (0 bytes) |
| `JUST_COMMANDS.md` | DELETE | Duplicates `just help`, no CI sync |
| `COVERAGE_AUTOMATION_SUMMARY.md` | DELETE | Describes unimplemented infrastructure |
| `planning/ready-for-review/done-roadmap.md` | ARCHIVE | Superseded by current roadmap.md (Jan 22) |
| `planning/done/contact-recovery.md` | ARCHIVE | Superseded, marked "Planned" but in done/ |
| `planning/done/phases-completed.md` | ARCHIVE | Historical snapshot, info now in roadmap.md |
| `project-states/2026_01_20_project_state.md` | ARCHIVE | Outdated assessment (3 days old), superseded |

## Proposed Actions

### Phase 1: Immediate Fixes (Blockers)

```bash
# 1. Delete empty file
rm docs/deployment/plan.md

# 2. Move roadmap.md to correct location
mv docs/planning/ready-for-review/roadmap.md docs/planning/roadmap.md

# 3. Archive done-roadmap.md
mv docs/planning/ready-for-review/done-roadmap.md \
   docs/planning/done/2026-01-20-roadmap-feature-complete-v1.md

# 4. Delete redundant files
rm docs/JUST_COMMANDS.md
rm docs/COVERAGE_AUTOMATION_SUMMARY.md
```

Update `planning/ready-for-review/README.md` to reflect actual contents (2 sync-related files).

### Phase 2: Fix Workflow Violations

```bash
# Move files to correct workflow stages
mv docs/planning/done/P6-recovery-mobile.md \
   docs/planning/todo/2026-01-22-P6-recovery-mobile.md

mv docs/planning/done/P7-pre-production-checklist.md \
   docs/planning/todo/2026-01-22-P7-pre-production-checklist.md

mv docs/planning/done/P8-github-governance.md \
   docs/planning/proposals/2026-01-22-P8-github-governance.md

mv docs/planning/done/P9-platform-requirements.md \
   docs/planning/proposals/2026-01-22-P9-platform-requirements.md
```

### Phase 3: Archive Historical Files

Create `docs/planning/archived/` for historical reference:

```bash
mkdir -p docs/planning/archived

mv docs/planning/done/contact-recovery.md \
   docs/planning/archived/2026-01-20-contact-recovery.md

mv docs/planning/done/phases-completed.md \
   docs/planning/archived/2026-01-20-phases-completed.md

mv docs/project-states/2026_01_20_project_state.md \
   docs/planning/archived/2026-01-20-project-assessment.md

# Remove empty project-states directory
rmdir docs/project-states
```

### Phase 4: Add Date Prefixes

**architecture/** (13 files) - Add `2026-01-22-` prefix:
- api.md → 2026-01-22-api.md
- cryptography.md → 2026-01-22-cryptography.md
- data-models.md → 2026-01-22-data-models.md
- decisions.md → 2026-01-22-decisions.md
- device-linking.md → 2026-01-22-device-linking.md
- exchange-protocol.md → 2026-01-22-exchange-protocol.md
- relay.md → 2026-01-22-relay.md
- schema.md → 2026-01-22-schema.md
- security.md → 2026-01-22-security.md
- storage.md → 2026-01-22-storage.md
- sync.md → 2026-01-22-sync.md
- tech-stack.md → 2026-01-22-tech-stack.md
(README.md is exempt)

**planning/done/** - Rename to dated format:
- 01-proximity-verification.md → 2026-01-20-proximity-verification.md
- 02-test-infra.md → 2026-01-20-test-infra.md
- 03-qr-transfer.md → 2026-01-20-qr-transfer.md
- 04-device-linking.md → 2026-01-20-device-linking.md
- 05-sync-updates.md → 2026-01-20-sync-updates.md
- 11-monorepo-split.md → 2026-01-20-monorepo-split.md
- 14-message-delivery-implementation.md → 2026-01-21-message-delivery-implementation.md
- 17-onboarding-experience.md → 2026-01-21-onboarding-experience.md

**planning/todo/** - Rename to dated format:
- 06-cross-platform-e2e.md → 2026-01-20-cross-platform-e2e.md
- 07-relay-persistence.md → 2026-01-20-relay-persistence.md
- 08-android-app.md → 2026-01-20-android-app.md
- 09-ios-app.md → 2026-01-20-ios-app.md
- 10-desktop-app.md → 2026-01-20-desktop-app.md
- 12-ci-cd.md → 2026-01-20-ci-cd.md
- 13-monitoring.md → 2026-01-20-monitoring.md
- 15-security-hardening.md → 2026-01-20-security-hardening.md
- 16-documentation.md → 2026-01-20-documentation.md
- 18-platform-edge-cases.md → 2026-01-20-platform-edge-cases.md
- e2e-test-checklist.md → 2026-01-20-e2e-test-checklist.md

**Other directories** - Add date prefixes:
- deployment/relay-production.md → 2026-01-22-relay-production.md
- development/ai-assisted-coding.md → 2026-01-22-ai-assisted-coding.md
- development/testing.md → 2026-01-22-testing.md
- testing/CROSS_PLATFORM_E2E.md → 2026-01-22-cross-platform-e2e.md
- legal/privacy-policy.md → 2026-01-22-privacy-policy.md

**Root level** - Add date prefixes (non-exempt files):
- aha-moments.md → 2026-01-22-aha-moments.md
- faq.md → 2026-01-22-faq.md
- MANUAL_TESTING_GUIDE.md → 2026-01-22-manual-testing-guide.md
- PROJECT_SUMMARY.md → 2026-01-22-project-summary.md
- SECURITY_AUDIT.md → 2026-01-22-security-audit.md
- TDD_RULES.md → 2026-01-22-tdd-rules.md
- THREAT_ANALYSIS.md → 2026-01-22-threat-analysis.md
- VERSIONING.md → 2026-01-22-versioning.md
- user-guide.md → 2026-01-22-user-guide.md

### Phase 5: Update Naming Policy

Update root `/CLAUDE.md` with clarified naming policy:

```markdown
## Docs naming

All files in `docs/` must be prefixed with date: `YYYY-MM-DD-<name>.md`

**Exceptions (no date required):**
- README.md files (standard convention)
- CLAUDE.md (tooling integration)
- CONTRIBUTING.md (standard convention)
- diagrams/*.md (numbered for ordering)
```

### Phase 6: Update docs/CLAUDE.md

Sync `docs/CLAUDE.md` with the updated structure:
- Add `archived/` to planning workflow
- Update planning workflow description
- Reference the naming convention

### Phase 7: CI Enforcement

Update `scripts/check-doc-naming.sh`:
1. Add exceptions list (README.md, CLAUDE.md, CONTRIBUTING.md, diagrams/)
2. Integrate into CI pipeline
3. Add to pre-commit hooks

## Final Directory Structure

```
docs/
├── README.md
├── CLAUDE.md
├── CONTRIBUTING.md
├── 2026-01-22-*.md (root docs with dates)
├── architecture/
│   ├── README.md
│   └── 2026-01-22-*.md (all dated)
├── deployment/
│   └── 2026-01-22-relay-production.md
├── development/
│   └── 2026-01-22-*.md
├── diagrams/
│   ├── README.md
│   └── 01-04-*.md (numeric, exempt)
├── legal/
│   └── 2026-01-22-privacy-policy.md
├── planning/
│   ├── README.md
│   ├── roadmap.md (single source of truth)
│   ├── proposals/
│   │   └── 2026-01-22-*.md
│   ├── todo/
│   │   └── 2026-01-*-*.md
│   ├── ready-for-review/
│   │   └── 2026-01-21-*.md
│   ├── done/
│   │   └── 2026-01-*-*.md
│   └── archived/
│       └── 2026-01-20-*.md (historical reference)
├── postmortems/
│   └── 2026-01-21-*.md (already compliant)
├── testing/
│   └── 2026-01-22-cross-platform-e2e.md
└── scripts/
    └── check-doc-naming.sh
```

## Success Criteria

- [x] No empty files in docs/ (deleted deployment/plan.md)
- [x] roadmap.md at `docs/planning/roadmap.md`
- [x] planning/ready-for-review/README.md reflects actual state
- [x] All workflow violations fixed (P6-P9 in correct stages)
- [x] Naming policy clarified in CLAUDE.md
- [x] All non-exempt files have date prefixes (Phase 4 complete)
- [x] archived/ folder created with historical docs
- [x] check-doc-naming.sh enforced in CI
- [x] Redundant files deleted (JUST_COMMANDS.md, COVERAGE_AUTOMATION_SUMMARY.md)

## Summary

| Metric | Before | After |
|--------|--------|-------|
| Total files | 74 | ~65 |
| Date-compliant | 4 (5.5%) | ~60 (92%) |
| Empty files | 1 | 0 |
| Workflow violations | 4 | 0 |
| Archived files | 0 | 4 |
