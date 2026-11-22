# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""The device rig lock (#439): one session at a time holds each phone.

Two sessions wiped each other's phone state on 2026-09-30 because nothing
said a phone was in use. Each phone has its own lock, and a bare claim
takes the exchange pair (pair tests always need both); a phone off the
rig (the Samsung S7) can be held separately. Locks are machine-wide
(every workspace slot shares the phones), a holder counts as alive while
its process runs (a run can sit in one long Maestro command without a
heartbeat), and a release hands the next holder a note about each
phone's state.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(sys.argv.pop(1)).resolve()


def session_id(name: str) -> str:
    """The id slot-lib.sh derives from VAUCHI_SESSION_ID (as `just gitlab claim` does)."""
    return hashlib.sha256(name.encode()).hexdigest()[:12]


class RigRecipeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.rig_dir = self.tmp / "rig"
        self.workspace = self.tmp / "vauchi"
        (self.workspace / "just").mkdir(parents=True)
        for library in ("rig.just", "rig-lib.sh", "slot-lib.sh"):
            shutil.copyfile(WORKSPACE_ROOT / "just" / library, self.workspace / "just" / library)
        (self.workspace / "justfile").write_text("mod rig 'just/rig.just'\n", encoding="utf-8")
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

    def rig(self, *args: str, session: str, pid: int | None = None,
            workspace: Path | None = None) -> subprocess.CompletedProcess[str]:
        workspace = workspace or self.workspace
        environment = {**os.environ, "VAUCHI_SESSION_ID": session, "VAUCHI_RIG_DIR": str(self.rig_dir)}
        environment.pop("CLAUDE_CODE_SESSION_ID", None)
        if pid is not None:
            environment["VAUCHI_RIG_HOLDER_PID"] = str(pid)
        return subprocess.run(
            ["just", "--justfile", str(workspace / "justfile"), "rig", *args],
            cwd=workspace, env=environment, capture_output=True, text=True,
        )

    def status_line(self, device: str) -> str:
        output = self.rig("status", session="observer").stdout
        for line in output.splitlines():
            if line.split() and line.split()[0] == device:
                return line
        self.fail(f"no status line for {device} in:\n{output}")

    def test_a_bare_claim_takes_the_exchange_pair(self) -> None:
        a = self.holder()
        claim = self.rig("claim", "Hover runs #9", session="session-a", pid=a.pid)
        self.assertEqual(claim.returncode, 0, claim.stdout + claim.stderr)
        self.assertIn("pixel, iphone", claim.stdout)

        for device in ("pixel", "iphone"):
            line = self.status_line(device)
            self.assertIn("held by", line)
            self.assertIn(f"pid {a.pid}", line)
            self.assertRegex(line, r"slot [^ /]+/vauchi/other,", "the workspace slot, not the module's directory")
            self.assertIn("Hover runs #9", line)
        self.assertIn("free", self.status_line("s7"))

    def test_a_phone_off_the_rig_is_held_separately(self) -> None:
        a, b = self.holder(), self.holder()
        self.rig("claim", "Hover runs", session="session-a", pid=a.pid)
        s7 = self.rig("claim", "s7", "notification checks", session="session-b", pid=b.pid)
        self.assertEqual(s7.returncode, 0, s7.stdout + s7.stderr)
        self.assertIn(session_id("session-b"), self.status_line("s7"))
        self.assertIn(session_id("session-a"), self.status_line("pixel"))

    def test_claiming_the_iphone_warns_that_automation_covers_its_code(self) -> None:
        """WebDriverAgent's "Automation Running" overlay sits on the iPhone's
        screen while its runner lives. On 2026-11-22 a session kept the
        runner through a Hover run at 14 cm and the Pixel decoded no frame
        of the iPhone's code; the notes that say so were not on its path
        (owner, #1342). The claim is."""
        a, b = self.holder(), self.holder()
        pair = self.rig("claim", "Hover runs", session="session-a", pid=a.pid)
        warning = [line for line in pair.stdout.splitlines() if "Automation Running" in line]
        self.assertEqual(len(warning), 1, pair.stdout)
        self.assertIn("iphone", warning[0])
        self.assertIn("end the runner", warning[0])

        s7 = self.rig("claim", "s7", "notification checks", session="session-b", pid=b.pid)
        self.assertEqual(s7.returncode, 0, s7.stdout + s7.stderr)
        self.assertNotIn("Automation Running", s7.stdout, "a phone without that overlay gets no such line")

    def test_a_claim_is_all_or_nothing(self) -> None:
        a, b = self.holder(), self.holder()
        self.rig("claim", "iphone", "WDA checks", session="session-a", pid=a.pid)
        refused = self.rig("claim", session="session-b", pid=b.pid)
        self.assertEqual(refused.returncode, 1)
        self.assertIn("HELD", refused.stdout)
        self.assertIn("iphone", refused.stdout)
        self.assertIn(f"pid {a.pid}", refused.stdout)
        self.assertIn("free", self.status_line("pixel"), "a refused pair claim must take neither phone")

    def test_a_phone_is_released_only_when_its_holder_process_is_gone(self) -> None:
        a, b = self.holder(), self.holder()
        self.rig("claim", session="session-a", pid=a.pid)
        a.kill()
        a.wait()
        taken = self.rig("claim", session="session-b", pid=b.pid)
        self.assertEqual(taken.returncode, 0, taken.stdout + taken.stderr)
        self.assertIn("stale", taken.stdout)
        self.assertIn(session_id("session-b"), self.status_line("iphone"))

    def test_a_reused_pid_does_not_keep_a_dead_holder_alive(self) -> None:
        b = self.holder()
        self.rig_dir.mkdir()
        # A live pid whose start time is not the recorded one: the pid was
        # reused by an unrelated process. `since` is now, so only the start
        # time can make this lock stale.
        (self.rig_dir / "iphone.lock").write_text(
            f"session=session-a\nharness=claude\nslot=vauchi\npid={b.pid}\n"
            f"started=Thu Jan  1 00:00:00 1970\nsince={int(time.time())}\nnote=\n"
        , encoding="utf-8")
        taken = self.rig("claim", "iphone", session="session-b", pid=b.pid)
        self.assertEqual(taken.returncode, 0, taken.stdout + taken.stderr)
        self.assertIn("stale", taken.stdout)

    def test_release_hands_the_next_holder_a_state_note_per_phone(self) -> None:
        a, b = self.holder(), self.holder()
        self.rig("claim", session="session-a", pid=a.pid)
        released = self.rig("release", "reinstalled 0.69.0, identity Bob, camera granted",
                            session="session-a", pid=a.pid)
        self.assertEqual(released.returncode, 0, released.stdout + released.stderr)
        self.assertIn("free", self.status_line("pixel"))
        self.assertIn("free", self.status_line("iphone"))

        claim = self.rig("claim", "iphone", session="session-b", pid=b.pid)
        self.assertEqual(claim.returncode, 0)
        self.assertIn("reinstalled 0.69.0, identity Bob, camera granted", claim.stdout)
        self.assertIn(session_id("session-a"), claim.stdout)

    def test_release_frees_only_this_sessions_phones(self) -> None:
        a, b = self.holder(), self.holder()
        self.rig("claim", session="session-a", pid=a.pid)
        self.rig("claim", "s7", session="session-b", pid=b.pid)
        other = self.rig("release", "pixel", "not mine", session="session-b", pid=b.pid)
        self.assertEqual(other.returncode, 1)
        self.assertIn(session_id("session-a"), self.status_line("pixel"))
        mine = self.rig("release", session="session-b", pid=b.pid)
        self.assertEqual(mine.returncode, 0, mine.stdout)
        self.assertIn("free", self.status_line("s7"))
        self.assertIn(session_id("session-a"), self.status_line("pixel"))

    def test_force_takes_a_held_phone_and_logs_it(self) -> None:
        a, b = self.holder(), self.holder()
        self.rig("claim", session="session-a", pid=a.pid)
        forced = self.rig("claim", "--force", "iphone", "owner needs the phone", session="owner", pid=b.pid)
        self.assertEqual(forced.returncode, 0, forced.stdout + forced.stderr)
        log = (self.rig_dir / "log").read_text(encoding="utf-8")
        self.assertIn("force", log)
        self.assertIn(session_id("session-a"), log)
        self.assertIn("owner needs the phone", log)
        self.assertIn(session_id("session-a"), self.status_line("pixel"), "force takes only the named phone")

    def test_the_locks_are_shared_by_every_workspace_slot(self) -> None:
        a, b = self.holder(), self.holder()
        other_slot = self.tmp / "vauchi-1"
        shutil.copytree(self.workspace, other_slot)
        self.rig("claim", session="session-a", pid=a.pid)
        refused = self.rig("claim", session="session-b", pid=b.pid, workspace=other_slot)
        self.assertEqual(refused.returncode, 1, refused.stdout)


    def test_check_lets_a_script_ask_before_driving_phones(self) -> None:
        a, b = self.holder(), self.holder()
        self.rig("claim", "Hover runs", session="session-a", pid=a.pid)
        held = self.rig("check", "pixel", "iphone", session="session-b", pid=b.pid)
        self.assertEqual(held.returncode, 1, held.stdout + held.stderr)
        self.assertIn("pixel", held.stderr)
        self.assertIn(session_id("session-a"), held.stderr)
        self.assertEqual(self.rig("check", "pixel", session="session-a", pid=a.pid).returncode, 0,
                         "the holder's own scripts pass")
        free = self.rig("check", "s7", session="session-b", pid=b.pid)
        self.assertEqual(free.returncode, 0, "a free phone passes")
        self.assertIn("just rig claim", free.stderr, "with a reminder to claim it")
        self.assertIn("held by", self.status_line("pixel"), "check claims nothing")
        self.assertIn("free", self.status_line("s7"))

if __name__ == "__main__":
    unittest.main()
