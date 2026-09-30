# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# The device rig — one session at a time holds the exchange rig's phones
# (#439). The lock is machine-wide and lasts while the holder's process runs.
# Usage: just rig status | claim [--force] [note] | release [state note]

[group('tests')]
test:
    python3 "{{ justfile_directory() }}/tests/test_rig_recipe.py" "{{ justfile_directory() }}"

# Show who holds the rig and the last hand-over note
status:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    source "{{ justfile_directory() }}/just/rig-lib.sh"
    RIG_SLOT_ROOT="{{ justfile_directory() }}"
    rig_status

# Hold the rig for this session (refused while another live session holds it)
[positional-arguments]
claim *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    source "{{ justfile_directory() }}/just/rig-lib.sh"
    RIG_SLOT_ROOT="{{ justfile_directory() }}"
    rig_claim "$@"

# Release the rig, leaving a note on the phones' state for the next holder
[positional-arguments]
release *note:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    source "{{ justfile_directory() }}/just/rig-lib.sh"
    RIG_SLOT_ROOT="{{ justfile_directory() }}"
    rig_release "$@"
