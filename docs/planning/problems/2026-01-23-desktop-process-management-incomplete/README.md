# Problem: Desktop Tauri Process Management Incomplete

**Status**: done
**Created**: 2026-01-23
**Priority**: High

## Problem Description

The Desktop (Tauri) device implementation in `e2e/src/device/tauri.rs` has critical bugs in process management:

1. **`launch_app()` returns error after spawning** - Process is spawned but immediately discarded
2. **Unsafe pointer manipulation in `kill_app()`** - Uses raw pointer to circumvent borrow checker
3. **Interior mutability not implemented** - Cannot store process handle properly
4. **IPC communication not implemented** - Cannot invoke Tauri commands from tests

## Impact

- Cannot run E2E tests against the desktop app
- Desktop app lifecycle cannot be controlled programmatically
- Cross-platform testing is incomplete

## Evidence

From `e2e/src/device/tauri.rs`:

```rust
// In launch_app() - process spawned then discarded:
let child = cmd.spawn().map_err(|e| { ... })?;
let _ = child;  // <-- Process handle dropped!
Err(E2eError::DeviceNotSupported(
    "Desktop app launch not yet fully implemented".into()
))

// In kill_app() - unsafe pointer manipulation:
if let Some(mut process) = unsafe {
    std::ptr::read(&self.process as *const Option<Child>)  // UB!
} {
    let _ = process.kill().await;
}
```

## Root Cause

The Device trait methods take `&self` (immutable reference), but storing the process handle requires mutation. The code comments acknowledge this:

```rust
// Store process handle (this is a bit hacky due to mut self)
// In a real implementation, we'd use interior mutability
```

## Proposed Solution

1. Use `tokio::sync::RwLock<Option<Child>>` for interior mutability
2. Properly store process handle after spawn
3. Implement IPC communication via Tauri test mode or stdin/stdout
4. Remove unsafe code
5. Add app readiness detection (wait for window/IPC)

## Acceptance Criteria

- [x] `launch_app()` successfully starts and tracks process
- [x] `kill_app()` safely terminates process without unsafe code
- [x] Process handle persists across method calls
- [x] At least basic IPC communication works
- [x] No unsafe blocks in device implementation

## Solution Implemented

1. Used `tokio::sync::Mutex<Option<Child>>` for process handle storage
2. Added test HTTP server to desktop app (`src/test_server.rs`)
3. Server exposes REST API: `/health`, `/identity`, `/card`, `/contacts`, `/sync`
4. E2E TauriDevice connects to test server via HTTP (reqwest)
5. Uses xvfb-run for headless testing on Linux
6. Test passes: identity creation, get card, list contacts

Key endpoints:
- `GET /health` - Health check
- `GET /identity`, `POST /identity` - Identity management
- `GET /card` - Get contact card
- `GET /contacts` - List contacts
- `POST /sync` - Sync with relay

## Related

- Task #2: Fix Desktop Tauri process management
- Planning doc: `_docs/planning/todo/2026-01-20-cross-platform-e2e.md`
