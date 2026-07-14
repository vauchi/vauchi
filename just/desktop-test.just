# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

# Desktop GUI testing recipes (AT-SPI, screenshots, accessibility audit)

# Run AT-SPI accessibility tests for linux-gtk (under Xvfb if no display)
[group('desktop-test')]
[script]
test-atspi-gtk *args='':
    echo "▸ Running AT-SPI tests for linux-gtk..."
    chmod +x linux-gtk/tests/atspi/run-tests.sh
    linux-gtk/tests/atspi/run-tests.sh -v --tb=short -k "not test_snapshots" {{ args }}

# Run AT-SPI accessibility tests for linux-qt (under Xvfb if no display)
[group('desktop-test')]
[script]
test-atspi-qt *args='':
    echo "▸ Running AT-SPI tests for linux-qt..."
    chmod +x linux-qt/tests/atspi/run-tests.sh
    linux-qt/tests/atspi/run-tests.sh -v --tb=short -k "not test_snapshots" {{ args }}

# Run all desktop AT-SPI tests (gtk + qt)
[group('desktop-test')]
[script]
test-desktop-all *args='':
    echo "▸ Running all desktop AT-SPI tests..."
    echo ""
    echo "=== linux-gtk ==="
    chmod +x linux-gtk/tests/atspi/run-tests.sh
    linux-gtk/tests/atspi/run-tests.sh -v --tb=short -k "not test_snapshots" {{ args }} || true
    echo ""
    echo "=== linux-qt ==="
    chmod +x linux-qt/tests/atspi/run-tests.sh
    linux-qt/tests/atspi/run-tests.sh -v --tb=short -k "not test_snapshots" {{ args }} || true

# Dump the AT-SPI accessibility tree for a running app (for debugging)
# Usage: just a11y-audit linux-gtk   or   just a11y-audit linux-qt
[group('desktop-test')]
a11y-audit repo:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ repo }}" in
        linux-gtk|gtk)
            APP_NAME="gvauchi"
            ;;
        linux-qt|qt)
            APP_NAME="vauchi"
            ;;
        *)
            echo "Usage: just a11y-audit <linux-gtk|linux-qt>"
            exit 1
            ;;
    esac

    python3 -c "
    import gi
    gi.require_version('Atspi', '2.0')
    from gi.repository import Atspi

    desktop = Atspi.get_desktop(0)
    found = False
    for i in range(desktop.get_child_count()):
        child = desktop.get_child_at_index(i)
        if child and child.get_name() == '$APP_NAME':
            found = True
            def dump(node, indent=0):
                try:
                    role = node.get_role_name()
                    name = node.get_name()
                    prefix = '  ' * indent
                    print(f'{prefix}[{role}] \"{name}\"')
                    for j in range(node.get_child_count()):
                        c = node.get_child_at_index(j)
                        if c and indent < 8:
                            dump(c, indent + 1)
                except Exception:
                    pass
            dump(child)
            break

    if not found:
        print(f'App \"{APP_NAME}\" not found in AT-SPI tree.')
        print('Is the app running with accessibility enabled?')
        print('  GTK: GTK_A11Y=atspi ./vauchi-gtk')
        print('  Qt:  QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 QT_ACCESSIBILITY=1 ./qvauchi')
    "

# Capture screenshots of all screens for a desktop app (requires running GUI under Xvfb)
# Usage: just screenshot-gtk   or   just screenshot-qt
[group('desktop-test')]
[script]
screenshot-gtk:
    echo "▸ Capturing GTK screenshots..."
    echo "  Build first: just build linux-gtk"
    echo "  Run under Xvfb with screenshot tests:"
    echo "    UPDATE_SNAPSHOTS=1 linux-gtk/tests/atspi/run-tests.sh -k test_snapshots -v"
    echo ""
    echo "  Baselines will be saved to linux-gtk/tests/atspi/snapshots/baseline/"
    echo "  Copy to design/screens/ for design documentation."

# Capture screenshots of all screens for Qt app
[group('desktop-test')]
[script]
screenshot-qt:
    echo "▸ Capturing Qt screenshots..."
    echo "  Build first: just build linux-qt"
    echo "  Run under Xvfb with screenshot tests:"
    echo "    UPDATE_SNAPSHOTS=1 linux-qt/tests/atspi/run-tests.sh -k test_snapshots -v"
    echo ""
    echo "  Baselines will be saved to linux-qt/tests/atspi/snapshots/baseline/"
    echo "  Copy to design/screens/ for design documentation."
