# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for `just git main wip` (vauchi/private#664).

A WIP checkpoint saves work on a branch you are leaving. On 2026-10-12 the
recipe also committed in repos that were already on main: twice it turned
an untracked screenshot in the workspace root into `wip: checkpoint …` on
the root repo's main, a commit that has to be undone by hand.
"""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
# Stand-ins for the vauchi/scripts helpers the recipe sources: that repo
# is not part of the root checkout in CI. for_each_repo mirrors the real
# enumeration (the root, then every top-level directory with a .git).
OUTPUT_HELPERS = """GREEN=""; RED=""; YELLOW=""; DIM=""; NC=""
timer_start() { :; }
timer_elapsed() { echo 0s; }
progress_ok() { echo "ok $3: $4"; }
progress_fail() { echo "FAIL $3: $4"; }
summary_mix() { :; }
"""
FOR_EACH_REPO = """for_each_repo() {
    local include_root=true
    if [[ "${1:-}" == "--no-root" ]]; then include_root=false; shift; fi
    local callback="$1"
    if $include_root && [[ -e ".git" ]]; then "$callback" "vauchi (root)" "."; fi
    local dir
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
    (path / "README").write_text("seed\n")
    git(path, "add", "README")
    git(path, "commit", "-q", "-m", "seed")
    git(path, "remote", "add", "origin", str(origin))
    git(path, "push", "-q", "-u", "origin", "main")


class GitMainWipTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.ws = base / "ws"
        make_repo(self.ws, base / "root.git")
        for entry in ("justfile", "just"):
            subprocess.run(["cp", "-R", str(ROOT / entry), str(self.ws / entry)], check=True)
        helpers = self.ws / "scripts" / "scripts"
        helpers.mkdir(parents=True)
        (helpers / "output-helpers.sh").write_text(OUTPUT_HELPERS)
        (helpers / "for-each-repo.sh").write_text(FOR_EACH_REPO)
        # The copied recipes are tracked in the root's history, as in the
        # real workspace; only the screenshot below is new.
        (self.ws / ".gitignore").write_text("scripts/\ncore/\n")
        git(self.ws, "add", "justfile", "just", ".gitignore")
        git(self.ws, "commit", "-q", "-m", "recipes")
        git(self.ws, "push", "-q")

        self.sub = self.ws / "core"
        make_repo(self.sub, base / "core.git")
        git(self.sub, "switch", "-q", "-c", "feature/work")
        (self.sub / "README").write_text("edited on a feature branch\n")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_main_wip(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["just", "git", "main", "wip"],
            cwd=self.ws,
            env=dict(os.environ, JUST_UNSTABLE="1"),
            capture_output=True,
            text=True,
        )

    def test_an_untracked_file_on_main_is_left_untracked(self) -> None:
        (self.ws / "screenshot.png").write_bytes(b"\x89PNG")
        head_before = git(self.ws, "rev-parse", "HEAD")

        result = self.run_main_wip()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(git(self.ws, "rev-parse", "HEAD"), head_before,
                         "a repo already on main gets no WIP commit")
        self.assertEqual(git(self.ws, "status", "--porcelain"), "?? screenshot.png")

    def test_work_on_a_feature_branch_is_still_saved_as_wip(self) -> None:
        result = self.run_main_wip()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(git(self.sub, "branch", "--show-current"), "main")
        self.assertTrue(
            git(self.sub, "log", "-1", "--format=%s", "feature/work").startswith("wip: checkpoint"),
            "the feature branch keeps its work as a WIP commit",
        )
