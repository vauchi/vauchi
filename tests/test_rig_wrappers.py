# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Device-tool wrappers honour the rig lock (#439, stage 3).

The Claude hook only sees commands an agent types. Scripts call adb, go-ios
and maestro themselves, so wrappers first on PATH check `just rig` before
running the real tool. Fake real tools record every call; no phone is
touched.
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
# name   platform  serials, UDIDs and aliases
pixel    android   034AY1UQS9
s7       android   9886784a544a484938 samsung
iphone   ios       00008030-000C04AE0ED0402E 07D4C7CE-25C3-59C0-A9DD-F0FD827BEC29
"""


class RigWrapperTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.workspace = self.tmp / "vauchi"
        (self.workspace / "just").mkdir(parents=True)
        for library in ("rig.just", "rig-lib.sh", "slot-lib.sh"):
            shutil.copyfile(WORKSPACE_ROOT / "just" / library, self.workspace / "just" / library)
        shutil.copytree(WORKSPACE_ROOT / "just" / "rig-bin", self.workspace / "just" / "rig-bin")
        (self.workspace / "justfile").write_text("mod rig 'just/rig.just'\n", encoding="utf-8")
        self.table = self.tmp / "rig-devices"
        self.table.write_text(TABLE, encoding="utf-8")
        self.rig_dir = self.tmp / "rig"
        self.real = self.tmp / "real"
        self.real.mkdir()
        self.calls = self.tmp / "calls"
        for tool in ("adb", "ios", "maestro"):
            fake = self.real / tool
            fake.write_text(f'#!/bin/sh\necho "{tool} $*" >> "{self.calls}"\n', encoding="utf-8")
            fake.chmod(0o755)
        self.holders: list[subprocess.Popen[bytes]] = []
        self.addCleanup(self.stop_holders)
        self.env = {
            **{k: v for k, v in os.environ.items() if k != "CLAUDE_CODE_SESSION_ID"},
            "VAUCHI_RIG_DIR": str(self.rig_dir),
            "VAUCHI_RIG_DEVICE_TABLE": str(self.table),
            "VAUCHI_RIG_HOME": str(self.tmp / "home"),
        }
        installed = self.just("install-wrappers", session="me")
        self.assertEqual(installed.returncode, 0, installed.stdout + installed.stderr)
        self.bin = self.tmp / "home" / "bin"

    def stop_holders(self) -> None:
        for holder in self.holders:
            holder.kill()
            holder.wait()

    def just(self, *args: str, session: str, pid: int | None = None) -> subprocess.CompletedProcess[str]:
        env = {**self.env, "VAUCHI_SESSION_ID": session}
        if pid is not None:
            env["VAUCHI_RIG_HOLDER_PID"] = str(pid)
        return subprocess.run(["just", "--justfile", str(self.workspace / "justfile"), "rig", *args],
                              cwd=self.workspace, env=env, capture_output=True, text=True)

    def claim_as_other(self, *args: str) -> None:
        holder = subprocess.Popen(["sleep", "600"])
        self.holders.append(holder)
        claim = self.just("claim", *args, session="other", pid=holder.pid)
        self.assertEqual(claim.returncode, 0, claim.stdout + claim.stderr)

    def run_tool(self, *argv: str, **extra: str) -> tuple[int, str, list[str]]:
        self.calls.write_text("", encoding="utf-8")
        env = {**self.env, "VAUCHI_SESSION_ID": "me", **extra,
               "PATH": f"{self.bin}:{self.real}:{os.environ['PATH']}"}
        result = subprocess.run(list(argv), env=env, capture_output=True, text=True)
        return result.returncode, result.stderr, self.calls.read_text(encoding="utf-8").splitlines()

    def test_install_links_each_tool(self) -> None:
        for tool in ("adb", "ios", "maestro"):
            self.assertTrue(os.access(self.bin / tool, os.X_OK), tool)

    def test_a_free_phone_runs_the_real_tool_with_the_same_arguments(self) -> None:
        rc, _, calls = self.run_tool("adb", "-s", "034AY1UQS9", "shell", "getprop", "ro.product.model")
        self.assertEqual(rc, 0)
        self.assertEqual(calls, ["adb -s 034AY1UQS9 shell getprop ro.product.model"])

    def test_a_held_phone_is_refused_before_the_real_tool_runs(self) -> None:
        self.claim_as_other("iphone", "Hover runs")
        rc, err, calls = self.run_tool("ios", "apps", "--udid=00008030-000C04AE0ED0402E")
        self.assertEqual(rc, 1)
        self.assertIn("iphone", err)
        self.assertIn("held by", err)
        self.assertEqual(calls, [])

    def test_a_command_naming_no_phone_targets_its_platform(self) -> None:
        self.claim_as_other("s7", "notification checks")
        rc, _, calls = self.run_tool("adb", "shell", "pm", "list", "packages")
        self.assertEqual((rc, calls), (1, []))
        rc, _, calls = self.run_tool("adb", "-s", "034AY1UQS9", "install", "app.apk")
        self.assertEqual(rc, 0, "naming the free Pixel passes")
        self.assertEqual(calls, ["adb -s 034AY1UQS9 install app.apk"])

    def test_maestro_targets_every_platform_unless_told(self) -> None:
        self.claim_as_other("iphone", "Hover runs")
        rc, _, _ = self.run_tool("maestro", "test", "flow.yaml")
        self.assertEqual(rc, 1)
        rc, _, calls = self.run_tool("maestro", "--platform", "android", "test", "flow.yaml")
        self.assertEqual(rc, 0)
        self.assertEqual(calls, ["maestro --platform android test flow.yaml"])

    def test_listings_and_the_override_pass(self) -> None:
        self.claim_as_other("pixel", "Hover runs")
        self.claim_as_other("s7", "checks")
        self.assertEqual(self.run_tool("adb", "devices")[0], 0)
        rc, _, calls = self.run_tool("adb", "shell", "id", VAUCHI_RIG_OK="1")
        self.assertEqual((rc, calls), (0, ["adb shell id"]))

    def test_the_holder_passes(self) -> None:
        holder = subprocess.Popen(["sleep", "600"])
        self.holders.append(holder)
        self.just("claim", "iphone", "mine", session="me", pid=holder.pid)
        rc, _, calls = self.run_tool("ios", "apps")
        self.assertEqual((rc, calls), (0, ["ios apps"]))

    def test_a_missing_real_tool_is_named(self) -> None:
        (self.real / "adb").unlink()
        env_path = f"{self.bin}:{self.real}:/usr/bin:/bin"
        result = subprocess.run(["adb", "devices"], capture_output=True, text=True,
                                env={**self.env, "VAUCHI_SESSION_ID": "me", "PATH": env_path})
        self.assertEqual(result.returncode, 127)
        self.assertIn("adb", result.stderr)


if __name__ == "__main__":
    unittest.main()
