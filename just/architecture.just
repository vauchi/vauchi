# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

# Test the standalone architecture analyzer, without building application crates.
[group('tools')]
architecture-test:
    cargo test --manifest-path scripts/tools/architecture-check/Cargo.toml --locked --offline -j 8

[group('tools')]
architecture-fmt:
    cargo fmt --manifest-path scripts/tools/architecture-check/Cargo.toml

[group('tools')]
architecture-check:
    cargo fmt --manifest-path scripts/tools/architecture-check/Cargo.toml --check
    cargo clippy --manifest-path scripts/tools/architecture-check/Cargo.toml --locked --offline -j 8 --all-targets -- -D warnings
    just architecture-test
    bash scripts/tools/architecture-check/tests/gate.test.sh
    just quality-complexity-build
    python3 scripts/tools/architecture-check/tests/quality-scan-integration.py

# Parse a fresh generated locale module alongside production source.
[group('tools')]
architecture-scan source="core":
    bash scripts/scripts/architecture-check.sh {{quote(source)}} scan

[group('tools')]
architecture-gate source="core" base="origin/main":
    bash scripts/scripts/architecture-check.sh {{quote(source)}} check {{quote(base)}}
