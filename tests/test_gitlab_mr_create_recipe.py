# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Exercise real local push hooks while GitLab remains an external boundary."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RESOLVER = """resolve_gitlab_repo() { echo "$1"; }
resolve_gitlab_project() { echo "vauchi/$1"; }
gitlab_repo_dir() { echo "$1"; }
"""
GLAB = r"""#!/usr/bin/env python3
import json, os, sys
if sys.argv[1:3] == ["auth", "status"]:
    sys.exit(0)
with open(os.environ["GLAB_CALL_LOG"], "a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\n")
route = sys.argv[2] if sys.argv[1] == "api" else ""
if "source_branch=" in route:
    print(json.dumps([{"iid": 1}]))
elif "merge_requests/1" in route:
    print(json.dumps({"iid": 1, "draft": True, "diverged_commits_count": 0, "head_pipeline": None}))
elif "state=opened" in route:
    print(json.dumps([{"iid": 1, "draft": True}]))
else:
    print("https://gitlab.test/vauchi/core/-/merge_requests/1")
"""
HOOK = """#!/bin/sh
printf '%s\n' "${SKIP_TESTS:-unset}" >> "$HOOK_LOG"
[ ! -f "$REFUSE_PUSH" ]
"""


class MrCreateRecipeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.ws = base / "workspace"
        self.ws.mkdir()
        shutil.copy2(ROOT / "justfile", self.ws / "justfile")
        shutil.copytree(ROOT / "just", self.ws / "just")
        helpers = self.ws / "scripts" / "scripts"
        helpers.mkdir(parents=True)
        (helpers / "resolve-repo.sh").write_text(RESOLVER)
        shutil.copy2(ROOT / "scripts/scripts/escape-mr-mentions.py", helpers)
        self.repo = self.ws / "core"
        self.remote = base / "remote.git"
        self.git(self.ws, "init", "--bare", "--initial-branch=main", str(self.remote))
        self.git(self.ws, "init", "--initial-branch=main", str(self.repo))
        self.git(self.repo, "config", "user.name", "Recipe Test")
        self.git(self.repo, "config", "user.email", "recipe@example.test")
        hooks = base / "hooks"
        hooks.mkdir()
        self.git(self.repo, "config", "core.hooksPath", str(hooks))
        self.git(self.repo, "commit", "--allow-empty", "-m", "chore: initial")
        self.git(self.repo, "remote", "add", "origin", str(self.remote))
        self.git(self.repo, "push", "origin", "main")
        self.git(self.repo, "switch", "-c", "feature/mr-test")
        self.git(self.repo, "commit", "--allow-empty", "-m", "fix: recipe contract")
        hook = hooks / "pre-push"
        hook.write_text(HOOK)
        hook.chmod(0o755)
        commands = base / "bin"
        commands.mkdir()
        glab = commands / "glab"
        glab.write_text(GLAB)
        glab.chmod(0o755)
        self.calls = base / "glab.jsonl"
        self.hook_log = base / "hook.log"
        self.refuse = base / "refuse"
        self.env = dict(os.environ, JUST_UNSTABLE="1", MR_NO_AUTOLINK="1",
                        MR_DRAFT="1", GLAB_CALL_LOG=str(self.calls),
                        HOOK_LOG=str(self.hook_log), REFUSE_PUSH=str(self.refuse),
                        PATH=f"{commands}{os.pathsep}{os.environ['PATH']}")
        self.env.pop("SKIP_TESTS", None)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    @staticmethod
    def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["git", "-C", str(repo), *args], check=True,
                              capture_output=True, text=True)

    def create(self, *extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["just", "gitlab", "mr-create", "core",
                               "fix: recipe contract", *extra], cwd=self.ws,
                              env=self.env, capture_output=True, text=True)

    def requests(self) -> list[list[str]]:
        if not self.calls.exists():
            return []
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_publication_runs_the_normal_push_hook(self) -> None:
        result = self.create()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.hook_log.read_text().splitlines(), ["unset"])
        requests = self.requests()
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0][:2], ["mr", "create"])
        self.assertIn("--draft", requests[0])
        self.assertEqual(requests[0][requests[0].index("--description") + 1],
                         "- fix: recipe contract")

    def test_an_mr_created_ready_goes_through_the_ready_queue(self) -> None:
        self.env.pop("MR_DRAFT")
        result = self.create()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        requests = self.requests()
        self.assertEqual(requests[0][:2], ["mr", "create"])
        self.assertIn("--draft", requests[0])
        self.assertEqual(requests[-1], ["mr", "update", "1", "--ready", "-R", "vauchi/core"])
        self.assertIn("first in the core ready queue", result.stdout)

    def test_a_rejected_push_does_not_create_an_mr_or_retry_forcefully(self) -> None:
        self.refuse.touch()
        result = self.create()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.hook_log.exists(), result.stdout + result.stderr)
        self.assertEqual(self.hook_log.read_text().splitlines(), ["unset"])
        self.assertEqual(self.requests(), [])


    def test_a_description_file_preserves_newlines_quotes_and_literal_shell_text(self) -> None:
        body = "## Summary\nKeep Bob's \"quoted\" value and $(touch should-not-exist).\n\n## Test Plan\n- [x] Observed RED then GREEN."
        description = self.ws / "reviewer's description.md"
        description.write_text(body)
        result = self.create(str(description))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        request = self.requests()[0]
        self.assertEqual(request[request.index("--description") + 1], body)
        self.assertEqual(self.hook_log.read_text().splitlines(), ["unset"])
        self.assertFalse((self.ws / "should-not-exist").exists())

    def test_a_missing_description_file_stops_before_publication(self) -> None:
        result = self.create(str(self.ws / "missing.md"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing or empty description file", result.stdout + result.stderr)
        self.assertFalse(self.hook_log.exists())
        self.assertEqual(self.requests(), [])


    def test_view_can_read_comments_without_publishing(self) -> None:
        result = subprocess.run(["just", "gitlab", "mr-view", "18", "core", "true"],
                                cwd=self.ws, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.requests(), [["mr", "view", "18", "-R", "vauchi/core", "--comments"]])
        self.assertFalse(self.hook_log.exists())


if __name__ == "__main__":
    unittest.main()
