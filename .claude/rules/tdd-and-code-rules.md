<!-- SSOT: docs/developers/tdd-rules.md (public docs site) -->

## TDD, Code Structure & Crypto (MANDATORY)

- **TDD applies to ALL repos** — Rust, Swift, Kotlin, C++, C#, Python, TypeScript. The discipline is language-agnostic:
  - Tidy→Commit→Red→Green→Commit→Refactor→Commit. Test FIRST. Tests trace to `features/*.feature`
  - **Tidy First** (optional): small structural-only improvement before starting a cycle — guard clauses, extract helper, rename, delete dead code. Own `tidy:` commit. No behavior change.
  - **Tidy Phase for large changes**: Before significant refactors, extractions, or architectural changes, plan a dedicated Phase 0 of `tidy:` commits that create clean seams — move types to shared locations, break circular deps, merge small modules, tighten visibility. Make the change easy, then make the easy change. Each tidy step is independently verifiable (`just check`).
  - Commit immediately when tests go green
  - Commit after each refactor if tests still green
- **Structure**: Keep production code and test code separate. Never mix.
- **Crypto**: See `adr-constraints.md` §Crypto — approved crates, no mocking, zeroize rules
- **Coverage**: 90%+ for vauchi-core. Measure with `just coverage`.
- **Planning**: Feature done → move `_private/docs/planning/todo/` doc to `done/`

### Language-Specific Test References

| Language | Repos | Framework | Docs |
|----------|-------|-----------|------|
| Rust | core, cli, tui, e2e, relay, linux-gtk, windows | `#[test]`, `proptest`, `insta` | `.claude/docs/test-quality-rules.md` |
| Swift | ios, macos | XCTest, SnapshotTesting | `.claude/docs/platform-bindings-rules.md` |
| Kotlin | android | JUnit4, Espresso, Compose semantics | `.claude/docs/platform-bindings-rules.md` |
| C++ | linux-qt | Google Test | — (no per-repo doc yet) |
| C# | windows | xUnit | — (no per-repo doc yet) |
| Python | linux-gtk, linux-qt | pytest, AT-SPI | — (no per-repo doc yet) |
| TypeScript | web-demo, drift-detector | Vitest, Playwright | `.claude/docs/small-repos-rules.md` |

When working in a frontend repo, read the matching per-repo doc for framework-specific conventions.
Repos without a per-repo doc follow the general rules in `.claude/docs/test-quality-rules.md`.
