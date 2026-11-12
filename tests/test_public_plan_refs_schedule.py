# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


WORKSPACE = Path(__file__).resolve().parents[1]
ENDPOINT = "projects/vauchi%2Fprivate/pipeline_schedules"
STUB = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with Path(os.environ["CALLS"]).open("a") as log:
    log.write(json.dumps(args) + "\\n")
if args == ["auth", "status"]:
    sys.exit(0)
endpoint = args[1]
mode = os.environ["MODE"]
if "?" in endpoint:
    if mode == "list-failure":
        sys.exit(1)
    print(json.dumps([{"id": 42, "description": "public-plan-refs"}] if mode == "existing" else []))
elif endpoint.endswith("/variables"):
    if mode == "variable-failure":
        sys.exit(1)
    print('{"key":"SCHEDULE_TASK","value":"public-plan-refs"}')
elif endpoint.endswith("/42"):
    print(json.dumps({"id":42, "ref":"refs/heads/main", "active":True,
        "cron":"17 5 * * 1", "cron_timezone":"UTC",
        "variables":[{"key":"SCHEDULE_TASK", "value":"public-plan-refs"}]}))
elif endpoint.endswith("/pipeline_schedules") and "POST" in args:
    print('{"id":42}')
else:
    sys.exit("unexpected call: " + repr(args))
'''


class PublicPlanRefsScheduleTest(unittest.TestCase):
    def run_recipe(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bin").mkdir()
            stub = root / "bin/glab"
            stub.write_text(STUB)
            stub.chmod(0o755)
            shutil.copyfile(WORKSPACE / "just/gitlab.just", root / "gitlab.just")
            (root / "justfile").write_text("mod gitlab 'gitlab.just'\n")
            calls = root / "calls"
            result = subprocess.run(
                ["just", "--justfile", str(root / "justfile"), "gitlab", "public-plan-refs-schedule"],
                cwd=root,
                env={**os.environ, "PATH": f"{root / 'bin'}:{os.environ['PATH']}",
                     "MODE": mode, "CALLS": str(calls)},
                capture_output=True, text=True,
            )
            recorded = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
            return result, recorded

    def test_creates_inactive_then_sets_task_then_activates_and_verifies(self):
        result, calls = self.run_recipe("new")
        self.assertEqual(result.returncode, 0, result.stderr)
        writes = [call for call in calls if "-X" in call]
        self.assertEqual([call[1] for call in writes], [ENDPOINT, ENDPOINT + "/42/variables", ENDPOINT + "/42"])
        self.assertIn("active=false", writes[0])
        self.assertIn("ref=main", writes[0])
        self.assertIn("cron=17 5 * * 1", writes[0])
        self.assertIn("key=SCHEDULE_TASK", writes[1])
        self.assertIn("value=public-plan-refs", writes[1])
        self.assertIn("active=true", writes[2])
        self.assertEqual(calls[-1], ["api", ENDPOINT + "/42"])

    def test_existing_schedule_is_verified_without_creating_a_duplicate(self):
        result, calls = self.run_recipe("existing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call for call in calls if "-X" in call], [])
        self.assertEqual(calls[-1], ["api", ENDPOINT + "/42"])

    def test_failed_variable_write_leaves_the_schedule_inactive(self):
        result, calls = self.run_recipe("variable-failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len([call for call in calls if "-X" in call]), 2)
        self.assertFalse(any("active=true" in call for call in calls))

    def test_failed_list_never_creates_a_schedule(self):
        result, calls = self.run_recipe("list-failure")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call for call in calls if "-X" in call], [])


if __name__ == "__main__":
    unittest.main()
