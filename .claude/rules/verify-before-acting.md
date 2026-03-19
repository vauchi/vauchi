---
apply: always
---

## Verify Before Acting (MANDATORY)

Problem records, plans, and roadmaps become stale. Code is the source of truth.

### Before implementing a fix from a problem record

```
grep -r "PatternFromProblemRecord" repo/src/  # verify the bug still exists
```

If the grep returns nothing, the issue may already be fixed. Update the problem record
instead of launching an implementation agent.

### Before launching background agents

Spend 30 seconds verifying the task is still needed. One grep is cheaper than a full
agent execution (~1500 tokens wasted on the ConsentType::Analytics non-issue, 2026-03-19).

### Before writing tests that use mocks or test infrastructure

Read the mock API first. Do not assume return types from method names.
`MockTransport::sent_messages()` returns `Vec<MessageEnvelope>`, not `Vec<Vec<u8>>`.

### After editing Rust files

The post-edit hook runs `rustfmt` which may reformat your edit. If making multiple
sequential edits to the same file, verify each edit took hold before proceeding to the
next. If a build fails with "unexpected arguments", re-read the file — the edit may
have been lost.
