# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Coverage for `just gitlab resource-group-reset` (vauchi/private#1179).

On 2026-11-09 a resource group that does not exist (GitLab: 404) was
reported as "No stuck jobs — lock is clean": the API error was read as an
empty job list.
"""

from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RESOLVE_REPO = """resolve_gitlab_repo() { echo "$1"; }
resolve_gitlab_project() { echo "vauchi/$1"; }
gitlab_repo_dir() { echo "$1"; }
"""
FAKE_GLAB = r"""#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
if args[:2] == ["auth", "status"]:
    sys.exit(0)
with open(os.environ["GLAB_CALLS"], "a") as log:
    log.write(json.dumps(args) + "\n")
route = next(a for a in args[1:] if a.startswith("projects/"))
if route.endswith("/resource_groups/ios-spm/upcoming_jobs"):
    print(json.dumps([{"id": 71, "name": "build:spm", "status": "waiting_for_resource"},
                      {"id": 72, "name": "publish:spm", "status": "waiting_for_resource"}]))
    sys.exit(0)
if route.endswith("/resource_groups/clean/upcoming_jobs"):
    print("[]")
    sys.exit(0)
if route.endswith("/cancel"):
    print(json.dumps({"id": int(route.split("/")[-2]), "status": "canceled"}))
    sys.exit(0)
print(json.dumps({"message": "404 Not found"}))
sys.stderr.write("glab: 404 Not found (HTTP 404)\n")
sys.exit(1)
"""


class ResourceGroupResetTests(unittest.TestCase):
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
        self.calls = base / "calls.jsonl"
        self.env = dict(os.environ, JUST_UNSTABLE="1", GLAB_CALLS=str(self.calls),
                        PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def reset(self, key: str) -> subprocess.CompletedProcess:
        return subprocess.run(["just", "gitlab", "resource-group-reset", "ios", key],
                              cwd=self.ws, env=self.env, capture_output=True, text=True)

    def cancelled(self) -> list[str]:
        if not self.calls.exists():
            return []
        return [c[-1] for c in map(json.loads, self.calls.read_text(encoding="utf-8").splitlines())
                if c[-1].endswith("/cancel")]

    def test_queued_jobs_are_cancelled(self) -> None:
        result = self.reset("ios-spm")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.cancelled(), ["projects/vauchi%2Fios/jobs/71/cancel",
                                            "projects/vauchi%2Fios/jobs/72/cancel"])
        self.assertIn("Queued/stuck jobs: 2", result.stdout)

    def test_an_empty_queue_is_reported_clean(self) -> None:
        result = self.reset("clean")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("lock is clean", result.stdout)

    def test_an_unknown_resource_group_fails_instead_of_reading_clean(self) -> None:
        result = self.reset("no-such-group")

        self.assertEqual(result.returncode, 1)
        self.assertNotIn("lock is clean", result.stdout)
        self.assertIn("404", result.stdout + result.stderr)
        self.assertEqual(self.cancelled(), [])


if __name__ == "__main__":
    unittest.main()
