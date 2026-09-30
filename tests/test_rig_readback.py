# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""The rig reads each phone's state on release and claim (#439).

Most runs lost on 2026-09-30 came from state changes nobody announced: a
reinstall reset the camera permission and the identity. Release records
what the phone reports; claim reads it again and names what changed since
the hand-over, which also catches a holder that vanished without releasing.
Fake adb and ios return canned output; no phone is touched.
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
TABLE = """\
pixel    android   034AY1UQS9
s7       android   9886784a544a484938 samsung
iphone   ios       00008030-000C04AE0ED0402E
"""

DUMPSYS = """\
Packages:
  Package [app.vauchi] (1a2b3c):
    versionCode=69 minSdk=26 targetSdk=34
    versionName={version}
    runtime permissions:
      android.permission.POST_NOTIFICATIONS: granted={notifications}, flags=[ USER_SET ]
      android.permission.CAMERA: granted={camera}, flags=[ USER_SET ]
"""

IOS_APPS = """[{{"CFBundleIdentifier":"com.apple.Preferences","CFBundleShortVersionString":"17.4"}},\
{{"CFBundleIdentifier":"app.vauchi.ios","CFBundleShortVersionString":"{version}"}}]"""


class RigReadbackTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.workspace = self.tmp / "vauchi"
        (self.workspace / "just").mkdir(parents=True)
        for library in ("rig.just", "rig-lib.sh", "slot-lib.sh"):
            shutil.copyfile(WORKSPACE_ROOT / "just" / library, self.workspace / "just" / library)
        (self.workspace / "justfile").write_text("mod rig 'just/rig.just'\n")
        (self.tmp / "rig-devices").write_text(TABLE)
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.state = self.tmp / "phone"
        self.set_phone(version="0.69.0", camera="true", notifications="false")
        adb = self.bin / "adb"
        adb.write_text(f'#!/bin/sh\n[ -f "{self.state}/offline" ] && exit 1\n'
                       f'[ -f "{self.state}/absent" ] && exit 0\ncat "{self.state}/dumpsys"\n')
        ios = self.bin / "ios"
        ios.write_text(f'#!/bin/sh\ncat "{self.state}/apps"\n')
        adb.chmod(0o755)
        ios.chmod(0o755)
        self.holder = subprocess.Popen(["sleep", "600"])
        self.addCleanup(self.holder.wait)
        self.addCleanup(self.holder.kill)

    def set_phone(self, *, version: str, camera: str, notifications: str) -> None:
        self.state.mkdir(exist_ok=True)
        (self.state / "dumpsys").write_text(DUMPSYS.format(version=version, camera=camera,
                                                             notifications=notifications))
        (self.state / "apps").write_text(IOS_APPS.format(version=version))

    def rig(self, *args: str, session: str = "me", readback: str = "1") -> subprocess.CompletedProcess[str]:
        env = {**{k: v for k, v in os.environ.items() if k != "CLAUDE_CODE_SESSION_ID"},
               "VAUCHI_SESSION_ID": session, "VAUCHI_RIG_DIR": str(self.tmp / "rig"),
               "VAUCHI_RIG_DEVICE_TABLE": str(self.tmp / "rig-devices"),
               "VAUCHI_RIG_HOLDER_PID": str(self.holder.pid), "VAUCHI_RIG_READBACK": readback,
               "PATH": f"{self.bin}:{os.environ['PATH']}"}
        return subprocess.run(["just", "--justfile", str(self.workspace / "justfile"), "rig", *args],
                              cwd=self.workspace, env=env, capture_output=True, text=True)

    def test_claim_reports_what_the_phone_says(self) -> None:
        claim = self.rig("claim", "pixel", "checks")
        self.assertEqual(claim.returncode, 0, claim.stdout + claim.stderr)
        self.assertIn("pixel now: app 0.69.0, camera granted, notifications denied", claim.stdout)

    def test_claim_names_what_changed_since_the_hand_over(self) -> None:
        self.rig("claim", "pixel", "checks")
        self.rig("release", "left as found")
        self.set_phone(version="0.70.0", camera="false", notifications="false")
        claim = self.rig("claim", "pixel", "next run", session="next")
        self.assertEqual(claim.returncode, 0, claim.stdout + claim.stderr)
        self.assertIn("changed since the hand-over", claim.stdout)
        self.assertIn("app 0.69.0 -> 0.70.0", claim.stdout)
        self.assertIn("camera granted -> denied", claim.stdout)
        self.assertNotIn("notifications", claim.stdout.split("changed since the hand-over")[1])

    def test_an_unchanged_phone_says_so(self) -> None:
        self.rig("claim", "pixel", "checks")
        self.rig("release", "left as found")
        claim = self.rig("claim", "pixel", "next run", session="next")
        self.assertIn("unchanged since the hand-over", claim.stdout)

    def test_the_iphone_reports_its_app_version(self) -> None:
        claim = self.rig("claim", "iphone", "checks")
        self.assertIn("iphone now: app 0.69.0", claim.stdout)

    def test_an_absent_app_and_an_unreachable_phone_never_block_a_claim(self) -> None:
        (self.state / "absent").write_text("")
        claim = self.rig("claim", "pixel", "checks")
        self.assertEqual(claim.returncode, 0)
        self.assertIn("pixel now: app not installed", claim.stdout)
        self.rig("release", "")
        (self.state / "offline").write_text("")
        claim = self.rig("claim", "pixel", "checks")
        self.assertEqual(claim.returncode, 0, claim.stdout + claim.stderr)
        self.assertIn("pixel now: not readable", claim.stdout)

    def test_reading_can_be_turned_off(self) -> None:
        claim = self.rig("claim", "pixel", "checks", readback="0")
        self.assertEqual(claim.returncode, 0)
        self.assertNotIn("now:", claim.stdout)


if __name__ == "__main__":
    unittest.main()
