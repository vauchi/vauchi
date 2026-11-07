# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later
"""repos.toml is the one list of repositories (private#1013): the root
.gitignore, the root README's table and the group README must name every
repository it lists, and `public_repos` in the justfile must be what the
registry says. A drift is named by file and repository."""
from __future__ import annotations

import os
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "scripts" / "lib" / "repo-registry.py"


class ReposRegistryTest(unittest.TestCase):
    def test_every_list_agrees_with_the_registry(self) -> None:
        result = subprocess.run(
            [sys.executable, str(HELPER), "check", str(ROOT)],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_public_repos_is_the_registry(self) -> None:
        registry = subprocess.run(
            [sys.executable, str(HELPER), "public"], cwd=ROOT, capture_output=True, text=True, check=True
        ).stdout.split()
        evaluated = subprocess.run(
            ["just", "--evaluate", "public_repos"],
            cwd=ROOT, capture_output=True, text=True, check=True,
            env={**os.environ, "JUST_UNSTABLE": "1"},
        ).stdout.split()
        self.assertEqual(evaluated, registry)

    def test_a_repo_with_checks_has_a_toolchain_to_run_them(self) -> None:
        # The recipes pick a runner by ecosystem: one marked "none" while it
        # lists checks made `just check e2e` check nothing for a week.
        import tomllib

        registry = tomllib.loads((ROOT / "repos.toml").read_text(encoding="utf-8"))
        checks = {"build", "test", "fmt", "lint", "fix", "coverage"}
        without_runner = [
            repo["name"]
            for repo in registry["repo"]
            if repo.get("ecosystem", "none") == "none" and checks & set(repo.get("ops", []))
        ]
        self.assertEqual(without_runner, [])


if __name__ == "__main__":
    unittest.main()
