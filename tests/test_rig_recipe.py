# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""The device rig lock (#439): one session holds the exchange rig's phones.

Two sessions wiped each other's phone state on 2026-09-30 because nothing
said the rig was in use. The lock is machine-wide (every workspace slot
shares the phones), a holder counts as alive while its process runs (a
run can sit in one long Maestro command without a heartbeat), and a
release hands the next holder a note about the phones' state.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(sys.argv.pop(1)).resolve()


class RigRecipeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.rig_dir = self.tmp / "rig"
        self.workspace = self.tmp / "vauchi"
        (self.workspace / "just").mkdir(parents=True)
        for library in ("rig.just", "rig-lib.sh", "slot-lib.sh"):
            shutil.copyfile(WORKSPACE_ROOT / "just" / library, self.workspace / "just" / library)
        (self.workspace / "justfile").write_text("mod rig 'just/rig.just'\n")
        self.holders: list[subprocess.Popen[bytes]] = []
        self.addCleanup(self.stop_holders)

    def stop_holders(self) -> None:
        for holder in self.holders:
            holder.kill()
            holder.wait()

    def holder(self) -> subprocess.Popen[bytes]:
        process = subprocess.Popen(["sleep", "600"])
        self.holders.append(process)
        return process

    def rig(self, *args: str, session: str, pid: int | None = None) -> subprocess.CompletedProcess[str]:
        environment = {**os.environ, "VAUCHI_SESSION_ID": session, "VAUCHI_RIG_DIR": str(self.rig_dir)}
        environment.pop("CLAUDE_CODE_SESSION_ID", None)
        if pid is not None:
            environment["VAUCHI_RIG_HOLDER_PID"] = str(pid)
        return subprocess.run(
            ["just", "--justfile", str(self.workspace / "justfile"), "rig", *args],
            cwd=self.workspace, env=environment, capture_output=True, text=True,
        )

    def test_a_free_rig_is_claimed_and_shown_as_held(self) -> None:
        a = self.holder()
        claim = self.rig("claim", "Hover runs #9", session="session-a", pid=a.pid)
        self.assertEqual(claim.returncode, 0, claim.stdout + claim.stderr)

        status = self.rig("status", session="session-b")
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertIn("held by", status.stdout)
        self.assertIn(f"pid {a.pid}", status.stdout)
        self.assertIn("Hover runs #9", status.stdout)

    def test_another_live_session_is_refused(self) -> None:
        a, b = self.holder(), self.holder()
        self.rig("claim", session="session-a", pid=a.pid)
        refused = self.rig("claim", session="session-b", pid=b.pid)
        self.assertEqual(refused.returncode, 1)
        self.assertIn("HELD", refused.stdout)
        self.assertIn(f"pid {a.pid}", refused.stdout)

    def test_the_holder_is_released_only_when_its_process_is_gone(self) -> None:
        a, b = self.holder(), self.holder()
        self.rig("claim", session="session-a", pid=a.pid)
        a.kill()
        a.wait()
        taken = self.rig("claim", session="session-b", pid=b.pid)
        self.assertEqual(taken.returncode, 0, taken.stdout + taken.stderr)
        self.assertIn("stale", taken.stdout)
        self.assertIn("held by", self.rig("status", session="session-c").stdout)

    def test_a_reused_pid_does_not_keep_a_dead_holder_alive(self) -> None:
        b = self.holder()
        self.rig_dir.mkdir()
        # A lock whose pid is alive but whose recorded start time is not that
        # process's: the pid was reused by an unrelated process.
        (self.rig_dir / "rig.lock").write_text(
            f"session=session-a\nharness=claude\nslot=vauchi\npid={b.pid}\n"
            "started=Thu Jan  1 00:00:00 1970\nsince=0\nnote=\n"
        )
        taken = self.rig("claim", session="session-b", pid=b.pid)
        self.assertEqual(taken.returncode, 0, taken.stdout + taken.stderr)
        self.assertIn("stale", taken.stdout)

    def test_release_hands_the_next_holder_a_state_note(self) -> None:
        a, b = self.holder(), self.holder()
        self.rig("claim", session="session-a", pid=a.pid)
        released = self.rig("release", "iPhone: build 0.69.0, identity Bob, camera granted",
                            session="session-a", pid=a.pid)
        self.assertEqual(released.returncode, 0, released.stdout + released.stderr)
        self.assertIn("free", self.rig("status", session="session-b").stdout)

        claim = self.rig("claim", session="session-b", pid=b.pid)
        self.assertEqual(claim.returncode, 0)
        self.assertIn("iPhone: build 0.69.0, identity Bob, camera granted", claim.stdout)
        self.assertIn("session-a", claim.stdout)

    def test_only_the_holder_can_release(self) -> None:
        a = self.holder()
        self.rig("claim", session="session-a", pid=a.pid)
        other = self.rig("release", "not mine", session="session-b", pid=a.pid)
        self.assertEqual(other.returncode, 1)
        self.assertIn("held by", self.rig("status", session="session-c").stdout)

    def test_force_takes_a_held_rig_and_logs_it(self) -> None:
        a, b = self.holder(), self.holder()
        self.rig("claim", session="session-a", pid=a.pid)
        forced = self.rig("claim", "--force", "owner needs the phone", session="owner", pid=b.pid)
        self.assertEqual(forced.returncode, 0, forced.stdout + forced.stderr)
        log = (self.rig_dir / "log").read_text()
        self.assertIn("force", log)
        self.assertIn("session-a", log)
        self.assertIn("owner needs the phone", log)

    def test_the_lock_is_shared_by_every_workspace_slot(self) -> None:
        a, b = self.holder(), self.holder()
        other_slot = self.tmp / "vauchi-1"
        shutil.copytree(self.workspace, other_slot)
        self.rig("claim", session="session-a", pid=a.pid)
        environment = {**os.environ, "VAUCHI_SESSION_ID": "session-b",
                       "VAUCHI_RIG_DIR": str(self.rig_dir), "VAUCHI_RIG_HOLDER_PID": str(b.pid)}
        environment.pop("CLAUDE_CODE_SESSION_ID", None)
        refused = subprocess.run(
            ["just", "--justfile", str(other_slot / "justfile"), "rig", "claim"],
            cwd=other_slot, env=environment, capture_output=True, text=True,
        )
        self.assertEqual(refused.returncode, 1, refused.stdout)


if __name__ == "__main__":
    unittest.main()
