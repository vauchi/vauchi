# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""`just lint-ci-needs` sweeps resolved CI configs for VCI06 (private#490).

It fetches each project's resolved `main` config from GitLab's CI lint API
and runs check-ci-needs-rules.py on it. The test runs the real recipe with
stand-ins for glab and the checker (root CI has no scripts repo).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(sys.argv.pop(1)).resolve().parent if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]

GLAB_STUB = """#!/usr/bin/env python3
import json, os, sys
path = sys.argv[2]
if "/ci/lint" in path:
    project = path.split("/")[1].split("%2F")[1]
    if project == "unreachable":
        sys.exit(1)
    print(json.dumps({"valid": True, "merged_yaml": open(os.path.join(os.environ["FIXTURES"], project)).read()}))
    sys.exit(0)
sys.exit(2)
"""

CHECKER_STUB = """#!/usr/bin/env python3
import sys
for name in sys.argv[1:]:
    if "BAD" in open(name).read():
        print(f"  {name}: VCI06: seeded violation")
        sys.exit(1)
"""


class LintCiNeedsRecipeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.ws = base / "ws"
        self.ws.mkdir()
        shutil.copy(ROOT / "justfile", self.ws / "justfile")
        shutil.copytree(ROOT / "just", self.ws / "just")
        self.bin = base / "bin"
        self.bin.mkdir()
        glab = self.bin / "glab"
        glab.write_text(GLAB_STUB)
        glab.chmod(0o755)
        self.checker = base / "checker.py"
        self.checker.write_text(CHECKER_STUB)
        self.fixtures = base / "fixtures"
        self.fixtures.mkdir()
        (self.fixtures / "good").write_text("job: {script: [ok]}\n")
        (self.fixtures / "bad").write_text("BAD: {script: [ok]}\n")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_recipe(self, *projects: str) -> subprocess.CompletedProcess[str]:
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env["FIXTURES"] = str(self.fixtures)
        env["VCI06_CHECKER"] = str(self.checker)
        env["JUST_UNSTABLE"] = "1"
        return subprocess.run(
            ["just", "--justfile", str(self.ws / "justfile"), "lint-ci-needs", *projects],
            cwd=self.ws, env=env, capture_output=True, text=True)

    def test_a_violation_fails_the_sweep_and_names_the_project(self) -> None:
        result = self.run_recipe("good", "bad")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("bad: VCI06: seeded violation", result.stdout)

    def test_clean_projects_pass(self) -> None:
        result = self.run_recipe("good")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_project_the_lint_api_refuses_is_reported_not_fatal(self) -> None:
        result = self.run_recipe("good", "unreachable")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("unreachable: no resolved CI config", result.stdout)


if __name__ == "__main__":
    unittest.main()
