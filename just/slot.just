# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Workspace slots — one session per full workspace clone (vauchi, vauchi-1, ...).
# session-init acquires this slot and session-end releases it.
# Usage: just slot status | acquire | release

[group('tests')]
test:
    python3 "{{ justfile_directory() }}/tests/test_slot_recipe.py" "{{ justfile_directory() }}"

# Show every slot, who holds it, and how many repos are off main or dirty
status:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    slot_status "{{ justfile_directory() }}"

# Hold this slot for the current session (refuses a slot another live session holds)
acquire:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    slot_acquire "{{ justfile_directory() }}"

# Refresh this session's slot lock so a long-running session is not taken over
touch:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    slot_touch "{{ justfile_directory() }}"

# Release this slot if the current session holds it
release:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{ justfile_directory() }}/just/slot-lib.sh"
    slot_release "{{ justfile_directory() }}"
