# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for `just git branch-health` on gone branches (vauchi/private#826).

A local branch whose remote was deleted shows as gone. On 2026-10-26 a
housekeeping pass deleted ~110 remote branches on purpose, yet the recipe
told every other session to re-push each gone branch, which would bring
them all back. A gone branch whose merged MR covers its tip is merged; any
other gone branch is a question for the maintainer, never a re-push.
"""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
# Stand-ins for the vauchi/scripts helpers the recipe sources: that repo
# is not part of the root checkout in CI.
OUTPUT_HELPERS = """GREEN=""; RED=""; YELLOW=""; DIM=""; NC=""
"""
GIT_HELPERS = """is_branch_in_main() {
    git -C "$1" merge-base --is-ancestor "$2" origin/main 2>/dev/null
}
"""
FOR_EACH_REPO = """for_each_repo() {
    local callback="$1" dir
    for dir in */; do
        [[ -e "${dir}.git" ]] || continue
        "$callback" "${dir%/}" "${dir%/}"
    done
}
for_each_repo_parallel() { for_each_repo "$@"; }
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
    (path / "README").write_text("seed\n")
    git(path, "add", "README")
    git(path, "commit", "-q", "-m", "seed")
    git(path, "remote", "add", "origin", str(origin))
    git(path, "push", "-q", "-u", "origin", "main")


def push_then_delete_remote(repo: Path, branch: str, content: str) -> str:
    git(repo, "switch", "-q", "-c", branch, "main")
    (repo / f"{branch}.txt").write_text(content)
    git(repo, "add", f"{branch}.txt")
    git(repo, "commit", "-q", "-m", branch)
    git(repo, "push", "-q", "-u", "origin", branch)
    git(repo, "push", "-q", "origin", "--delete", branch)
    git(repo, "switch", "-q", "main")
    return git(repo, "rev-parse", branch)


class GitBranchHealthGoneTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.ws = base / "ws"
        self.ws.mkdir()
        for entry in ("justfile", "just"):
            subprocess.run(["cp", "-R", str(ROOT / entry), str(self.ws / entry)], check=True)
        helpers = self.ws / "scripts" / "scripts"
        helpers.mkdir(parents=True)
        (helpers / "output-helpers.sh").write_text(OUTPUT_HELPERS)
        (helpers / "for-each-repo.sh").write_text(FOR_EACH_REPO)
        (helpers / "git-helpers.sh").write_text(GIT_HELPERS)

        self.sub = self.ws / "core"
        make_repo(self.sub, base / "core.git")
        # Squash-merged: main holds the change under a different commit.
        merged_tip = push_then_delete_remote(self.sub, "squashed", "merged work\n")
        (self.sub / "squashed.txt").write_text("merged work\n")
        (self.sub / "README").write_text("main moved on\n")
        git(self.sub, "add", "squashed.txt", "README")
        git(self.sub, "commit", "-q", "-m", "squash of squashed")
        git(self.sub, "push", "-q")
        push_then_delete_remote(self.sub, "abandoned", "never merged\n")

        # GitLab's MR list for a source branch: only `squashed` merged.
        bin_dir = base / "bin"
        bin_dir.mkdir()
        glab = bin_dir / "glab"
        glab.write_text(
            "#!/bin/sh\n"
            'case "$2" in\n'
            f'  *source_branch=squashed*) echo \'[{{"state":"merged","sha":"{merged_tip}"}}]\' ;;\n'
            "  *) echo '[]' ;;\n"
            "esac\n"
        )
        glab.chmod(0o755)
        self.env = dict(
            os.environ, JUST_UNSTABLE="1", PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}"
        )

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def branch_health(self, *mode: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["just", "git", "branch-health", *mode],
            cwd=self.ws, env=self.env, capture_output=True, text=True,
        )

    def row(self, output: str, branch: str) -> str:
        return next(line for line in output.splitlines() if f" {branch} " in line)

    def test_no_gone_branch_is_offered_a_re_push(self) -> None:
        result = self.branch_health()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("RECOVER", result.stdout)
        self.assertNotIn("re-push", result.stdout)
        self.assertNotIn("push -u", result.stdout)

    def test_a_gone_branch_covered_by_a_merged_mr_is_deleted(self) -> None:
        self.assertIn("DELETE", self.row(self.branch_health().stdout, "squashed"))

        result = self.branch_health("cleanup")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(git(self.sub, "branch", "--list", "squashed"), "")

    def test_a_gone_branch_without_a_merged_mr_is_kept_and_asked_about(self) -> None:
        result = self.branch_health("cleanup")

        self.assertIn("ASK", self.row(result.stdout, "abandoned"))
        self.assertIn("deleted on purpose", result.stdout)
        self.assertNotEqual(git(self.sub, "branch", "--list", "abandoned"), "")


if __name__ == "__main__":
    unittest.main()
