# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT_JUSTFILE = Path(sys.argv.pop(1)).resolve()


class E2eRecipeTest(unittest.TestCase):
    def test_direct_gate_targets_device_and_supplies_flow_environment(self) -> None:
        for platform, device in (
            ("android", "emulator-5554"),
            ("ios", "84EBFBCE-88CC-4DFF-8958-9B995F49AF9C"),
        ):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as temp_dir:
                workspace = Path(temp_dir)
                flow_dir = workspace / "e2e" / "maestro" / platform
                flow_dir.mkdir(parents=True)
                (flow_dir / "create_identity.yaml").write_text(
                    "appId: app.vauchi\n---\n- launchApp\n"
                , encoding="utf-8")

                bin_dir = workspace / "bin"
                bin_dir.mkdir()
                args_file = workspace / "maestro-args.txt"
                maestro = bin_dir / "maestro"
                maestro.write_text(
                    "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$MAESTRO_ARGS_FILE\"\n"
                , encoding="utf-8")
                maestro.chmod(maestro.stat().st_mode | stat.S_IXUSR)

                env = os.environ.copy()
                env["PATH"] = f"{bin_dir}:{env['PATH']}"
                env["MAESTRO_ARGS_FILE"] = str(args_file)
                result = subprocess.run(
                    [
                        "just",
                        "--justfile",
                        str(ROOT_JUSTFILE),
                        "--working-directory",
                        str(workspace),
                        f"e2e-{platform}",
                        "create_identity",
                        device,
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                    env=env,
                )

                self.assertEqual(result.returncode, 0, result.stderr)
                args = args_file.read_text(encoding="utf-8").splitlines()
                self.assertEqual(
                    args[:4],
                    [
                        "--device",
                        device,
                        "test",
                        f"e2e/maestro/{platform}/create_identity.yaml",
                    ],
                )
                self.assertIn("NAME=E2E Test", args)

    def test_critical_gate_targets_requested_device(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            workspace = Path(temp_dir)
            flow_dir = workspace / "e2e" / "maestro" / "android"
            flow_dir.mkdir(parents=True)
            (flow_dir / "create_identity.yaml").write_text(
                "appId: app.vauchi\n---\n- launchApp\n"
            , encoding="utf-8")

            bin_dir = workspace / "bin"
            bin_dir.mkdir()
            args_file = workspace / "maestro-args.txt"
            maestro = bin_dir / "maestro"
            maestro.write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$MAESTRO_ARGS_FILE\"\n"
            , encoding="utf-8")
            maestro.chmod(maestro.stat().st_mode | stat.S_IXUSR)

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"
            env["MAESTRO_ARGS_FILE"] = str(args_file)
            result = subprocess.run(
                [
                    "just",
                    "--justfile",
                    str(ROOT_JUSTFILE),
                    "--working-directory",
                    str(workspace),
                    "e2e-maestro-critical",
                    "android",
                    "emulator-5554",
                ],
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                args_file.read_text(encoding="utf-8").splitlines()[:4],
                [
                    "--device",
                    "emulator-5554",
                    "test",
                    "e2e/maestro/android/create_identity.yaml",
                ],
            )


if __name__ == "__main__":
    unittest.main()
