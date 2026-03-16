---
name: desktop-stack
description: Tauri + SolidJS desktop app conventions, IPC commands, i18n, theming, and build/test commands. Use when working on the desktop/ repo.
model: haiku
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Desktop Stack — ARCHIVED

The `desktop/` repo (Tauri 2 + SolidJS) was **archived per ADR-027** (2026-03). It has been replaced by native platform apps:

| Repo | Toolkit | Language | Binding Strategy |
|------|---------|----------|------------------|
| `macos/` | SwiftUI | Swift | UniFFI → xcframework (shared with iOS) |
| `linux-gtk/` | GTK4 + libadwaita | Rust | Direct crate (same process, no FFI) |
| `linux-qt/` | Qt 6 + QML | C++ | cbindgen → C ABI (`vauchi-cabi`) |
| `windows/` | WinUI 3 | C# (.NET 8) | C ABI (`vauchi-cabi`) |

**Why**: Direct hardware access (camera, BLE, NFC), native look-and-feel, eliminates WebView security surface. See `_private/docs/specs/2026-01-22-decisions.md` (ADR-027).

**Web demo** (`web-demo/`) uses SolidJS + WASM — it is a separate project, not a desktop replacement.

## Build & Test

Use platform-specific recipes:

```bash
just build macos          # macOS app
just build linux-gtk      # GTK4 Linux app
just build linux-qt       # Qt6 Linux app
just build windows        # WinUI3 Windows app
just check <platform>     # fmt + lint + test
```

There are no `just desktop-*` recipes — they were removed with the archive.
