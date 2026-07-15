# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WORKTREE_JUSTFILE = Path(sys.argv.pop(1)).resolve()


class WorktreeRecipeTest(unittest.TestCase):
    def git(self, repository: Path, *arguments: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(repository), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def create_fixture(self, directory: Path) -> tuple[Path, Path]:
        remote = directory / "remote.git"
        seed = directory / "seed"
        checkout = directory / "checkout"

        subprocess.run(
            ["git", "init", "--bare", "--initial-branch=main", str(remote)],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["git", "init", "--initial-branch=main", str(seed)],
            check=True,
            capture_output=True,
        )
        self.git(seed, "config", "user.email", "test@example.com")
        self.git(seed, "config", "user.name", "Worktree Test")
        (seed / "history.txt").write_text("base\n")
        self.git(seed, "add", "history.txt")
        self.git(seed, "commit", "-m", "base")
        self.git(seed, "remote", "add", "origin", str(remote))
        self.git(seed, "push", "-u", "origin", "main")

        subprocess.run(
            ["git", "clone", "--quiet", str(remote), str(checkout)],
            check=True,
        )
        self.git(checkout, "config", "user.email", "test@example.com")
        self.git(checkout, "config", "user.name", "Worktree Test")

        scripts = checkout / "scripts/scripts"
        scripts.mkdir(parents=True)
        (scripts / "output-helpers.sh").write_text(
            "status_ok() { :; }\nstatus_fail() { :; }\n"
        )
        (scripts / "for-each-repo.sh").write_text("for_each_repo() { :; }\n")
        return seed, checkout

    def run_create(self, checkout: Path, branch: str) -> subprocess.CompletedProcess[str]:
        module = checkout / "worktree.just"
        shutil.copyfile(WORKTREE_JUSTFILE, module)
        wrapper = checkout / "justfile"
        wrapper.write_text(
            'set script-interpreter := ["bash", "-eu"]\n'
            "mod worktree 'worktree.just'\n"
        )
        return subprocess.run(
            [
                "just",
                "--justfile",
                str(wrapper),
                "worktree",
                "create",
                branch,
                "root",
            ],
            cwd=checkout,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_new_branch_starts_at_fetched_origin_main(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            seed, checkout = self.create_fixture(Path(temporary_directory))

            (seed / "history.txt").write_text("base\nremote main\n")
            self.git(seed, "add", "history.txt")
            self.git(seed, "commit", "-m", "advance remote main")
            self.git(seed, "push", "origin", "main")
            expected_main = self.git(seed, "rev-parse", "HEAD")

            self.git(checkout, "switch", "-c", "unrelated")
            (checkout / "unrelated.txt").write_text("unrelated\n")
            self.git(checkout, "add", "unrelated.txt")
            self.git(checkout, "commit", "-m", "unrelated checkout commit")

            result = self.run_create(checkout, "fix/new-work")

            self.assertEqual(result.returncode, 0, result.stderr)
            created = checkout / ".worktrees/fix--new-work/root"
            self.assertEqual(self.git(created, "rev-parse", "HEAD"), expected_main)

    def test_existing_branch_is_attached_without_rebasing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            _, checkout = self.create_fixture(Path(temporary_directory))
            self.git(checkout, "branch", "fix/existing-work")
            expected_head = self.git(checkout, "rev-parse", "fix/existing-work")

            result = self.run_create(checkout, "fix/existing-work")

            self.assertEqual(result.returncode, 0, result.stderr)
            created = checkout / ".worktrees/fix--existing-work/root"
            self.assertEqual(self.git(created, "rev-parse", "HEAD"), expected_head)

    def test_remote_only_branch_is_attached_without_diverging(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            seed, checkout = self.create_fixture(Path(temporary_directory))
            self.git(seed, "switch", "-c", "fix/remote-work")
            (seed / "remote-work.txt").write_text("remote work\n")
            self.git(seed, "add", "remote-work.txt")
            self.git(seed, "commit", "-m", "remote branch work")
            self.git(seed, "push", "-u", "origin", "fix/remote-work")
            expected_head = self.git(seed, "rev-parse", "HEAD")

            result = self.run_create(checkout, "fix/remote-work")

            self.assertEqual(result.returncode, 0, result.stderr)
            created = checkout / ".worktrees/fix--remote-work/root"
            self.assertEqual(self.git(created, "rev-parse", "HEAD"), expected_head)


if __name__ == "__main__":
    unittest.main()
