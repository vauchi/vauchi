# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for `just git push-all` (vauchi/private#1318).

A remote branch deleted by housekeeping stays deleted (private#826). On
2026-11-20 the recipe took a branch whose upstream was gone for one never
pushed and ran `push -u`, recreating it; only failing pre-push gates
stopped three such pushes.
"""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_HELPERS = """GREEN=""; RED=""; YELLOW=""; DIM=""; NC=""
timer_start() { :; }
timer_elapsed() { echo 0s; }
status_ok() { echo "ok $1: $2"; }
status_info() { echo "info $1: $2"; }
status_fail() { echo "FAIL $1: $2"; }
summary_mix() { :; }
"""
FOR_EACH_REPO = """for_each_repo() {
    local callback="$1" dir
    for dir in */; do
        [[ -e "${dir}.git" ]] || continue
        "$callback" "${dir%/}" "${dir%/}"
    done
}
"""


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, capture_output=True, text=True
    ).stdout.strip()


def make_repo(path: Path, origin: Path) -> None:
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
    subprocess.run(["git", "init", "-q", "-b", "main", str(path)], check=True)
    git(path, "config", "user.email", "test@example.invalid")
    git(path, "config", "user.name", "Test")
    git(path, "config", "commit.gpgsign", "false")
    (path / "README").write_text("seed\n", encoding="utf-8")
    git(path, "add", "README")
    git(path, "commit", "-q", "-m", "seed")
    git(path, "remote", "add", "origin", str(origin))
    git(path, "push", "-q", "-u", "origin", "main")


def commit_on_branch(repo: Path, branch: str) -> None:
    git(repo, "switch", "-q", "-c", branch)
    (repo / "README").write_text(f"work on {branch}\n", encoding="utf-8")
    git(repo, "commit", "-q", "-am", f"feat: {branch}")


def remote_has(repo: Path, branch: str) -> bool:
    return bool(git(repo, "ls-remote", "--heads", "origin", branch))


class GitPushAllTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.ws = base / "ws"
        self.ws.mkdir()
        for entry in ("justfile", "just"):
            subprocess.run(["cp", "-R", str(ROOT / entry), str(self.ws / entry)], check=True)
        helpers = self.ws / "scripts" / "scripts"
        helpers.mkdir(parents=True)
        (helpers / "output-helpers.sh").write_text(OUTPUT_HELPERS, encoding="utf-8")
        (helpers / "for-each-repo.sh").write_text(FOR_EACH_REPO, encoding="utf-8")

        self.gone = self.ws / "gone"
        make_repo(self.gone, base / "gone.git")
        commit_on_branch(self.gone, "issue/1")
        git(self.gone, "push", "-q", "-u", "origin", "issue/1")
        git(self.gone, "push", "-q", "origin", "--delete", "issue/1")
        git(self.gone, "fetch", "-q", "--prune", "origin")
        (self.gone / "README").write_text("more work after the remote went\n", encoding="utf-8")
        git(self.gone, "commit", "-q", "-am", "feat: more")

        self.new = self.ws / "new"
        make_repo(self.new, base / "new.git")
        commit_on_branch(self.new, "issue/2")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_push_all(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["just", "git", "push-all"],
            cwd=self.ws,
            env=dict(os.environ, JUST_UNSTABLE="1"),
            capture_output=True,
            text=True,
        )

    def test_a_branch_whose_remote_was_deleted_is_not_pushed_again(self) -> None:
        result = self.run_push_all()

        self.assertFalse(remote_has(self.gone, "issue/1"), result.stdout + result.stderr)
        self.assertIn("gone", result.stdout)
        self.assertIn("branch-health", result.stdout)

    def test_a_branch_never_pushed_is_still_pushed_with_its_upstream(self) -> None:
        result = self.run_push_all()

        self.assertTrue(remote_has(self.new, "issue/2"), result.stdout + result.stderr)
        self.assertEqual(git(self.new, "rev-parse", "--abbrev-ref", "issue/2@{u}"), "origin/issue/2")


if __name__ == "__main__":
    unittest.main()
