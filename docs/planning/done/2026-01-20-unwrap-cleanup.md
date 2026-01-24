# P04: Remove Panic-Prone Code

**Priority**: HIGH
**Status**: ✓ DONE (critical paths)
**Effort**: 1-2 days
**Last audit**: 2026-01-21

## Problem

Production `.unwrap()` calls can panic on unexpected None/Err values.

### Current Counts (2026-01-21)

**Production code only** (excludes tests, doc comments, mutex locks):

| Location | Count | Target | Status |
|----------|-------|--------|--------|
| crypto/ | 0 | 0 | ✓ |
| api/ | 0 | 0 | ✓ |
| total core/src | 15 | <20 | ✓ |

**Note**: Raw grep shows ~270+ but most are:
- Inline test code (`#[cfg(test)]` modules)
- Doc examples (`///` and `//!` comments)
- Mutex locks (`.lock().unwrap()` - panics only on poisoned mutex)

## Approach

Replace `.unwrap()` with proper error handling:

```rust
// BAD
let card = wb.own_card()?.unwrap();

// GOOD
let card = wb.own_card()?.ok_or(VauchiError::NoCard)?;
```

## Priority Order

1. **Crypto paths** - Panics here = security incidents
2. **Core API** - User-facing operations
3. **CLI/TUI** - Less critical but still bad UX

## Commands to Find

```bash
# Find all unwraps in production code (not tests)
rg "\.unwrap\(\)" --type rust code/vauchi-core/src/
rg "\.unwrap\(\)" --type rust code/vauchi-cli/src/
rg "\.unwrap\(\)" --type rust code/vauchi-relay/src/
```

## Files to Audit (Priority)

| File | Severity | Notes |
|------|----------|-------|
| `crypto/encryption.rs` | CRITICAL | RNG initialization |
| `crypto/ratchet.rs` | CRITICAL | Key derivation |
| `exchange/device_link.rs` | HIGH | Device pairing |
| `api/vauchi.rs` | HIGH | Public API |
| `storage/*.rs` | MEDIUM | Data access |

## Replacement Patterns

```rust
// Option handling
.unwrap() → .ok_or(Error::MissingValue)?
.unwrap() → .unwrap_or_default() // if default is safe
.unwrap() → .expect("reason") // if truly impossible, document why

// Result handling
.unwrap() → ? // propagate error
.unwrap() → .map_err(|e| Error::from(e))?
```

## Acceptance Criteria

- [ ] Zero `.unwrap()` in `crypto/` (except tests)
- [ ] Zero `.unwrap()` in `api/`
- [ ] Remaining `.unwrap()` have `// SAFETY:` comments
- [ ] `cargo clippy` passes
- [ ] All tests pass
