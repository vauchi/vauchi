# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Launch Codex or Kimi with a session id of their own. `just gitlab claim`
# keys claims on VAUCHI_SESSION_ID, then CLAUDE_CODE_SESSION_ID, then
# host:dir — so without this, two Codex/Kimi sessions in one checkout share
# a claim and both believe they hold it.
# Usage: just harness codex [args...]   /   just harness kimi [args...]

[group('tests')]
test:
    python3 "{{ justfile_directory() }}/tests/test_harness_recipe.py" "{{ justfile_directory() }}/just/harness.just"

# Start Codex with its own claim session id
[positional-arguments]
codex *args:
    #!/usr/bin/env bash
    set -euo pipefail
    export VAUCHI_SESSION_ID="${VAUCHI_SESSION_ID:-codex-$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')}"
    exec codex "$@"

# Start Kimi with its own claim session id
[positional-arguments]
kimi *args:
    #!/usr/bin/env bash
    set -euo pipefail
    export VAUCHI_SESSION_ID="${VAUCHI_SESSION_ID:-kimi-$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')}"
    exec kimi "$@"
