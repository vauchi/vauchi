# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Exercise the real recipe bodies at their process boundary."""

import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def recipe(name, arguments):
    match = re.search(rf"^{name} \*args:\n(.*?)(?=^\S)",
                      (ROOT / "justfile").read_text(encoding="utf-8"), re.M | re.S)
    if match is None:
        raise AssertionError(f"Missing recipe {name}")
    script = match.group(1).replace("{{args}}", shlex.join(arguments))
    return script.replace("{{ ios_simulator }}", "unused")


class CheckRecipeFailureTests(unittest.TestCase):
    def run_recipe(self, name, arguments, failing_phase=""):
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            (workspace / "CLAUDE.md").touch()
            (workspace / "scripts").symlink_to(ROOT / "scripts", target_is_directory=True)
            (workspace / "bin").mkdir()
            child = workspace / "bin" / "just"
            child.write_text('#!/bin/sh\n[ "$1" != "$FAILING_PHASE" ]\n')
            child.chmod(0o755)
            environment = os.environ.copy()
            environment.update(PATH=f"{workspace / 'bin'}:{environment['PATH']}",
                               FAILING_PHASE=failing_phase)
            environment.pop("_QR_SHARED_DIR", None)
            environment.pop("VAUCHI_QUIET", None)
            return subprocess.run(["bash", "-c", recipe(name, arguments)],
                                  cwd=workspace, env=environment, text=True,
                                  capture_output=True, timeout=15)

    # @internal — developer check orchestration, no product feature
    def test_unsupported_requested_operations_fail_in_both_modes(self):
        for name in ("fmt-check", "lint", "test"):
            for quiet in ([], ["--quiet"]):
                with self.subTest(name=name, quiet=quiet):
                    result = self.run_recipe(name, ["_private", *quiet])
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    # @internal — developer check orchestration, no product feature
    def test_quiet_check_propagates_every_child_exit_without_a_summary(self):
        for phase in ("fmt-check", "lint", "test"):
            with self.subTest(phase=phase):
                result = self.run_recipe("check", ["cli", "--quiet"], phase)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
