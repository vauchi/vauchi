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
    def test_critical_gate_targets_requested_device(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            workspace = Path(temp_dir)
            flow_dir = workspace / "e2e" / "maestro" / "android"
            flow_dir.mkdir(parents=True)
            (flow_dir / "create_identity.yaml").write_text(
                "appId: app.vauchi\n---\n- launchApp\n"
            )

            bin_dir = workspace / "bin"
            bin_dir.mkdir()
            args_file = workspace / "maestro-args.txt"
            maestro = bin_dir / "maestro"
            maestro.write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$MAESTRO_ARGS_FILE\"\n"
            )
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
                args_file.read_text().splitlines()[:4],
                [
                    "--device",
                    "emulator-5554",
                    "test",
                    "e2e/maestro/android/create_identity.yaml",
                ],
            )


if __name__ == "__main__":
    unittest.main()
