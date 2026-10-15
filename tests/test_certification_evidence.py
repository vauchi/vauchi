# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Feature: release_privacy_multidevice_certification.feature @evidence."""

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from certification_fixture import NOW, PIPELINE_ID, REVISION, api_fixtures, fresh_report, sample_report
from tools.release_evidence import EvidenceError, collect_report, read_report, validate_report


class CertificationEvidenceTest(unittest.TestCase):
    # @scenario: release_privacy_multidevice_certification :: One current automated certification report is required
    def test_complete_report_identifies_seven_lanes_and_26_cases(self):
        self.assertEqual({"lanes": 7, "cases": 26},
                         validate_report(sample_report(), REVISION, now=NOW))

    def test_invalid_reports_fail_closed(self):
        mutations = {
            "missing lane": lambda r: r["lanes"].pop(),
            "missing scenario": lambda r: r["lanes"][1]["cases"].pop(),
            "empty cases": lambda r: r["lanes"][0].update(cases=[]),
            "skipped": lambda r: r["lanes"][0]["cases"][0].update(status="skipped"),
            "failed": lambda r: r["lanes"][0]["cases"][0].update(status="failed"),
            "non-blocking": lambda r: r["lanes"][0].update(allow_failure=True),
            "not boolean": lambda r: r["lanes"][0].update(allow_failure=0),
            "mixed pipeline": lambda r: r["lanes"][0].update(pipeline_id=999),
            "mixed revision": lambda r: r["lanes"][0].update(sha="a" * 40),
            "duplicate lane": lambda r: r["lanes"].append(copy.deepcopy(r["lanes"][0])),
            "duplicate case": lambda r: r["lanes"][0]["cases"].append(
                copy.deepcopy(r["lanes"][0]["cases"][0])),
            "duplicate job": lambda r: r["lanes"][1].update(job_id=r["lanes"][0]["job_id"]),
            "wrong class": lambda r: r["lanes"][0]["cases"][0].update(classname="unit"),
            "failed job": lambda r: r["lanes"][0].update(status="failed"),
            "wrong scope": lambda r: r.update(scope="release-ready"),
            "unknown schema": lambda r: r.update(schema_version=2),
            "boolean schema": lambda r: r.update(schema_version=True),
            "unknown field": lambda r: r.update(release_ready=True),
            "missing source": lambda r: r["sources"].pop("cli"),
            "malformed source": lambda r: r["sources"].update(core="main"),
            "unmerged pipeline": lambda r: r["pipeline"].update(ref="issue/6"),
            "failed pipeline": lambda r: r["pipeline"].update(status="failed"),
            "wrong project": lambda r: r["pipeline"].update(web_url="https://example.test/1"),
            "bool id": lambda r: r["pipeline"].update(id=True),
            "future job": lambda r: r["lanes"][0].update(finished_at="2026-10-16T00:00:00Z"),
            "naive time": lambda r: r["pipeline"].update(created_at="2026-10-15T01:25:47"),
            "wrong type": lambda r: r.update(lanes={}),
        }
        for defect, mutate in mutations.items():
            with self.subTest(defect=defect):
                report = sample_report()
                mutate(report)
                with self.assertRaisesRegex(EvidenceError, "certification evidence"):
                    validate_report(report, REVISION, now=NOW)

    def test_revision_mismatch_and_stale_or_future_evidence_fail(self):
        for revision, now in (
            ("f" * 40, NOW),
            (REVISION, NOW + timedelta(days=8)),
            (REVISION, NOW - timedelta(days=1)),
        ):
            with self.subTest(revision=revision, now=now):
                with self.assertRaisesRegex(EvidenceError, "certification evidence"):
                    validate_report(sample_report(), revision, now=now)

    def test_additional_passing_cases_do_not_weaken_required_coverage(self):
        report = sample_report()
        report["lanes"][0]["cases"].append(
            {"name": "future::additional_scenario", "classname": "vauchi-e2e-tests::it",
             "status": "success"})
        self.assertEqual({"lanes": 7, "cases": 27},
                         validate_report(report, REVISION, now=NOW))

    def test_file_boundary_rejects_missing_malformed_and_oversized_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "report.json"
            for payload in (None, b"{", b"[]", b"null", b"\xff",
                            b'{"schema_version":1,"schema_version":1}',
                            b" " * (2 * 1024 * 1024 + 1)):
                with self.subTest(payload=None if payload is None else len(payload)):
                    if payload is not None:
                        path.write_bytes(payload)
                    with self.assertRaisesRegex(EvidenceError, "certification evidence"):
                        read_report(path, REVISION, now=NOW)
            path.write_text(json.dumps(sample_report()))
            self.assertEqual({"lanes": 7, "cases": 26}, read_report(path, REVISION, now=NOW))

    def test_collect_preserves_pipeline_and_tested_sources_without_test_output(self):
        replies = api_fixtures()
        prefix = f"projects/vauchi%2Fe2e/pipelines/{PIPELINE_ID}"
        replies[prefix + "/test_report"]["test_suites"][0]["test_cases"][0]["system_output"] = (
            "sensitive-observer-marker"
        )
        report = collect_report(PIPELINE_ID, REVISION, fetch=replies.__getitem__, now=NOW)
        self.assertEqual(sample_report(), report)
        self.assertNotIn("sensitive-observer-marker", json.dumps(report))

    def test_collect_rejects_partial_or_inconsistent_api_results(self):
        prefix = f"projects/vauchi%2Fe2e/pipelines/{PIPELINE_ID}"
        mutations = (
            lambda r: r[prefix + "/test_report"]["test_suites"].pop(),
            lambda r: r[prefix + "/test_report"]["test_suites"][0].update(total_count=0),
            lambda r: r[prefix + "/jobs?per_page=100&page=1"][0].update(allow_failure=True),
            lambda r: r[prefix + "/jobs?per_page=100&page=1"][0].update(pipeline={"id": 999}),
        )
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                replies = api_fixtures()
                mutate(replies)
                with self.assertRaisesRegex(EvidenceError, "certification evidence"):
                    collect_report(PIPELINE_ID, REVISION, fetch=replies.__getitem__, now=NOW)

    # @scenario: release_privacy_multidevice_certification :: Incomplete automated evidence blocks release
    def test_every_required_scenario_is_indispensable(self):
        for lane_index, lane in enumerate(sample_report()["lanes"]):
            for case_index, case in enumerate(lane["cases"]):
                with self.subTest(lane=lane["name"], case=case["name"]):
                    report = sample_report()
                    report["lanes"][lane_index]["cases"].pop(case_index)
                    with self.assertRaisesRegex(EvidenceError, "certification evidence"):
                        validate_report(report, REVISION, now=NOW)

    def test_freshness_boundary_uses_original_pipeline_creation(self):
        deadline = datetime(2026, 10, 22, 1, 25, 47, tzinfo=timezone.utc)
        self.assertEqual({"lanes": 7, "cases": 26},
                         validate_report(sample_report(), REVISION, now=deadline))
        with self.assertRaisesRegex(EvidenceError, "older than seven days"):
            validate_report(sample_report(), REVISION, now=deadline + timedelta(microseconds=1))

    def test_cli_exports_valid_evidence_and_hides_failed_api_output(self):
        for mode in ("success", "failed", "malformed", "oversized"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                folder = Path(directory)
                replies = api_fixtures()
                fresh = fresh_report()
                prefix = f"projects/vauchi%2Fe2e/pipelines/{PIPELINE_ID}"
                replies[prefix].update(fresh["pipeline"])
                for job in replies[prefix + "/jobs?per_page=100&page=1"]:
                    job["finished_at"] = fresh["lanes"][0]["finished_at"]
                response_file = folder / "responses.json"
                response_file.write_text(json.dumps(replies))
                executable = folder / "glab"
                executable.write_text("""#!/usr/bin/env python3
import json, os, sys
mode = os.environ['CERTIFICATION_TEST_MODE']
if mode == 'failed':
    print('sensitive-api-marker', file=sys.stderr)
    sys.exit(1)
if mode == 'malformed':
    print('{sensitive-api-marker')
elif mode == 'oversized':
    print(' ' * (2 * 1024 * 1024 + 1))
else:
    value = json.load(open(os.environ['CERTIFICATION_TEST_RESPONSES']))[sys.argv[-1]]
    sys.stdout.write(value if isinstance(value, str) else json.dumps(value))
""")
                executable.chmod(0o755)
                env = dict(os.environ, PATH=str(folder) + os.pathsep + os.environ.get("PATH", ""),
                           CERTIFICATION_TEST_RESPONSES=str(response_file), CERTIFICATION_TEST_MODE=mode)
                output = folder / "certification.json"
                result = subprocess.run(
                    [sys.executable, "-m", "tools.collect_release_evidence", str(PIPELINE_ID),
                     REVISION, str(output)], env=env, capture_output=True, text=True,
                    cwd=Path(__file__).resolve().parent.parent, timeout=30,
                )
                self.assertEqual(0 if mode == "success" else 1, result.returncode, result.stderr)
                self.assertNotIn("sensitive-api-marker", result.stdout + result.stderr)
                if mode == "success":
                    self.assertEqual({"lanes": 7, "cases": 26}, read_report(output, REVISION))
                else:
                    self.assertIn("certification evidence:", result.stderr)
                    self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
