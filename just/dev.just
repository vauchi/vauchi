# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Multi-instance dev recipes (testing sync between "devices")

# ═══════════════════════════════════════════════════════════════════
# MULTI-INSTANCE DEV
# ═══════════════════════════════════════════════════════════════════

# Start local relay (memory storage)
[group('dev')]
dev-relay:
    ./scripts/scripts/dev/local-relay.sh

# Start local relay with TLS (for iOS/Android testing)
[group('dev')]
dev-relay-tls:
    ./scripts/scripts/dev/local-relay-tls.sh

# Setup local CA for mobile TLS testing
[group('dev')]
dev-relay-tls-setup:
    ./scripts/scripts/dev/local-relay-tls.sh --setup

# Run CLI with isolated data (e.g., just dev-cli alice init "Alice")
[group('dev')]
[positional-arguments]
dev-cli *args:
    ./scripts/scripts/dev/multi-cli.sh "$@"

# Run TUI with isolated data
[group('dev')]
dev-tui instance:
    ./scripts/scripts/dev/multi-tui.sh {{instance}}

# Clean test data
[group('dev')]
[confirm('This will clean all dev test data. Continue?')]
dev-clean:
    ./scripts/scripts/dev/cleanup.sh all

# Run E2E test checklist (manual device testing)
[group('dev')]
e2e-checklist *args:
    ./scripts/scripts/dev/e2e-test-checklist.sh {{ args }}
