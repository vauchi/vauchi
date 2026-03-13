---
name: library-docs
description: Fetch up-to-date library documentation using WebSearch + Agent instead of Context7 MCP. Use when you need current docs for any library, crate, or framework.
---

# Library Documentation Lookup

Replaces the Context7 MCP server with a local, zero-dependency approach using WebSearch and Agent tools. No external MCP process, no npm supply chain risk.

## When to use

- When you need up-to-date documentation for a library, crate, or framework
- When the user asks "how does X work in library Y?"
- When you need API reference, usage examples, or migration guides
- When writing code that depends on external libraries

## How to use

1. **Identify** the library name and version (if relevant)
2. **Search** using WebSearch with targeted queries:
   - `"<library> <topic> documentation site:<official-docs-domain>"`
   - `"<library> <version> API reference <specific-function-or-type>"`
   - `"<library> examples <use-case>"`
3. **Fetch** the most relevant result using WebFetch to get full page content
4. **Extract** the specific information needed and apply it

## Search strategy

For Rust crates (primary use case):
- Search `site:docs.rs` for API docs: `"<crate> <type/fn> site:docs.rs"`
- Search `site:crates.io` for crate metadata: `"<crate> site:crates.io"`
- Search the crate's repo for examples: `"<crate> example <topic> site:github.com"`

For other ecosystems:
- Swift/iOS: `site:developer.apple.com` or `site:swiftpackageindex.com`
- Kotlin/Android: `site:developer.android.com` or `site:kotlinlang.org`
- TypeScript/Node: `site:npmjs.com` or framework-specific docs site
- General: Include "official documentation" in query

## For bulk lookups

When multiple libraries need docs simultaneously, use the Agent tool to parallelize:
- Spawn one Agent per library with a specific documentation question
- Each agent uses WebSearch + WebFetch independently
- Results come back in parallel without blocking

## Advantages over Context7

- No persistent MCP server process
- No npm supply chain risk (`npx -y` downloading unverified packages)
- No third-party API dependency (Upstash)
- No risk of poisoned documentation injection
- Results come from authoritative sources (docs.rs, official sites)
- Works offline for already-fetched content (WebFetch cache)
