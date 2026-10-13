# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for `just test-build` (vauchi/private#665).

The recipe raises the app versions on a fresh branch from main and opens
the MRs whose merge tags a release and uploads it to TestFlight or Play
internal testing. --dry-run stops before pushing, which is what this test
drives in a sandbox of throwaway repos.
"""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]

GRADLE = 'android {\n    defaultConfig {\n        versionCode = 5\n        versionName = "0.1.4"\n    }\n}\n'
PROJECT = 'targets:\n  Vauchi:\n    settings:\n      base:\n        MARKETING_VERSION: "0.1.13"\n        CURRENT_PROJECT_VERSION: "14"\n'


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, capture_output=True, text=True
    ).stdout.strip()


def make_app(path: Path, origin: Path, rel: str, content: str) -> None:
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
    subprocess.run(["git", "init", "-q", "-b", "main", str(path)], check=True)
    for key, value in (("user.email", "test@example.invalid"), ("user.name", "Test"),
                       ("commit.gpgsign", "false")):
        git(path, "config", key, value)
    (path / rel).parent.mkdir(parents=True, exist_ok=True)
    (path / rel).write_text(content)
    git(path, "add", "-A")
    git(path, "commit", "-q", "-m", "seed")
    git(path, "remote", "add", "origin", str(origin))
    git(path, "push", "-q", "-u", "origin", "main")


class TestBuildRecipeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.ws = base / "ws"
        self.ws.mkdir()
        for entry in ("justfile", "just"):
            subprocess.run(["cp", "-R", str(ROOT / entry), str(self.ws / entry)], check=True)
        self.android = self.ws / "android"
        self.ios = self.ws / "ios"
        make_app(self.android, base / "android.git", "app/build.gradle.kts", GRADLE)
        make_app(self.ios, base / "ios.git", "project.yml", PROJECT)
        # xcodegen stand-in: regenerating the project shows up as a file.
        self.bin = base / "bin"
        self.bin.mkdir()
        xcodegen = self.bin / "xcodegen"
        xcodegen.write_text("#!/bin/sh\necho generated > Vauchi.pbxproj\n")
        xcodegen.chmod(0o755)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_recipe(self, *args: str) -> subprocess.CompletedProcess:
        env = dict(os.environ, JUST_UNSTABLE="1", PATH=f"{self.bin}:{os.environ['PATH']}")
        return subprocess.run(
            ["just", "test-build", *args], cwd=self.ws, env=env, capture_output=True, text=True
        )

    def test_a_dry_run_bumps_each_app_on_its_own_branch_and_pushes_nothing(self) -> None:
        result = self.run_recipe("both", "--dry-run")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(git(self.android, "branch", "--show-current"), "chore/test-build-0.1.5")
        self.assertIn('versionName = "0.1.5"', (self.android / "app/build.gradle.kts").read_text())
        self.assertIn("versionCode = 6", (self.android / "app/build.gradle.kts").read_text())
        self.assertEqual(git(self.ios, "branch", "--show-current"), "chore/test-build-0.1.14")
        self.assertIn('MARKETING_VERSION: "0.1.14"', (self.ios / "project.yml").read_text())
        self.assertIn('CURRENT_PROJECT_VERSION: "15"', (self.ios / "project.yml").read_text())
        self.assertEqual(git(self.ios, "show", "--name-only", "--format=", "HEAD").split(),
                         ["Vauchi.pbxproj", "project.yml"], "iOS commits the regenerated project")
        for repo in (self.android, self.ios):
            self.assertEqual(git(repo, "status", "--porcelain"), "")
            self.assertEqual(git(repo, "ls-remote", "--heads", "origin", "chore/*"), "",
                             "a dry run pushes nothing")

    def test_a_dirty_app_repo_stops_the_run_before_anything_changes(self) -> None:
        (self.ios / "scratch.txt").write_text("uncommitted\n")

        result = self.run_recipe("both", "--dry-run")

        self.assertNotEqual(result.returncode, 0)
        for repo in (self.android, self.ios):
            self.assertEqual(git(repo, "branch", "--show-current"), "main")

    def test_an_unknown_target_or_flag_is_refused(self) -> None:
        self.assertNotEqual(self.run_recipe("windows").returncode, 0)
        self.assertNotEqual(self.run_recipe("both", "--force").returncode, 0)
