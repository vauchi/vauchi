# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

JUSTFILE = Path(sys.argv.pop(1)).resolve()


def plan_with_gates(
    completed_gate: int | None = None,
    excluded_gate: int | None = None,
    all_completed: bool = False,
    status_line: str = "All 15 release gates are open.",
) -> str:
    gates = []
    for gate_number in range(1, 16):
        if gate_number == excluded_gate:
            continue
        marker = "[x] " if all_completed or gate_number == completed_gate else ""
        gates.append(f"   - {marker}RG-{gate_number} — Gate {gate_number} outcome.")
    return "\n".join(
        [
            "# Master Plan: Production Readiness",
            "",
            "**Status**",
            "",
            status_line,
            "",
            "**Release gates**",
            "",
            "1. Complete all production release gates",
            *gates,
            "",
            "**Layer dependencies**",
        ]
    )


class ReleaseGatesTest(unittest.TestCase):
    def run_release_gates(
        self, plan: str, deploy_config: str | None = None
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workspace = Path(temporary_directory)
            plan_path = workspace / "_private/docs/planning/master-plan.plan.md"
            plan_path.parent.mkdir(parents=True)
            plan_path.write_text(plan)
            if deploy_config is not None:
                deploy_path = workspace / "_private/infra/config/deploy.combined.yml"
                deploy_path.parent.mkdir(parents=True)
                deploy_path.write_text(deploy_config)
            return subprocess.run(
                [
                    "just",
                    "--justfile",
                    str(JUSTFILE),
                    "--working-directory",
                    str(workspace),
                    "release-gates",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

    def test_open_rg_tasks_block_release(self) -> None:
        result = self.run_release_gates(plan_with_gates())

        self.assertEqual(1, result.returncode)
        self.assertIn("Production Release Readiness", result.stdout)
        self.assertNotIn("v0.2.0", result.stdout)
        self.assertIn("HARD GATES (0/15 done)", result.stdout)
        self.assertIn("15 HARD GATE(s) block release", result.stdout)

    def test_checked_rg_task_counts_as_done(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                completed_gate=1,
                status_line="14 release gates are open.",
            )
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("HARD GATES (1/15 done)", result.stdout)
        self.assertIn("14 HARD GATE(s) block release", result.stdout)

    def test_checked_rg_task_contradicts_all_open_status(self) -> None:
        result = self.run_release_gates(plan_with_gates(completed_gate=1))

        self.assertEqual(1, result.returncode)
        self.assertIn("master-plan status contradiction", result.stdout)
        self.assertIn("says all 15 gates are open", result.stdout)

    def test_empty_gate_parse_fails_loudly(self) -> None:
        result = self.run_release_gates("# Master Plan without release gates\n")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("ERROR: no RG release gates found", result.stderr)

    def test_missing_rg_task_fails_loudly(self) -> None:
        result = self.run_release_gates(plan_with_gates(excluded_gate=9))

        self.assertNotEqual(0, result.returncode)
        self.assertIn("ERROR: expected RG-1 through RG-15", result.stderr)

    def test_completed_rg7_requires_distinct_relay_hosts(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
            ),
            deploy_config="""
servers:
  web:
    hosts:
      - bold-hopper-vps
    labels:
      app.vauchi.operator: relay-operator
accessories:
  ohttp-relay:
    host: bold-hopper-vps
    labels:
      app.vauchi.operator: gateway-operator
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-7 release config failure", result.stdout)
        self.assertIn("application relay and OHTTP relay share host", result.stdout)

    def test_completed_rg7_requires_distinct_operator_labels(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
            ),
            deploy_config="""
servers:
  web:
    hosts:
      - relay-host
    labels:
      app.vauchi.operator: same-operator
accessories:
  ohttp-relay:
    host: gateway-host
    labels:
      app.vauchi.operator: same-operator
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-7 release config failure", result.stdout)
        self.assertIn("operator identities are not distinct", result.stdout)

    def test_completed_rg7_accepts_distinct_host_and_operator(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
            ),
            deploy_config="""
servers:
  web:
    hosts:
      - relay-host
    labels:
      app.vauchi.operator: relay-operator
accessories:
  ohttp-relay:
    host: gateway-host
    labels:
      app.vauchi.operator: gateway-operator
""",
        )

        self.assertEqual(0, result.returncode)
        self.assertIn("All hard gates passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
