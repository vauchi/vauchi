# Rejected Solutions

## Solution A: Single comprehensive PRINCIPLES.md

**Description**: Create a complete standalone document containing all principles with full rationale.

**Rejected because**:
- Would duplicate significant content from existing specialized docs (THREAT_ANALYSIS.md, decisions.md, TDD_RULES.md)
- Higher maintenance burden - changes would need to be made in multiple places
- Risk of drift between PRINCIPLES.md and the detailed source documents

## Solution C: Embed in CLAUDE.md

**Description**: Add all principles directly to CLAUDE.md so they're always loaded for AI context.

**Rejected because**:
- Would make CLAUDE.md excessively long (currently ~100 lines, would grow to 300+)
- Mixes operational rules (commands, structure) with philosophy
- Harder for human contributors to read and navigate
- CLAUDE.md should remain focused on "how to work" not "why we exist"
