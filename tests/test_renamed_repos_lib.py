# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
#
# SPDX-License-Identifier: GPL-3.0-or-later

"""A workspace follows a renamed repository by moving its checkout.

ADR-078 renamed linux-gtk to gtk-display and linux-qt to qt-display
(private#1029). The registry names the new directories, and a slot cloned
before the rename holds the old ones, with their branches and local work.
"""

import subprocess
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent.parent / "just" / "renamed-repos-lib.sh"


def git(cwd: Path, *args: str) -> str:
    done = subprocess.run(
        ["git", "-C", str(cwd), *args], capture_output=True, text=True, check=True
    )
    return done.stdout.strip()


def checkout(path: Path, url: str) -> None:
    path.mkdir(parents=True)
    git(path, "init", "-q")
    git(path, "remote", "add", "origin", url)


def migrate(workspace: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", "-c", f'source "{LIB}" && migrate_renamed_repo_dirs "$1"', "_", str(workspace)],
        capture_output=True,
        text=True,
    )


class RenamedRepoDirs(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.workspace = Path(scratch.name)

    def test_an_old_checkout_moves_to_the_new_name_with_its_work(self):
        tmp_path = self.workspace
        checkout(tmp_path / "linux-gtk", "git@gitlab.com:vauchi/linux-gtk.git")
        (tmp_path / "linux-gtk" / "uncommitted.txt").write_text("local work\n")

        done = migrate(tmp_path)

        assert done.returncode == 0, done.stderr
        assert not (tmp_path / "linux-gtk").exists()
        assert (tmp_path / "gtk-display" / "uncommitted.txt").read_text() == "local work\n"
        assert git(tmp_path / "gtk-display", "config", "--get", "remote.origin.url") == (
            "git@gitlab.com:vauchi/gtk-display.git"
        )
        assert "linux-gtk -> gtk-display" in done.stdout

    def test_an_https_remote_keeps_its_scheme(self):
        tmp_path = self.workspace
        checkout(tmp_path / "linux-qt", "https://gitlab.com/vauchi/linux-qt.git")

        migrate(tmp_path)

        assert git(tmp_path / "qt-display", "config", "--get", "remote.origin.url") == (
            "https://gitlab.com/vauchi/qt-display.git"
        )

    def test_a_remote_that_is_not_the_renamed_project_is_left_alone(self):
        tmp_path = self.workspace
        checkout(tmp_path / "linux-qt", "git@example.org:someone/fork.git")

        migrate(tmp_path)

        assert git(tmp_path / "qt-display", "config", "--get", "remote.origin.url") == (
            "git@example.org:someone/fork.git"
        )

    def test_both_directories_present_is_refused_and_nothing_moves(self):
        tmp_path = self.workspace
        checkout(tmp_path / "linux-gtk", "git@gitlab.com:vauchi/linux-gtk.git")
        checkout(tmp_path / "gtk-display", "git@gitlab.com:vauchi/gtk-display.git")
        (tmp_path / "linux-gtk" / "kept.txt").write_text("still here\n")

        done = migrate(tmp_path)

        assert done.returncode == 1
        assert (tmp_path / "linux-gtk" / "kept.txt").read_text() == "still here\n"
        assert "both linux-gtk and gtk-display exist" in done.stderr

    def test_a_workspace_that_already_followed_is_untouched_and_silent(self):
        tmp_path = self.workspace
        checkout(tmp_path / "gtk-display", "git@gitlab.com:vauchi/gtk-display.git")

        done = migrate(tmp_path)

        assert done.returncode == 0
        assert done.stdout == ""
        assert (tmp_path / "gtk-display" / ".git").is_dir()

    def test_a_plain_directory_with_the_old_name_is_not_moved(self):
        tmp_path = self.workspace
        (tmp_path / "linux-gtk").mkdir()
        (tmp_path / "linux-gtk" / "notes.txt").write_text("not a checkout\n")

        done = migrate(tmp_path)

        assert done.returncode == 0
        assert (tmp_path / "linux-gtk" / "notes.txt").exists()
        assert not (tmp_path / "gtk-display").exists()


if __name__ == "__main__":
    unittest.main()
