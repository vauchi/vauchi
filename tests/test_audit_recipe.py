# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Exercise the actual audit recipe against Cargo's exit-status boundary."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CARGO = """#!/usr/bin/env python3
import argparse, os, sys
if sys.argv[1] == "audit":
    if os.environ.get("AUDIT_WARNING") == "1":
        print("Warning: unmaintained", flush=True)
        parser = argparse.ArgumentParser(add_help=False)
        parser.add_argument("--deny", action="append", default=[])
        policy, _ = parser.parse_known_args(sys.argv[2:])
        sys.exit(1 if "warnings" in policy.deny else 0)
    sys.exit(0)
if sys.argv[1:3] == ["deny", "check"]:
    sys.exit(int(os.environ.get("DENY_EXIT", "0")))
sys.exit(2)
"""


class AuditRecipeTest(unittest.TestCase):
    def run_audit(self, **settings: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            shutil.copy(ROOT / "justfile", workspace / "justfile")
            shutil.copytree(ROOT / "just", workspace / "just")
            (workspace / "example").mkdir()
            scripts = workspace / "scripts" / "scripts"
            scripts.mkdir(parents=True)
            (scripts / "resolve-repo.sh").write_text(
                "repos_by_toolchain() { echo example; }\n"
                'repo_dir() { printf "%s\\n" "$1"; }\n'
            , encoding="utf-8")
            binary = workspace / "bin"
            binary.mkdir()
            cargo = binary / "cargo"
            cargo.write_text(CARGO, encoding="utf-8")
            cargo.chmod(0o755)
            environment = {
                **os.environ,
                "PATH": f"{binary}{os.pathsep}{os.environ['PATH']}",
                "JUST_UNSTABLE": "1",
                **settings,
            }
            return subprocess.run(
                ["just", "--justfile", str(workspace / "justfile"), "audit", "example"],
                cwd=workspace,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

    def test_a_warning_denied_by_ci_fails_the_local_recipe(self) -> None:
        result = self.run_audit(AUDIT_WARNING="1")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("ERROR: cargo audit failed for example", result.stderr)

    def test_clean_dependencies_pass(self) -> None:
        result = self.run_audit()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_dependency_policy_failure_still_fails(self) -> None:
        result = self.run_audit(DENY_EXIT="1")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("ERROR: cargo deny check failed for example", result.stderr)


if __name__ == "__main__":
    unittest.main()
