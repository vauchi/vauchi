# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""The GitLab wrapper recipes make exactly the glab call they name (vauchi/private#1179).

For a thin wrapper the glab call is the contract: merging with --auto-merge
instead of now, or cancelling a job instead of a pipeline, is the bug. The
retry and run recipes also read GitLab's reply, so a refusal must fail the
recipe and say why. test_glab_cli_contract.py checks the same commands
against the real glab.
"""

from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RESOLVE_REPO = """resolve_gitlab_repo() { if [ "$1" = _private ]; then echo private; else echo "$1"; fi; }
resolve_gitlab_project() { echo "vauchi/$(resolve_gitlab_repo "$1")"; }
gitlab_repo_dir() { echo "$1"; }
"""
FAKE_GLAB = r"""#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
if args[:2] == ["auth", "status"]:
    sys.exit(0)
with open(os.environ["GLAB_CALLS"], "a") as log:
    log.write(json.dumps(args) + "\n")
if os.environ.get("GLAB_REFUSE"):
    print(json.dumps({"message": os.environ["GLAB_REFUSE"]}))
    sys.stderr.write("glab: %s\n" % os.environ["GLAB_REFUSE"])
    sys.exit(1)
if args[0] == "api" and args[1].endswith("/retry"):
    print(json.dumps({"id": 9, "status": "pending", "web_url": "https://gl/p/9"}))
elif args[0] == "api" and args[1].endswith("/pipeline"):
    print(json.dumps({"id": 10, "ref": "main", "status": "created", "web_url": "https://gl/p/10"}))
elif args[0] == "api" and "/jobs" in args[1]:
    print(json.dumps([
        {"id": 31, "name": "test:unit", "status": "failed", "allow_failure": False, "retried": True},
        {"id": 32, "name": "test:unit", "status": "success", "allow_failure": False, "retried": False},
    ]))
elif args[0] == "api" and args[1].endswith("/bridges"):
    print(json.dumps([{"id": 33, "name": "check:site-indexing", "status": "failed",
                       "allow_failure": False,
                       "downstream_pipeline": {"id": 77, "project_id": 4}}]))
