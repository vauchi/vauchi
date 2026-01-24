# Problem: TUI PTY Automation Not Implemented

**Status**: done
**Created**: 2026-01-23
**Priority**: High

## Problem Description

The TUI device automation in `e2e/src/device/tui.rs` is completely non-functional. All Device trait methods return `DeviceNotSupported` errors. The implementation documents requiring the `expectrl` crate for PTY control, but:

1. **The `expectrl` dependency is not added to Cargo.toml**
2. **No PTY session management is implemented**
3. **All Device trait methods are empty stubs**

## Impact

- Cannot run E2E tests against the TUI
- Cross-platform testing is incomplete
- TUI regressions cannot be caught automatically

## Evidence

From `e2e/src/device/tui.rs`:
```rust
// TODO: Add PTY session handle when implementing
// pty_session: Option<PtySession>,

async fn create_identity(&self, _name: &str) -> E2eResult<()> {
    Err(E2eError::DeviceNotSupported(
        "TUI device automation not yet implemented. Requires expectrl crate for PTY control.".into()
    ))
}
```

From `e2e/Cargo.toml`:
- No `expectrl` dependency present despite documentation stating it's required

## Proposed Solution

1. Add `expectrl = "0.7"` to `e2e/Cargo.toml`
2. Implement PTY session struct with:
   - `start_session()` - Spawn TUI in PTY
   - `send_key(char)` - Send keyboard input
   - `send_text(&str)` - Send text string
   - `expect(&str)` - Wait for pattern in output
   - `get_screen()` - Capture current screen state
3. Implement Device trait methods using PTY primitives
4. Write tests in TDD fashion

## Acceptance Criteria

- [x] `expectrl` added to dependencies
- [x] TuiDevice can spawn and control TUI process
- [x] `create_identity` flow works end-to-end
- [x] At least 3 Device trait methods fully implemented
- [x] Tests pass for basic TUI automation

## Solution Implemented

1. Added `expectrl = "0.7"` to `e2e/Cargo.toml`
2. Implemented PTY session management using `script` command for proper `/dev/tty` access
3. Created wrapper shell script for proper terminal environment setup:
   - Set `TERM=xterm-256color` for proper rendering
   - Set terminal size with `stty rows 24 cols 80`
   - Pass `VAUCHI_DATA_DIR` and `VAUCHI_RELAY_URL` environment variables
4. Fixed TUI to read `VAUCHI_DATA_DIR` environment variable for test isolation
5. Implemented Device trait methods: `create_identity`, `get_card`, `kill_app`, `launch_app`
6. Tests pass in `test_tui_exchange` test case

## Related

- Task #1: Implement TUI PTY automation with expectrl
- Planning doc: `_docs/planning/todo/2026-01-20-cross-platform-e2e.md`
