# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for `just gitlab pipeline-status` on a reused branch (vauchi/private#408).

ADR-073 reuses `issue/<N>` after each merge, so a branch collects several
MRs. MR pipelines run on refs/merge-requests/<iid>/merge, never on the
branch, and `glab ci status --branch` then refuses with "merge request ID
number required". The recipe reads the open MR's head pipeline instead.
"""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
# Stand-ins for the vauchi/scripts helpers the recipe sources: that repo
# is not part of the root checkout in CI.
RESOLVE_REPO = """resolve_gitlab_repo() { echo "$1"; }
resolve_gitlab_project() { echo "vauchi/$1"; }
gitlab_repo_dir() { echo "$1"; }
"""
# A merged-results pipeline (ref refs/merge-requests/<iid>/merge) runs on a
# merge commit whose second parent is the branch head, as on gitlab.com.
# GitLab as seen for three branches: issue/7 has a merged and an open MR,
# issue/8 has only a branch pipeline, issue/9 has nothing. As on gitlab.com,
# only the single-MR endpoint carries head_pipeline, not the MR list.
FAKE_GLAB = r"""#!/bin/sh
case "$1 $2" in
  "auth status") exit 0 ;;
  "ci status")
    echo "merge request ID number required. Possible matches: !12, !11" >&2
    exit 1 ;;
esac
case "$2" in
  *merge_requests*source_branch=issue%2F7*) echo '[{"iid":12}]' ;;
  *merge_requests/12)
    echo '{"iid":12,"head_pipeline":{"id":901,"status":"running","web_url":"https://gl/p/901"}}' ;;
  *merge_requests*source_branch=issue%2F10*) echo '[{"iid":13}]' ;;
  *merge_requests/13)
    echo '{"iid":13,"head_pipeline":{"id":903,"status":"failed","sha":"merge13","ref":"refs/merge-requests/13/merge","web_url":"https://gl/p/903"}}' ;;
  *merge_requests*source_branch=issue%2F11*) echo '[{"iid":14}]' ;;
  *merge_requests/14)
    echo poll >> "$FAKE_POLLS"
    if [ "$(wc -l < "$FAKE_POLLS")" -lt 3 ]; then s=running; else s=success; fi
    echo '{"iid":14,"head_pipeline":{"id":904,"status":"'"$s"'","sha":"merge14","ref":"refs/merge-requests/14/merge","web_url":"https://gl/p/904"}}' ;;
  *merge_requests*source_branch=issue%2F15*) echo '[{"iid":15}]' ;;
  *merge_requests/15)
    echo '{"iid":15,"head_pipeline":{"id":905,"status":"success","sha":"merge15","ref":"refs/merge-requests/15/merge","web_url":"https://gl/p/905"}}' ;;
  *repository/commits/merge15) echo '{"parent_ids":["main0","0000000000000000000000000000000000000000"]}' ;;
  *repository/commits/merge*) echo '{"parent_ids":["main0","'"$FAKE_SHA"'"]}' ;;
  *merge_requests*) echo '[]' ;;
  *pipelines/901/jobs*)
    echo '[{"name":"test","status":"success"},{"name":"lint","status":"running"}]' ;;
  *pipelines/902/jobs*|*pipelines/903/jobs*) echo '[{"name":"test","status":"failed"}]' ;;
  *pipelines/904/jobs*) echo '[{"name":"test","status":"success"}]' ;;
  *pipelines*ref=issue%2F8*)
    echo '[{"id":902,"status":"failed","web_url":"https://gl/p/902"}]' ;;
  *pipelines*) echo '[]' ;;
  *) echo "unexpected: $*" >&2; exit 2 ;;
esac
"""


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True)


class GitlabPipelineStatusTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.ws = base / "ws"
        self.ws.mkdir()
        for entry in ("justfile", "just"):
            subprocess.run(["cp", "-R", str(ROOT / entry), str(self.ws / entry)], check=True)
        helpers = self.ws / "scripts" / "scripts"
        helpers.mkdir(parents=True)
        (helpers / "resolve-repo.sh").write_text(RESOLVE_REPO)

        self.repo = self.ws / "core"
        git(self.ws, "init", "-q", "-b", "main", str(self.repo))

        bin_dir = base / "bin"
        bin_dir.mkdir()
        glab = bin_dir / "glab"
        glab.write_text(FAKE_GLAB)
        glab.chmod(0o755)
        self.env = dict(
            os.environ, JUST_UNSTABLE="1", PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            FAKE_POLLS=str(base / "polls"), PIPELINE_WAIT_INTERVAL="0",
            PIPELINE_WAIT_APPEAR_POLLS="2", FAKE_SHA="",
        )

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def pipeline_status(self, branch: str) -> subprocess.CompletedProcess:
        git(self.repo, "switch", "-q", "-c", branch)
        return subprocess.run(
            ["just", "gitlab", "pipeline-status", "core"],
            cwd=self.ws, env=self.env, capture_output=True, text=True,
        )

    def test_a_branch_with_several_mrs_reports_the_open_mrs_pipeline(self) -> None:
        result = self.pipeline_status("issue/7")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("pipeline 901 (!12): running https://gl/p/901", result.stdout)
        self.assertIn("lint", result.stdout)

    def test_a_branch_without_an_open_mr_reports_its_latest_branch_pipeline(self) -> None:
        result = self.pipeline_status("issue/8")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("pipeline 902 (branch): failed https://gl/p/902", result.stdout)

    def test_a_branch_with_no_pipeline_says_so_and_fails(self) -> None:
        result = self.pipeline_status("issue/9")

        self.assertEqual(result.returncode, 1)
        self.assertIn("no pipeline for issue/9", result.stdout + result.stderr)

    def pipeline_wait(self, branch: str) -> subprocess.CompletedProcess:
        git(self.repo, "switch", "-q", "-c", branch)
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "c")
        self.env["FAKE_SHA"] = subprocess.run(["git", "-C", str(self.repo), "rev-parse", "HEAD"],
                                              capture_output=True, text=True, check=True).stdout.strip()
        return subprocess.run(
            ["just", "gitlab", "pipeline-wait", "core"],
            cwd=self.ws, env=self.env, capture_output=True, text=True, timeout=60,
        )

    # 2026-11-09: on _private issue/1179, whose open MR had a pipeline,
    # pipeline-wait printed "No pipeline found yet" until killed; the fake
    # refuses `glab ci status` the same way for a reused branch.
    def test_wait_ends_passed_when_the_pipeline_succeeds(self) -> None:
        result = self.pipeline_wait("issue/11")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Pipeline PASSED", result.stdout)
        self.assertIn("pipeline 904 (!14): running", result.stdout)
        self.assertLess(result.stdout.index("running"), result.stdout.index("Pipeline PASSED"))

    def test_wait_ends_failed_when_the_pipeline_fails(self) -> None:
        result = self.pipeline_wait("issue/10")

        self.assertEqual(result.returncode, 1)
        self.assertIn("Pipeline FAILED", result.stdout)
        self.assertIn("failed\ttest", result.stdout)

    # Right after a push the MR's head pipeline is still the previous
    # commit's; a green one there says nothing about HEAD.
    def test_wait_does_not_pass_on_an_earlier_commits_pipeline(self) -> None:
        result = self.pipeline_wait("issue/15")

        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Pipeline PASSED", result.stdout)
        self.assertIn("no pipeline for issue/15 at", result.stdout + result.stderr)

    def test_wait_fails_when_the_branch_has_no_pipeline(self) -> None:
        result = self.pipeline_wait("issue/9")

        self.assertEqual(result.returncode, 1)
        self.assertIn("no pipeline for issue/9 at", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
