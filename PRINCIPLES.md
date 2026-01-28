<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

<!-- SSOT: This is the single source of truth for Vauchi principles and philosophy -->
# Vauchi Principles

**The single source of truth for core principles and philosophy.**

All solutions must be validated against these principles before implementation.

---

## Core Value Statement

Vauchi is built on three interlocking commitments:

### 1. Privacy is a right, not an option

All design starts with: *"How would we build this if users were our only concern?"*

- E2E encryption for all communications
- Zero-knowledge relay (sees only encrypted blobs)
- No tracking, analytics, or telemetry
- User owns and controls their data

### 2. Trust is earned in person

Human recognition is the security anchor, not passwords or platforms.

- QR exchange with physical proximity verification
- No accounts or registration (device IS the identity)
- Social vouching for recovery (people you've actually met)
- No trust-on-first-use, no platform-mediated relationships

### 3. Quality comes from rigorous methodology

Confidence through discipline, not hope.

- Test-Driven Development (TDD) is mandatory
- Problem-first workflow with full traceability
- Threat modeling drives security decisions
- No hacks, no tech debt, no ignored tests

---

## Principle Categories

### Privacy Principles

| Principle | Statement |
|-----------|-----------|
| **User Ownership** | All data stored locally on device, encrypted, under user control |
| **Zero Knowledge** | Relay cannot decrypt content; sees only encrypted blobs and metadata |
| **No Harvesting** | No analytics, telemetry, location tracking, or advertising IDs |
| **No Sharing** | User data never shared with third parties |
| **Selective Visibility** | Users control per-field, per-contact visibility |

**Details**: [THREAT_ANALYSIS.md](docs/2026-01-22-THREAT_ANALYSIS.md), [privacy-policy.md](docs/legal/2026-01-22-privacy-policy.md)

### Security Principles

| Principle | Statement |
|-----------|-----------|
| **Proximity Required** | QR + BLE/NFC/ultrasonic prevents remote harvesting |
| **Audited Crypto Only** | `ring` crate exclusively; no custom cryptography |
| **Forward Secrecy** | Double Ratchet ensures past messages safe if keys compromised |
| **Memory Safety** | Rust enforces safety; no unsafe in crypto paths |
| **Defense in Depth** | Multiple layers: encryption, signing, verification |

**Details**: [security.md](docs/architecture/2026-01-22-security.md), [decisions.md](docs/architecture/2026-01-22-decisions.md), [THREAT_ANALYSIS.md](docs/2026-01-22-THREAT_ANALYSIS.md)

### Technical Principles

| Principle | Statement |
|-----------|-----------|
| **TDD Mandatory** | Red→Green→Refactor. Test FIRST. No exceptions |
| **90%+ Coverage** | For vauchi-core; real crypto in tests (no mocking) |
| **Rust Core** | Memory safety, no GC, cross-platform compilation |
| **Clean Dependencies** | vauchi-core standalone; downstream repos use git deps |
| **Gherkin Traceability** | Features in `features/*.feature` drive test writing |

**Details**: [TDD_RULES.md](docs/2026-01-22-TDD_RULES.md), [decisions.md](docs/architecture/2026-01-22-decisions.md)

### UX Principles

| Principle | Statement |
|-----------|-----------|
| **Complexity Hidden** | Users see "scan QR, contact added"; encryption invisible |
| **In-Person Trust** | Human recognition is the security anchor |
| **Offline-First** | QR exchange works without connectivity |
| **Portable Identity** | No vendor lock-in; restore from backup, switch devices |
| **Cross-Platform Consistency** | Same experience on iOS, Android, desktop |

**Details**: [aha-moments.md](docs/2026-01-22-aha-moments.md), [user-guide.md](docs/2026-01-22-user-guide.md)

### Process Principles

| Principle | Statement |
|-----------|-----------|
| **Problem-First** | Every task starts as a problem; ideas restated as problems |
| **Artifacts Accumulate** | Investigation, rejected solutions, retrospectives attached to problems |
| **No Wasted Rejections** | Archive rejected solutions with reasoning |
| **Small Atomic Commits** | After each green, after each refactor |
| **Retrospective Required** | Learn from every completed problem |

**Details**: [problem-to-solution-flow.md](docs/2026-01-23-problem-to-solution-flow.md)

---

## Using These Principles

### For Solution Validation

When evaluating a proposed solution, check:

1. **Does it align with Core Principles?** (Privacy, Trust, Quality)
2. **Does it fit the Culture?** (Process Principles)
3. **Is it compatible with Current Implementation?** (Technical Principles)
4. **Does it support existing Features?** (UX Principles)

If a solution conflicts with any principle, it must be rejected with documented reasoning.

### For Decision Making

When facing a design decision:

1. Start with the user's perspective
2. Assume adversarial conditions (what could go wrong?)
3. Choose the option that best upholds all three core values
4. Document the decision and rationale

### For New Contributors

Read these principles before contributing. They are non-negotiable. If you disagree with a principle, open a problem record to discuss changing it—don't ignore it.

---

## Amending Principles

Principles can be amended, but only through the Problem Workflow:

1. Create a problem record explaining why the principle should change
2. Investigate impact across codebase and documentation
3. Validate the change against remaining principles
4. Implement with full retrospective

Principles are not immutable, but changes must be deliberate and documented.
