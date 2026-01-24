# Investigation: Core Principles Single Source of Truth

## Current State

Core principles are **scattered across 10+ documents**:

| Document | Contains |
|----------|----------|
| `CLAUDE.md` | TDD, crypto library choice, coverage requirements |
| `docs/2026-01-22-TDD_RULES.md` | Three laws of TDD, testing methodology |
| `docs/2026-01-22-THREAT_ANALYSIS.md` | 35+ security threats, mitigations |
| `docs/architecture/2026-01-22-decisions.md` | 18 ADRs (technical decisions) |
| `docs/architecture/2026-01-22-security.md` | Security priorities |
| `docs/architecture/README.md` | Architectural overview |
| `docs/2026-01-22-aha-moments.md` | 23 UX philosophy moments |
| `docs/legal/2026-01-22-privacy-policy.md` | Privacy commitments |
| `docs/2026-01-23-problem-to-solution-flow.md` | Process workflow |

## Identified Principles (Synthesis)

### 1. Privacy Philosophy
- **User data ownership**: All data stored locally, encrypted, user-controlled
- **Zero-knowledge relay**: Relay sees only encrypted blobs
- **No tracking**: No analytics, telemetry, location tracking
- **No third-party sharing**: Period

### 2. Security Philosophy
- **Physical proximity required**: QR + BLE/NFC/ultrasonic verification
- **No accounts/registration**: Device IS the account
- **Forward secrecy**: Double Ratchet for message protection
- **Audited crypto only**: `ring` crate, no custom implementations

### 3. Technical Principles
- **Rust for core**: Memory safety, no GC, cross-platform
- **TDD mandatory**: Red→Green→Refactor, test FIRST
- **90%+ coverage**: For vauchi-core
- **Never mock crypto**: Real cryptographic operations in tests

### 4. UX Values
- **Complexity hidden**: Users see simple QR scan, encryption invisible
- **In-person trust model**: Human recognition is security anchor
- **Offline-first**: QR exchange works without connectivity
- **Portable identity**: No vendor lock-in

### 5. Process Values
- **Problem-first workflow**: Every task starts as a problem
- **Artifacts accumulate**: Investigation, rejected solutions, retrospectives
- **No wasted rejections**: Archive with reasoning
- **Small atomic commits**: After each green, after each refactor

### Core Value Statement (Discovered)

**Three interlocking commitments:**

1. **Privacy is a right, not an option** — E2E encryption, zero-knowledge relay, no tracking, user ownership

2. **Trust is earned in person** — QR exchange with proximity verification, social vouching for recovery

3. **Quality comes from rigorous methodology** — TDD, problem-first planning, threat modeling, full traceability

## Possible Solutions

### Solution A: Single PRINCIPLES.md document
Create `docs/PRINCIPLES.md` as the authoritative source, with all other docs referencing it.

**Pros:**
- Single location to read and understand
- Easy to reference in CLAUDE.md
- Clear authority

**Cons:**
- May duplicate content from other docs
- Risk of drift if not maintained

### Solution B: PRINCIPLES.md with links to detailed docs
Create a lightweight `docs/PRINCIPLES.md` that states principles concisely and links to detailed docs for rationale.

**Pros:**
- Single source of truth for principles
- Detailed rationale stays in specialized docs
- Less duplication

**Cons:**
- Requires following links for full context

### Solution C: Embed in CLAUDE.md
Add principles directly to CLAUDE.md so they're always loaded.

**Pros:**
- Always visible to Claude
- No extra file to maintain

**Cons:**
- CLAUDE.md becomes very long
- Mixes operational rules with philosophy
- Harder for humans to read

## Recommendation

**Solution B: PRINCIPLES.md with links**

Create `docs/2026-01-23-PRINCIPLES.md` containing:
1. Core value statement (3 commitments)
2. Principle categories with concise statements
3. Links to detailed docs for rationale
4. Update CLAUDE.md to reference it in validation step

This balances:
- Single source of truth
- Minimal duplication
- Full context available via links
- Readable by both humans and AI
