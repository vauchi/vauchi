# Problem: Need single source of truth for core principles and philosophy

## Status: done

## Problem Statement

The project lacks a single, authoritative document defining core principles and philosophy. These principles are referenced in the Problem Workflow validation step ("Validate solutions against Core Principles, Culture, Current Implementation, Features") but are not formally documented anywhere.

## Origin

- **Source**: Discussion during Problem Workflow adoption
- **Date Created**: 2026-01-23

## Impact

- **Validation inconsistency**: Without documented principles, solution validation is subjective
- **Onboarding difficulty**: New contributors don't know what the project values
- **Decision drift**: Principles may shift over time without a stable reference
- **AI assistance**: Claude cannot properly validate solutions against undocumented principles

## Artifacts

- [x] Investigation document - `investigation.md`
- [x] Knowledge documents - Not needed (internal synthesis only)
- [x] Rejected solutions - `rejected-solutions.md`
- [x] Implementation plan - `implementation-plan.md`
- [x] Retrospective - `retrospective.md`

## Implementation

- Created `docs/2026-01-23-PRINCIPLES.md` with:
  - Core value statement (3 commitments)
  - 5 principle categories with concise statements
  - Links to detailed documentation
  - Usage guidelines for validation
- Updated `CLAUDE.md` to reference PRINCIPLES.md in MANDATORY section
- Updated `docs/CLAUDE.md` key documents list

## Investigation Questions

1. What principles are currently implied across existing docs?
2. What should be included? (technical principles, privacy philosophy, UX values, etc.)
3. Where should this document live?
4. How should it be structured?

## Child Problems

(To be populated from retrospective)

## Links

- Problem Workflow: `docs/2026-01-23-problem-to-solution-flow.md`