"""

CORE = ["-R", "vauchi/core"]
WRAPPERS = [
    (["mr-merge", "5", "core"], ["mr", "merge", "5", "--yes", *CORE]),
    (["mr-merge-when-green", "5", "core"], ["mr", "merge", "5", "--auto-merge", "--yes", *CORE]),
    (["mr-close", "5", "core"], ["mr", "close", "5", *CORE]),
    (["mr-approve", "5", "core"], ["mr", "approve", "5", *CORE]),
    (["mr-rebase", "5", "core"], ["mr", "rebase", "5", *CORE]),
    (["mr-list", "core"], ["mr", "list", *CORE]),
    (["mr-view", "5", "core"], ["mr", "view", "5", *CORE]),
    (["mr-view", "5", "core", "true"], ["mr", "view", "5", *CORE, "--comments"]),
    (["pipeline-cancel", "9", "core"], ["ci", "cancel", "pipeline", "9", *CORE]),
    (["pipeline-retry", "9", "core"], ["api", "projects/vauchi%2Fcore/pipelines/9/retry", "-X", "POST"]),
    (["pipeline-run", "main", "core"], ["api", "projects/vauchi%2Fcore/pipeline", "-X", "POST", "-f", "ref=main"]),
    (["pipeline-list", "core"], ["ci", "list", *CORE]),
    # Retried attempts and bridges too: without them a pipeline can read
    # failed while every listed job passed (private#1281).
    (["pipeline-jobs", "9", "core"], [
        ["api", "projects/vauchi%2Fcore/pipelines/9/jobs?include_retried=true", "--paginate"],
        ["api", "projects/vauchi%2Fcore/pipelines/9/bridges", "--paginate"],
    ]),
    (["pipeline-log", "31", "core"], ["ci", "trace", "31", *CORE]),
    (["issue-list", "_private"], ["issue", "list", "-R", "vauchi/private"]),
    (["issue-view", "1179", "_private"], ["issue", "view", "1179", "-R", "vauchi/private"]),
    (["issue-view", "1179", "_private", "--comments"],
     ["issue", "view", "1179", "-R", "vauchi/private", "--comments"]),
    (["issue-close", "1179", "_private"], ["issue", "close", "1179", "-R", "vauchi/private"]),
    # Retitles an issue and replaces its description from a file
    # (private#1281: an issue reframed around its goal).
    (["issue-update", "1281", "A new title", "description.md", "_private"],
     ["issue", "update", "1281", "-R", "vauchi/private", "--title", "A new title",
      "--description", "The goal, restated."]),
]


class GitlabWrapperRecipeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.ws = base / "ws"
        self.ws.mkdir()
        for entry in ("justfile", "just"):
            subprocess.run(["cp", "-R", str(ROOT / entry), str(self.ws / entry)], check=True)
        helpers = self.ws / "scripts" / "scripts"
        helpers.mkdir(parents=True)
        (helpers / "resolve-repo.sh").write_text(RESOLVE_REPO, encoding="utf-8")
        bin_dir = base / "bin"
        bin_dir.mkdir()
        glab = bin_dir / "glab"
        glab.write_text(FAKE_GLAB, encoding="utf-8")
        glab.chmod(0o755)
        (self.ws / "description.md").write_text("The goal, restated.\n", encoding="utf-8")
        self.calls = base / "calls.jsonl"
        self.env = dict(os.environ, JUST_UNSTABLE="1", GLAB_CALLS=str(self.calls),
                        PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_recipe(self, args: list[str], **env: str) -> tuple[subprocess.CompletedProcess, list]:
        if self.calls.exists():
            self.calls.unlink()
        result = subprocess.run(["just", "gitlab", *args], cwd=self.ws,
                                env={**self.env, **env}, capture_output=True, text=True)
        calls = [json.loads(line) for line in self.calls.read_text(encoding="utf-8").splitlines()] \
            if self.calls.exists() else []
        return result, calls

    def test_each_wrapper_makes_exactly_its_glab_call(self) -> None:
        for args, expected in WRAPPERS:
            with self.subTest(recipe=" ".join(args)):
                result, calls = self.run_recipe(args)

                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                wanted = expected if isinstance(expected[0], list) else [expected]
                self.assertEqual(calls, wanted)

    def test_pipeline_jobs_shows_retried_attempts_and_bridges(self) -> None:
        result, _ = self.run_recipe(["pipeline-jobs", "9", "core"])

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = result.stdout.splitlines()
        self.assertTrue(any(l.split()[0] == "31" and l.endswith("retried") for l in lines), lines)
        self.assertTrue(any(l.split()[0] == "32" and not l.endswith("retried") for l in lines), lines)
        self.assertTrue(any(l.split()[0] == "33" and "bridge downstream=77 4" in l for l in lines), lines)

    def test_retry_and_run_report_the_new_pipeline(self) -> None:
        retried, _ = self.run_recipe(["pipeline-retry", "9", "core"])
        started, _ = self.run_recipe(["pipeline-run", "main", "core"])

        self.assertIn("Retried pipeline 9: pending — https://gl/p/9", retried.stdout)
        self.assertIn("Triggered pipeline 10 on main: created — https://gl/p/10", started.stdout)

    def test_a_refusal_fails_the_recipe_and_names_gitlabs_reason(self) -> None:
        for args in (["pipeline-retry", "9", "core"], ["pipeline-run", "main", "core"],
                     ["mr-merge", "5", "core"], ["pipeline-cancel", "9", "core"]):
            with self.subTest(recipe=" ".join(args)):
                result, _ = self.run_recipe(args, GLAB_REFUSE="403 Forbidden")

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("403 Forbidden", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
