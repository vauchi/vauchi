# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""`just test-name` must report failing tests, and run every test target.

Each toolchain arm ended in `|| true`, so a failing build or test exited 0
(vauchi/private#590). Cargo also stopped at the first failing test binary:
on 2026-10-16 a red cucumber target hid the matching tests in core's `it`
target, and the recipe still exited 0.

The test runs the real recipe in a sandbox with a stub `cargo` on PATH.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(sys.argv.pop(1)).resolve().parent if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]

# The four resolver functions the recipe uses. Root CI does not clone the
# scripts repo, so the real resolve-repo.sh is not there to copy.
RESOLVE_REPO_STUB = """
resolve_repo() { echo "$1"; }
repo_dir() { echo "$PWD/$1"; }
repo_toolchain() { echo rust; }
repo_test_features() { echo "--features stub/testing"; }
"""

CARGO_STUB = """#!/bin/sh
echo "$*" >> "$CARGO_CALLS"
echo "test result: stub"
exit "$CARGO_EXIT"
"""


class TestNameRecipeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.ws = base / "ws"
        self.ws.mkdir()
        shutil.copy(ROOT / "justfile", self.ws / "justfile")
        shutil.copytree(ROOT / "just", self.ws / "just")
        resolver = self.ws / "scripts" / "scripts"
        resolver.mkdir(parents=True)
        (resolver / "resolve-repo.sh").write_text(RESOLVE_REPO_STUB)
        (self.ws / "core").mkdir()
        (self.ws / "core" / "Cargo.toml").write_text("[workspace]\n")
        self.bin = base / "bin"
        self.bin.mkdir()
        cargo = self.bin / "cargo"
        cargo.write_text(CARGO_STUB)
        cargo.chmod(0o755)
        self.calls = base / "cargo-calls.log"

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_recipe(self, cargo_exit: int) -> subprocess.CompletedProcess[str]:
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env["CARGO_CALLS"] = str(self.calls)
        env["CARGO_EXIT"] = str(cargo_exit)
        env["JUST_UNSTABLE"] = "1"
        return subprocess.run(
            ["just", "--justfile", str(self.ws / "justfile"), "test-name", "some_pattern", "core"],
            cwd=self.ws,
            env=env,
            capture_output=True,
            text=True,
        )

    def test_failing_tests_fail_the_recipe(self) -> None:
        result = self.run_recipe(cargo_exit=101)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("test-name: core failed", result.stdout + result.stderr)

    def test_passing_tests_pass_the_recipe(self) -> None:
        result = self.run_recipe(cargo_exit=0)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_cargo_runs_every_test_target(self) -> None:
        self.run_recipe(cargo_exit=0)
        calls = self.calls.read_text()
        self.assertIn("--no-fail-fast", calls)
        self.assertIn("some_pattern", calls)


if __name__ == "__main__":
    unittest.main()
