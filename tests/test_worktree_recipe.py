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

    def run_list(self, checkout: Path) -> list[str]:
        (checkout / "scripts/scripts/output-helpers.sh").write_text(
            'status_ok() { echo "ROW $1 $2"; }\nstatus_fail() { :; }\n'
        )
        result = subprocess.run(
            ["just", "--justfile", str(checkout / "justfile"), "worktree", "list"],
            cwd=checkout,
            check=True,
            capture_output=True,
            text=True,
        )
        return [line.removeprefix("ROW ") for line in result.stdout.splitlines()
                if line.startswith("ROW ")]

    def run_create(
        self, checkout: Path, branch: str, *repositories: str
    ) -> subprocess.CompletedProcess[str]:
        module = checkout / "worktree.just"
        shutil.copyfile(WORKTREE_JUSTFILE, module)
        wrapper = checkout / "justfile"
        wrapper.write_text("mod worktree 'worktree.just'\n")
        return subprocess.run(
            [
                "just",
                "--justfile",
                str(wrapper),
                "worktree",
                "create",
                branch,
                *(repositories or ("root",)),
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
            created = checkout / ".worktrees/fix--new-work"
            self.assertEqual(self.git(created, "rev-parse", "HEAD"), expected_main)

    def test_script_recipes_select_bash_explicitly(self) -> None:
        lines = WORKTREE_JUSTFILE.read_text().splitlines()
        self.assertNotIn("[script]", lines)
        for recipe in [
            "create name *repos='':",
            "list:",
            "remove name:",
            "remove-force name:",
        ]:
            recipe_line = lines.index(recipe)
            self.assertEqual(lines[recipe_line + 1].strip(), "#!/usr/bin/env bash")

    def test_existing_branch_is_attached_without_rebasing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            _, checkout = self.create_fixture(Path(temporary_directory))
            self.git(checkout, "branch", "fix/existing-work")
            expected_head = self.git(checkout, "rev-parse", "fix/existing-work")

            result = self.run_create(checkout, "fix/existing-work")

            self.assertEqual(result.returncode, 0, result.stderr)
            created = checkout / ".worktrees/fix--existing-work"
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
            created = checkout / ".worktrees/fix--remote-work"
            self.assertEqual(self.git(created, "rev-parse", "HEAD"), expected_head)

    def test_root_worktree_nests_repos_so_workspace_links_resolve(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            seed, checkout = self.create_fixture(Path(temporary_directory))
            subprocess.run(
                ["git", "clone", "--quiet", str(Path(temporary_directory) / "remote.git"),
                 str(checkout / "_private")],
                check=True,
            )
            (seed / ".claude").symlink_to("_private/history.txt")
            self.git(seed, "add", ".claude")
            self.git(seed, "commit", "-m", "link into the nested repo")
            self.git(seed, "push", "origin", "main")

            result = self.run_create(checkout, "fix/nested", "root", "_private")

            self.assertEqual(result.returncode, 0, result.stderr)
            root = checkout / ".worktrees/fix--nested"
            self.assertEqual(self.git(root, "rev-parse", "--show-toplevel"), str(root.resolve()))
            self.assertEqual(
                self.git(root / "_private", "rev-parse", "--show-toplevel"),
                str((root / "_private").resolve()),
            )
            self.assertEqual((root / ".claude").read_text(), "base\n")

    def test_list_shows_only_repositories_of_a_nested_root_worktree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            seed, checkout = self.create_fixture(Path(temporary_directory))
            subprocess.run(
                ["git", "clone", "--quiet", str(Path(temporary_directory) / "remote.git"),
                 str(checkout / "_private")],
                check=True,
            )
            (seed / "just").mkdir()
            (seed / "just/recipe.txt").write_text("recipe\n")
            (seed / ".gitignore").write_text("/_private/\n/.branch-name\n")
            self.git(seed, "add", "just", ".gitignore")
            self.git(seed, "commit", "-m", "tracked directory beside the nested repo")
            self.git(seed, "push", "origin", "main")
            self.assertEqual(self.run_create(checkout, "fix/list", "root", "_private").returncode, 0)

            rows = self.run_list(checkout)

            self.assertEqual(sorted(rows), ["_private fix/list", "root fix/list"])


if __name__ == "__main__":
    unittest.main()
