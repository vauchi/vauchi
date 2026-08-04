# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Regression coverage for project-wide CI pipeline discovery."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
DISCOVER = ROOT / "just" / "discover-ci-pipelines.sh"


class SessionEndCiPipelineScopeTests(unittest.TestCase):
    """Protect the project-wide scope of pipeline alignment checks."""

    def test_discovers_project_pipelines_and_prunes_generated_trees(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            expected = {
                workspace / ".gitlab-ci.yml",
                workspace / "frontend" / ".gitlab-ci.yml",
            }
            excluded = {
                workspace / ".git" / ".gitlab-ci.yml",
                workspace / ".worktrees" / "branch" / ".gitlab-ci.yml",
                workspace / "frontend" / "build" / ".gitlab-ci.yml",
                workspace / "frontend" / "node_modules" / ".gitlab-ci.yml",
                workspace / "frontend" / "target" / ".gitlab-ci.yml",
            }
            for pipeline in expected | excluded:
                pipeline.parent.mkdir(parents=True, exist_ok=True)
                pipeline.touch()

            result = subprocess.run(
                ["bash", str(DISCOVER), str(workspace)],
                check=True,
                capture_output=True,
                text=True,
            )

        discovered = {Path(line) for line in result.stdout.splitlines()}
        self.assertEqual(discovered, expected)


if __name__ == "__main__":
    unittest.main()
