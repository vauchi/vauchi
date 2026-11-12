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
endpoint = next(arg for arg in args[1:] if arg.startswith("projects/"))
mode = os.environ["MODE"]
state_file = Path(os.environ["STATE"])
if state_file.exists():
    state = json.loads(state_file.read_text())
else:
    schedule = {"id":42, "description":"public-plan-refs", "ref":"refs/heads/main",
        "active":mode != "existing-inactive", "cron":"17 5 * * 1", "cron_timezone":"UTC",
        "variables":[{"key":"SCHEDULE_TASK", "value":"public-plan-refs", "variable_type":"env_var"}]}
    if mode == "existing-wrong-ref":
        schedule["ref"] = "other"
    if mode == "existing-wrong-task":
        schedule["variables"][0]["value"] = "other"
    if mode == "existing-unreadable-variables":
        del schedule["variables"]
    state = {"schedule":schedule if mode.startswith("existing") or mode == "paginated" else None}
method = args[args.index("-X") + 1] if "-X" in args else "GET"
fields = dict(args[i + 1].split("=", 1) for i, arg in enumerate(args) if arg == "-f")
def persist():
    state_file.write_text(json.dumps(state))
def fail_once(operation):
    if mode == operation + "-failure" and not state.get("failed"):
        state["failed"] = True
        persist()
        sys.exit(1)
if "?" in endpoint:
    if mode == "list-failure":
        sys.exit(1)
    records = [state["schedule"]] if state["schedule"] else []
    if mode == "duplicates":
        records = [{"id": 41, "description": "public-plan-refs"}, {"id": 42, "description": "public-plan-refs"}]
    if mode == "paginated":
        print("[]")
    print(json.dumps(records))
elif endpoint.endswith("/variables"):
    fail_once("variable")
    if any(v["key"] == fields["key"] for v in state["schedule"]["variables"]):
        sys.exit("duplicate variable")
    state["schedule"]["variables"].append(fields)
    print(json.dumps(fields))
elif endpoint.endswith("/42"):
    if method == "PUT":
        fail_once("activation")
        state["schedule"]["active"] = fields["active"] == "true"
    print(json.dumps(state["schedule"]))
elif endpoint.endswith("/pipeline_schedules") and "POST" in args:
    if state["schedule"]:
        sys.exit("duplicate schedule")
    state["schedule"] = {**fields, "id":42, "active":fields["active"] == "true", "variables":[]}
    print(json.dumps(state["schedule"]))
else:
    sys.exit("unexpected call: " + repr(args))
persist()
'''


class PublicPlanRefsScheduleTest(unittest.TestCase):
    def run_recipe(self, mode, attempts=1):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bin").mkdir()
            stub = root / "bin/glab"
            stub.write_text(STUB)
            stub.chmod(0o755)
            shutil.copyfile(WORKSPACE / "just/gitlab.just", root / "gitlab.just")
            (root / "justfile").write_text("mod gitlab 'gitlab.just'\n")
            calls = root / "calls"
            state = root / "state.json"
            results = []
            for _ in range(attempts):
                results.append(subprocess.run(
                    ["just", "--justfile", str(root / "justfile"), "gitlab", "public-plan-refs-schedule"],
                    cwd=root,
                    env={**os.environ, "PATH": f"{root / 'bin'}:{os.environ['PATH']}",
                         "MODE": mode, "CALLS": str(calls), "STATE": str(state)},
                    capture_output=True, text=True,
                ))
            self.backend = json.loads(state.read_text()) if state.exists() else {}
            recorded = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
            return (results[0] if attempts == 1 else results), recorded

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

    def test_inactive_existing_schedule_is_activated_without_duplicate(self):
        result, calls = self.run_recipe("existing-inactive")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.backend["schedule"]["active"])
        self.assertEqual(len([call for call in calls if "-X" in call]), 1)

    def test_retry_recovers_from_partial_creation_without_duplicates(self):
        for mode in ("variable-failure", "activation-failure"):
            with self.subTest(mode=mode):
                results, calls = self.run_recipe(mode, attempts=2)
                self.assertNotEqual(results[0].returncode, 0)
                self.assertEqual(results[1].returncode, 0, results[1].stderr)
                schedule = self.backend["schedule"]
                self.assertTrue(schedule["active"])
                self.assertEqual(schedule["id"], 42)
                self.assertEqual(schedule["variables"], [{
                    "key": "SCHEDULE_TASK", "value": "public-plan-refs", "variable_type": "env_var"}])
                creates = [call for call in calls if "POST" in call and call[1] == ENDPOINT]
                self.assertEqual(len(creates), 1)

    def test_mismatched_or_unreadable_existing_schedule_is_never_modified(self):
        for mode in ("existing-wrong-ref", "existing-wrong-task", "existing-unreadable-variables"):
            with self.subTest(mode=mode):
                result, calls = self.run_recipe(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual([call for call in calls if "-X" in call], [])

    def test_duplicate_schedules_are_not_modified(self):
        result, calls = self.run_recipe("duplicates")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call for call in calls if "-X" in call], [])

    def test_schedule_on_a_later_page_is_found_without_a_duplicate(self):
        result, calls = self.run_recipe("paginated")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call for call in calls if "-X" in call], [])


if __name__ == "__main__":
    unittest.main()
