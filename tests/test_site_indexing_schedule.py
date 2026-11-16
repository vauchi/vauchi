# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "just/site-indexing-schedule.py"


class ScheduleBackend:
    def __init__(self, fail_variable=""):
        self.schedule = None
        self.fail_variable = fail_variable
        self.writes = []

    def __call__(self, endpoint, method="GET", **fields):
        if method != "GET":
            self.writes.append((endpoint, method, fields))
        if "/repository/files/" in endpoint:
            return (
                "check:site-indexing-live"
                if "infra%2Fci" in endpoint
                else "infra/ci/site-indexing.yml"
            )
        if "?per_page=" in endpoint:
            return [self.schedule] if self.schedule else []
        if endpoint.endswith("/variables"):
            if fields["key"] == self.fail_variable:
                raise RuntimeError("variable write refused")
            self.schedule["variables"].append(fields)
        elif method == "POST":
            self.schedule = {**fields, "id": 42, "active": False, "variables": []}
        elif method == "PUT":
            self.schedule.update(fields)
        return self.schedule


class SiteIndexingScheduleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("indexing_schedule", SCRIPT)
        cls.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.module)

    def test_creates_inactive_then_configures_all_selectors_before_activation(self):
        backend = ScheduleBackend()
        self.assertEqual(self.module.ensure_schedule(backend), 42)
        self.assertEqual(backend.writes[0][2]["active"], False)
        self.assertEqual(backend.writes[-1][2], {"active": True})
        self.assertEqual(
            {v["key"]: v["value"] for v in backend.schedule["variables"]},
            {
                "SITE_INDEXING_ONLY": "1",
                "INDEXING_MODE": "live",
                "SCHEDULE_TASK": "site-indexing-live",
            },
        )
        self.assertEqual(backend.schedule["cron"], "23 6 * * *")

    def test_variable_failure_preserves_inactive_state_and_retry_resumes(self):
        backend = ScheduleBackend("INDEXING_MODE")
        with self.assertRaises(RuntimeError):
            self.module.ensure_schedule(backend)
        self.assertEqual(backend.schedule["active"], False)
        backend.fail_variable = ""
        self.assertEqual(self.module.ensure_schedule(backend), 42)
        self.assertEqual(len(backend.schedule["variables"]), 3)
        self.assertEqual(backend.schedule["active"], True)

    def test_verified_schedule_is_idempotent(self):
        backend = ScheduleBackend()
        self.module.ensure_schedule(backend)
        writes = len(backend.writes)
        self.assertEqual(self.module.ensure_schedule(backend), 42)
        self.assertEqual(len(backend.writes), writes)

    def test_conflicting_schedule_is_not_overwritten(self):
        backend = ScheduleBackend()
        self.module.ensure_schedule(backend)
        backend.schedule["cron"] = "0 0 * * *"
        writes = len(backend.writes)
        with self.assertRaises(ValueError):
            self.module.ensure_schedule(backend)
        self.assertEqual(len(backend.writes), writes)

    def test_missing_main_config_never_creates_a_schedule(self):
        backend = ScheduleBackend()

        def missing(endpoint, method="GET", **fields):
            if "/repository/files/" in endpoint:
                raise RuntimeError("main config not merged")
            return backend(endpoint, method, **fields)

        with self.assertRaises(RuntimeError):
            self.module.ensure_schedule(missing)
        self.assertEqual(backend.writes, [])


if __name__ == "__main__":
    unittest.main()
