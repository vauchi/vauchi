---
name: linux-e2e-testing
description: AT-SPI and FFI-based E2E testing for native Linux GUI apps (GTK4, Qt). Use when testing linux-gtk or linux-qt frontends, or debugging GUI automation on Wayland.
model: haiku
---

<!-- SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me> -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Linux E2E Testing (AT-SPI & FFI)

## When to Use

- Testing linux-gtk or linux-qt apps end-to-end
- Automating button clicks, text input, screen transitions
- Verifying onboarding flow, sidebar navigation, button states
- Debugging AT-SPI widget tree visibility

## Two Approaches

### 1. AT-SPI (Accessibility Testing)

Uses Linux accessibility framework via D-Bus. Works on Wayland (xdotool doesn't).

**Requirements:**
- `at-spi2-core`, `python-pyatspi` installed
- GTK4: `GTK_A11Y=atspi` env var
- Qt: `QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1` env var

**Capabilities:**
- Find widgets by role (`push button`, `label`, `text`) and name
- Click buttons via action interface (`click`, `activate`, `press`)
- Read/write text fields via editable text interface
- Check enabled/disabled state via `SENSITIVE` state flag
- Read label text for screen verification

**Limitations:**
- Qt dynamically created buttons may not expose action interfaces on Wayland
- Small timing delays (0.3s) needed between actions
- Widget tree structure varies between GTK and Qt

### 2. FFI Testing (Python ctypes)

Loads `libvauchi_cabi.so` directly, bypasses GUI layer entirely.

**Capabilities:**
- Full AppEngine control: create, navigate, handle actions, read screens
- JSON-based: parse screen models, verify components, check actions
- No GUI needed — works in headless CI
- Fast and deterministic

**Best for:**
- Verifying core logic independently from GUI rendering
- CI pipelines without display server
- Testing all action flows without AT-SPI limitations

## Test Flow Reference

Full documentation: `_private/docs/testing/2026-03-09-atspi-e2e-testing.md`

### AT-SPI Quick Pattern

```python
import gi
gi.require_version('Atspi', '2.0')
from gi.repository import Atspi
import time

desktop = Atspi.get_desktop(0)
# Find app by window title
app = next(desktop.get_child_at_index(i)
           for i in range(desktop.get_child_count())
           if desktop.get_child_at_index(i)
           and desktop.get_child_at_index(i).get_name() == "Vauchi")

# Find and click button
def click(node, name):
    for btn in find_all(node, role="push button", name=name):
        actions = btn.get_action_iface()
        if actions:
            actions.do_action(0)
            time.sleep(0.3)
            return True
    return False
```

### FFI Quick Pattern

```python
import ctypes, json

lib = ctypes.CDLL("target/release/libvauchi_cabi.so")
lib.vauchi_app_create.restype = ctypes.c_void_p
lib.vauchi_app_current_screen.restype = ctypes.c_char_p
lib.vauchi_app_handle_action.restype = ctypes.c_char_p

app = lib.vauchi_app_create()
screen = json.loads(lib.vauchi_app_current_screen(app).decode())
assert screen["screen_id"] == "identity_check"

# Press button
action = json.dumps({"ActionPressed": {"action_id": "create_new"}})
lib.vauchi_app_handle_action(app, action.encode())

# Enter text
action = json.dumps({"TextChanged": {"component_id": "display_name", "value": "Alice"}})
lib.vauchi_app_handle_action(app, action.encode())

lib.vauchi_app_destroy(app)
```

## Key Widget Roles (AT-SPI)

| Role | GTK4 | Qt |
|------|------|----|
| `push button` | GtkButton | QPushButton |
| `text` | GtkText/GtkEntry | QLineEdit |
| `label` | GtkLabel | QLabel |
| `toggle button` | GtkToggleButton | — |
| `check box` | GtkCheckButton | QCheckBox |

## Debugging

- **Accerciser**: GUI AT-SPI tree browser (`sudo pacman -S accerciser`)
- **Dump tree**: Walk all nodes printing role, name, child count
- **State check**: `node.get_state_set().contains(Atspi.StateType.SENSITIVE)`
- **Timing issues**: Add `time.sleep(0.3)` between action and read
