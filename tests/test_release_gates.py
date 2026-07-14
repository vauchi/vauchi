# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

JUSTFILE = Path(sys.argv.pop(1)).resolve()

CANONICAL_SHIP_CRITERIA = """
**Ship criteria**

| Criterion | Required state | Classification |
|-----------|----------------|----------------|
| Release gates RG-1 through RG-15 | complete | hard |
| Protocol v2 | finalized | hard |
| E2E ignored tests | no more than 5 | hard |
| Accessibility acceptance (RG-12) | every frontend passes | hard |
"""

CHECKED_SHIP_CRITERIA = """
**Ship criteria**

| Criterion | Required state | Classification |
|-----------|----------------|----------------|
| Release gates RG-1 through RG-15 | complete | hard |
| [x] Protocol v2 | finalized | hard |
| [x] E2E ignored tests | no more than 5 | hard |
| Accessibility acceptance (RG-12) | every frontend passes | hard |
"""


def plan_with_gates(
    completed_gate: int | None = None,
    excluded_gate: int | None = None,
    all_completed: bool = False,
    status_line: str = "All 15 release gates are open.",
    ship_criteria: str | None = CANONICAL_SHIP_CRITERIA,
    extra_body: str = "",
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
            ship_criteria or "",
            "",
            extra_body,
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
        self,
        plan: str,
        deploy_config: str | None = None,
        adr_065: str | None = None,
        ignored_test_count: int | None = None,
        core_tags: list[str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workspace = Path(temporary_directory)
            plan_path = workspace / "_private/docs/planning/master-plan.plan.md"
            plan_path.parent.mkdir(parents=True)
            plan_path.write_text(plan)
            if adr_065 is not None:
                adr_path = (
                    workspace
                    / "_private/docs/decisions/"
                    "adr-065-first-release-protocol-version-contract.md"
                )
                adr_path.parent.mkdir(parents=True)
                adr_path.write_text(adr_065)
            if ignored_test_count is not None:
                e2e_tests = workspace / "e2e/tests/it/ignored_tests.rs"
                e2e_tests.parent.mkdir(parents=True)
                e2e_tests.write_text(
                    "\n".join(
                        [
                            "#[ignore]\n#[test]\nfn ignored_case_"
                            f"{index}() {{}}"
                            for index in range(ignored_test_count)
                        ]
                    )
                )
            if core_tags is not None:
                core_path = workspace / "core"
                core_path.mkdir()
                subprocess.run(["git", "init", "--quiet"], cwd=core_path, check=True)
                subprocess.run(
                    ["git", "config", "user.email", "test@example.invalid"],
                    cwd=core_path,
                    check=True,
                )
                subprocess.run(
                    ["git", "config", "user.name", "Release Gate Test"],
                    cwd=core_path,
                    check=True,
                )
                (core_path / "README.md").write_text("test core repo\n")
                subprocess.run(["git", "add", "README.md"], cwd=core_path, check=True)
                subprocess.run(
                    ["git", "commit", "--quiet", "-m", "test core repo"],
                    cwd=core_path,
                    check=True,
                )
                for tag in core_tags:
                    subprocess.run(["git", "tag", tag], cwd=core_path, check=True)
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

    def test_missing_ship_criteria_table_fails_loudly(self) -> None:
        result = self.run_release_gates(plan_with_gates(ship_criteria=None))

        self.assertNotEqual(0, result.returncode)
        self.assertIn("ERROR: Ship criteria table not found", result.stderr)

    def test_missing_expected_hard_ship_criterion_fails_loudly(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                ship_criteria="""
**Ship criteria**

| Criterion | Required state | Classification |
|-----------|----------------|----------------|
| Release gates RG-1 through RG-15 | complete | hard |
| Protocol v2 | finalized | hard |
""",
            )
        )

        self.assertNotEqual(0, result.returncode)
        self.assertIn("ERROR: expected hard ship criteria", result.stderr)
        self.assertIn("E2E ignored tests", result.stderr)

    def test_completed_rg7_requires_distinct_relay_hosts(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
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
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
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
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
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
            adr_065="""
# ADR-065: First-Release Protocol Version Contract

**Status**: Accepted
""",
            ignored_test_count=5,
            core_tags=["v0.55.2"],
        )

        self.assertEqual(0, result.returncode)
        self.assertIn("All hard gates passed", result.stdout)

    def test_open_hard_ship_criteria_block_release(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria="""
**Ship criteria**

| Criterion | Required state | Classification |
|-----------|----------------|----------------|
| Release gates RG-1 through RG-15 | complete | hard |
| Protocol v2 | finalized | hard |
| E2E ignored tests | no more than 5 | hard |
| Accessibility acceptance (RG-12) | every frontend passes | hard |
""",
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

        self.assertEqual(1, result.returncode)
        self.assertIn("HARD SHIP CRITERIA (0/2 done)", result.stdout)
        self.assertIn("Protocol v2", result.stdout)
        self.assertIn("E2E ignored tests", result.stdout)

    def test_checked_e2e_ignored_tests_require_e2e_tree(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
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
            adr_065="""
# ADR-065: First-Release Protocol Version Contract

**Status**: Accepted
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("E2E ignored-test evidence failure", result.stdout)
        self.assertIn("e2e test tree is missing", result.stdout)

    def test_checked_e2e_ignored_tests_require_count_at_or_below_ceiling(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
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
            adr_065="""
# ADR-065: First-Release Protocol Version Contract

**Status**: Accepted
""",
            ignored_test_count=6,
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("E2E ignored-test evidence failure", result.stdout)
        self.assertIn("6 ignored Rust E2E test(s), expected no more than 5", result.stdout)

    def test_completed_convergence_gates_require_current_core_binding_tag(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body=(
                    "ADR-065 defines Protocol v2 finalization. "
                    "Core !1391 publishes current core main as 0.55.2 bindings."
                ),
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
            adr_065="""
# ADR-065: First-Release Protocol Version Contract

**Status**: Accepted
""",
            ignored_test_count=5,
            core_tags=["v0.55.1"],
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("Core binding release evidence failure", result.stdout)
        self.assertIn("required core tag v0.55.2 is missing", result.stdout)

    def test_checked_protocol_v2_requires_accepted_adr_065(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
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
            adr_065="""
# ADR-065: First-Release Protocol Version Contract

**Status**: Proposed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("Protocol v2 evidence failure", result.stdout)
        self.assertIn("ADR-065 status is Proposed, not Accepted", result.stdout)

    def test_checked_protocol_v2_requires_master_plan_adr_065_citation(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
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
            adr_065="""
# ADR-065: First-Release Protocol Version Contract

**Status**: Accepted
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("Protocol v2 evidence failure", result.stdout)
        self.assertIn("master plan does not cite ADR-065", result.stdout)

    def test_checked_hard_ship_criteria_can_pass_with_completed_rg_gates(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria="""
**Ship criteria**

| Criterion | Required state | Classification |
|-----------|----------------|----------------|
| Release gates RG-1 through RG-15 | complete | hard |
| [x] Protocol v2 | finalized | hard |
| [x] E2E ignored tests | no more than 5 | hard |
| Accessibility acceptance (RG-12) | every frontend passes | hard |
""",
                extra_body="ADR-065 defines Protocol v2 finalization.",
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
            adr_065="""
# ADR-065: First-Release Protocol Version Contract

**Status**: Accepted
""",
            ignored_test_count=5,
            core_tags=["v0.55.2"],
        )

        self.assertEqual(0, result.returncode)
        self.assertIn("HARD SHIP CRITERIA (2/2 done)", result.stdout)
        self.assertIn("All hard gates passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
