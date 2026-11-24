# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from certification_fixture import REVISION, fresh_report

JUSTFILE = Path(sys.argv.pop(1)).resolve()

CANONICAL_SHIP_CRITERIA = """
**Ship criteria**

| Criterion | Required state | Classification |
|-----------|----------------|----------------|
| Release gates RG-1 through RG-16 | complete | hard |
| Protocol v2 | finalized | hard |
| E2E ignored tests | no more than 5 | hard |
| Accessibility acceptance (RG-12) | every frontend passes | hard |
"""

SAME_OPERATOR_DISTINCT_HOSTS = """
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
"""

def production_config(host_variable: str) -> str:
    return f"""<%
  deploy_host = ENV.fetch("{host_variable}")
%>
servers:
  web:
    hosts:
      - <%= deploy_host %>
"""


def service_config(operator: str | None) -> str:
    labels = f"\nlabels:\n  app.vauchi.operator: {operator}\n" if operator else "\n"
    return f"service: fixture{labels}"


def service_configs_from(combined: str) -> dict[str, str]:
    """Each service's own Kamal config, carrying the operator label the
    combined fixture names for it (relay first, OHTTP relay second): the
    verifier reads operators there, so fixtures written in the combined
    shape keep their meaning."""
    operators = re.findall(r"app\.vauchi\.operator:\s*(\S+)", combined)
    return {
        "deploy.relay.yml": service_config(operators[0] if operators else None),
        "deploy.ohttp-relay.yml": service_config(
            operators[1] if len(operators) > 1 else None
        ),
    }


# Where the relay and OHTTP app deploys actually land: their production
# destination configs, each taking its host from a CI variable.
DISTINCT_PRODUCTION_HOSTS = {
    "deploy.relay.production.yml": production_config("RELAY_DEPLOY_HOST"),
    "deploy.ohttp-relay.production.yml": production_config("OHTTP_DEPLOY_HOST"),
}


CHECKED_SHIP_CRITERIA = """
**Ship criteria**

| Criterion | Required state | Classification |
|-----------|----------------|----------------|
| Release gates RG-1 through RG-16 | complete | hard |
| [x] Protocol v2 | finalized | hard |
| [x] E2E ignored tests | no more than 5 | hard |
| Accessibility acceptance (RG-12) | every frontend passes | hard |
"""


def plan_with_gates(
    completed_gate: int | None = None,
    excluded_gate: int | None = None,
    all_completed: bool = False,
    status_line: str = "All 16 release gates are open.",
    ship_criteria: str | None = CANONICAL_SHIP_CRITERIA,
    extra_body: str = "",
) -> str:
    gates = []
    for gate_number in range(1, 17):
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
        production_configs: dict[str, str] | None = None,
        adr_065: str | None = None,
        ignored_test_count: int | None = None,
        core_tags: list[str] | None = None,
        humble_todo_count: int | None = None,
        web_demo_todo_count: int | None = None,
        windows_display_todo_count: int | None = None,
        humble_release_zero_exit: int = 0,
        humble_release_zero_output: str = "humble_check: release-zero gate passed",
        usability_evidence: str | None = None,
        accessibility_evidence: str | None = None,
        privacy_evidence: str | None = None,
        ohttp_fail_closed_evidence: str | None = None,
        frontend_journey_evidence: str | None = None,
        local_two_user_evidence: str | None = None,
        ohttp_relay_two_user_evidence: str | None = None,
        six_device_convergence_evidence: str | None = None,
        every_linked_device_evidence: str | None = None,
        selectable_exchange_evidence: str | None = None,
        long_lived_contact_evidence: str | None = None,
        production_distribution_evidence: str | None = None,
        user_data_convergence_evidence: str | None = None,
        certification_evidence: dict | None = None,
        checklist_counts: tuple[int, int, int, int] | None = (0, 1, 0, 1),
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workspace = Path(temporary_directory)
            env = os.environ.copy()
            plan_path = workspace / "_private/docs/planning/master-plan.plan.md"
            plan_path.parent.mkdir(parents=True)
            plan_path.write_text(plan, encoding="utf-8")
            if checklist_counts is not None:
                sc_open, sc_done, d_open, d_done = checklist_counts
                counter = workspace / "_private/scripts/ship-checklist.py"
                counter.parent.mkdir(parents=True)
                # The counter belongs to the private repo, absent from root CI.
                counter.write_text(
                    "import sys\n"
                    "if sys.argv[1:] != ['--count']:\n"
                    "    sys.exit('release-gates must only count the checklist')\n"
                    f"print('SC open {sc_open}, closed {sc_done}; "
                    f"decisions open {d_open}, recorded {d_done}')\n"
                    f"sys.exit({int(bool(sc_open or d_open))})\n"
                , encoding="utf-8")
            if certification_evidence is not None:
                report_path = workspace / "target/release-evidence/certification.json"
                report_path.parent.mkdir(parents=True)
                report_path.write_text(json.dumps(certification_evidence), encoding="utf-8")
            if adr_065 is not None:
                adr_path = (
                    workspace
                    / "_private/docs/decisions/"
                    "adr-065-first-release-protocol-version-contract.md"
                )
                adr_path.parent.mkdir(parents=True)
                adr_path.write_text(adr_065, encoding="utf-8")
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
                , encoding="utf-8")
            if core_tags is not None:
                core_path = workspace / "core"
                core_path.mkdir()
                tag_list = workspace / "core-tags.txt"
                tag_list.write_text("\n".join(core_tags), encoding="utf-8")
                fake_bin = workspace / "bin"
                fake_bin.mkdir()
                fake_git = fake_bin / "git"
                fake_git.write_text(
                    "\n".join(
                        [
                            "#!/bin/sh",
                            'if [ "$1" = "-C" ] && [ "$2" = "e2e" ] && '
                            '[ "$3" = "rev-parse" ] && [ "$4" = "HEAD" ]; then',
                            f'  printf "%s\\n" "{REVISION}"',
                            "  exit 0",
                            "fi",
                            'if [ "$1" = "-C" ] && [ "$3" = "tag" ] && '
                            '[ "$4" = "--list" ]; then',
                            '  if grep -Fx -- "$5" '
                            '"$RELEASE_GATE_TEST_CORE_TAGS" >/dev/null; then',
                            '    printf "%s\\n" "$5"',
                            "  fi",
                            "  exit 0",
                            "fi",
                            'printf "%s\\n" "unsupported fake git invocation" >&2',
                            "exit 2",
                            "",
                        ]
                    )
                , encoding="utf-8")
                fake_git.chmod(0o755)
                env["PATH"] = f"{fake_bin}{os.pathsep}{env.get('PATH', '')}"
                env["RELEASE_GATE_TEST_CORE_TAGS"] = str(tag_list)
            if humble_todo_count is not None:
                android_source = workspace / "android/app/src/main/kotlin/Humble.kt"
                android_source.parent.mkdir(parents=True)
                android_source.write_text(
                    "\n".join(
                        [
                            f"// TODO(HUMBLE): remaining migration {index}"
                            for index in range(humble_todo_count)
                        ]
                    )
                    or "// native UI migration complete\n"
                , encoding="utf-8")
            if web_demo_todo_count is not None:
                web_demo_source = workspace / "web-demo/src/humble.ts"
                web_demo_source.parent.mkdir(parents=True)
                web_demo_source.write_text(
                    "\n".join(
                        [
                            f"// TODO(HUMBLE): remaining migration {index}"
                            for index in range(web_demo_todo_count)
                        ]
                    )
                    or "// web demo migration complete\n"
                , encoding="utf-8")
            if windows_display_todo_count is not None:
                windows_display_source = (
                    workspace / "windows-display/src/Vauchi.Display/Humble.cs"
                )
                windows_display_source.parent.mkdir(parents=True)
                windows_display_source.write_text(
                    "\n".join(
                        [
                            f"// TODO(HUMBLE): remaining migration {index}"
                            for index in range(windows_display_todo_count)
                        ]
                    )
                , encoding="utf-8")
            humble_checker =workspace / "scripts/scripts/humble_check.py"
            humble_checker.parent.mkdir(parents=True)
            humble_checker.write_text(
                "\n".join(
                    [
                        "import sys",
                        "required = {'--workspace-root', '--config', '--check', "
                        "'--release-zero'}",
                        "missing = required.difference(sys.argv[1:])",
                        "if missing:",
                        "    print(f'missing release-zero argument(s): "
                        "{sorted(missing)}')",
                        "    sys.exit(2)",
                        f"print({humble_release_zero_output!r})",
                        f"sys.exit({humble_release_zero_exit})",
                        "",
                    ]
                )
            , encoding="utf-8")
            (workspace / "scripts/scripts/humble_check_rules.json").write_text("{}\n", encoding="utf-8")
            (workspace / "scripts/scripts/humble_check.baseline.json").write_text("{}\n", encoding="utf-8")
            if usability_evidence is not None:
                usability_path = (
                    workspace
                    / "_private/docs/testing/usability/"
                    "first-release-unassisted-sessions.md"
                )
                usability_path.parent.mkdir(parents=True)
                usability_path.write_text(usability_evidence, encoding="utf-8")
            if accessibility_evidence is not None:
                accessibility_path = (
                    workspace
                    / "_private/docs/testing/accessibility/"
                    "native-frontend-acceptance.md"
                )
                accessibility_path.parent.mkdir(parents=True)
                accessibility_path.write_text(accessibility_evidence, encoding="utf-8")
            if privacy_evidence is not None:
                privacy_path = (
                    workspace
                    / "_private/docs/testing/privacy/"
                    "service-boundary-no-decryptability.md"
                )
                privacy_path.parent.mkdir(parents=True)
                privacy_path.write_text(privacy_evidence, encoding="utf-8")
            if ohttp_fail_closed_evidence is not None:
                ohttp_path = (
                    workspace
                    / "_private/docs/testing/privacy/"
                    "ohttp-fail-closed.md"
                )
                ohttp_path.parent.mkdir(parents=True, exist_ok=True)
                ohttp_path.write_text(ohttp_fail_closed_evidence, encoding="utf-8")
            if frontend_journey_evidence is not None:
                journey_path = (
                    workspace
                    / "_private/docs/testing/frontend/"
                    "core-user-journey.md"
                )
                journey_path.parent.mkdir(parents=True)
                journey_path.write_text(frontend_journey_evidence, encoding="utf-8")
            if local_two_user_evidence is not None:
                local_two_user_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "local-two-user-propagation.md"
                )
                local_two_user_path.parent.mkdir(parents=True)
                local_two_user_path.write_text(local_two_user_evidence, encoding="utf-8")
            if ohttp_relay_two_user_evidence is not None:
                ohttp_relay_two_user_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "ohttp-relay-two-user-propagation.md"
                )
                ohttp_relay_two_user_path.parent.mkdir(parents=True, exist_ok=True)
                ohttp_relay_two_user_path.write_text(ohttp_relay_two_user_evidence, encoding="utf-8")
            if six_device_convergence_evidence is not None:
                six_device_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "six-device-convergence.md"
                )
                six_device_path.parent.mkdir(parents=True, exist_ok=True)
                six_device_path.write_text(six_device_convergence_evidence, encoding="utf-8")
            if every_linked_device_evidence is not None:
                every_device_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "every-linked-device-exchange.md"
                )
                every_device_path.parent.mkdir(parents=True, exist_ok=True)
                every_device_path.write_text(every_linked_device_evidence, encoding="utf-8")
            if selectable_exchange_evidence is not None:
                selectable_exchange_path = (
                    workspace
                    / "_private/docs/testing/usability/"
                    "selectable-exchange-mode-acceptance.md"
                )
                selectable_exchange_path.parent.mkdir(parents=True, exist_ok=True)
                selectable_exchange_path.write_text(selectable_exchange_evidence, encoding="utf-8")
            if long_lived_contact_evidence is not None:
                long_lived_contact_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "long-lived-contact-continuity.md"
                )
                long_lived_contact_path.parent.mkdir(parents=True, exist_ok=True)
                long_lived_contact_path.write_text(long_lived_contact_evidence, encoding="utf-8")
            if production_distribution_evidence is not None:
                production_distribution_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "production-distribution.md"
                )
                production_distribution_path.parent.mkdir(parents=True, exist_ok=True)
                production_distribution_path.write_text(production_distribution_evidence, encoding="utf-8")
            if user_data_convergence_evidence is not None:
                user_data_convergence_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "user-data-convergence.md"
                )
                user_data_convergence_path.parent.mkdir(parents=True, exist_ok=True)
                user_data_convergence_path.write_text(user_data_convergence_evidence, encoding="utf-8")
            if deploy_config is not None:
                deploy_path = workspace / "_private/infra/config/deploy.combined.yml"
                deploy_path.parent.mkdir(parents=True)
                deploy_path.write_text(deploy_config, encoding="utf-8")
                configs = dict(DISTINCT_PRODUCTION_HOSTS)
                configs.update(service_configs_from(deploy_config))
                configs.update(production_configs or {})
                for name, text in configs.items():
                    if text is not None:
                        (deploy_path.parent / name).write_text(text, encoding="utf-8")
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
                env=env,
            )

    def test_open_rg_tasks_block_release(self) -> None:
        result = self.run_release_gates(plan_with_gates())

        self.assertEqual(1, result.returncode)
        self.assertIn("Production Release Readiness", result.stdout)
        self.assertNotIn("v0.2.0", result.stdout)
        self.assertIn("HARD GATES (0/16 done)", result.stdout)
        self.assertIn("16 HARD GATE(s) block release", result.stdout)

    def test_checked_rg_task_counts_as_done(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                completed_gate=1,
                status_line="14 release gates are open.",
            )
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("HARD GATES (1/16 done)", result.stdout)
        self.assertIn("15 HARD GATE(s) block release", result.stdout)

    def test_checked_rg_task_contradicts_all_open_status(self) -> None:
        result = self.run_release_gates(plan_with_gates(completed_gate=1))

        self.assertEqual(1, result.returncode)
        self.assertIn("master-plan status contradiction", result.stdout)
        self.assertIn("says all 16 gates are open", result.stdout)

    def test_empty_gate_parse_fails_loudly(self) -> None:
        result = self.run_release_gates("# Master Plan without release gates\n")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("ERROR: no RG release gates found", result.stderr)

    def test_missing_rg_task_fails_loudly(self) -> None:
        result = self.run_release_gates(plan_with_gates(excluded_gate=9))

        self.assertNotEqual(0, result.returncode)
        self.assertIn("ERROR: expected RG-1 through RG-16", result.stderr)

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
| Release gates RG-1 through RG-16 | complete | hard |
| Protocol v2 | finalized | hard |
""",
            )
        )

        self.assertNotEqual(0, result.returncode)
        self.assertIn("ERROR: expected hard ship criteria", result.stderr)
        self.assertIn("E2E ignored tests", result.stderr)

    def test_completed_rg7_reads_operators_from_each_services_own_config(
        self,
    ) -> None:
        # After #30 the OHTTP relay is no accessory of the combined config:
        # it deploys from deploy.ohttp-relay.yml to its own host. Hosts and
        # operators come from each service's configs, not the combined file.
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
""",
            production_configs={
                "deploy.relay.yml": service_config("relay-operator"),
                "deploy.ohttp-relay.yml": service_config("gateway-operator"),
            },
        )

        self.assertNotIn("RG-7 release config failure", result.stdout)

    def test_completed_rg7_requires_an_operator_label_on_each_service(
        self,
    ) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            deploy_config=SAME_OPERATOR_DISTINCT_HOSTS,
            production_configs={"deploy.ohttp-relay.yml": service_config(None)},
        )

        self.assertEqual(1, result.returncode)
        self.assertIn(
            "OHTTP relay operator identity label app.vauchi.operator "
            "is not declared",
            result.stdout,
        )

    def test_completed_rg7_fails_when_both_hops_deploy_to_one_host_variable(
        self,
    ) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            deploy_config=SAME_OPERATOR_DISTINCT_HOSTS,
            production_configs={
                "deploy.relay.production.yml": production_config("DEPLOY_HOST"),
                "deploy.ohttp-relay.production.yml": production_config(
                    "DEPLOY_HOST"
                ),
            },
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-7 release config failure", result.stdout)
        self.assertIn(
            "relay and OHTTP relay production deploys share host source "
            "'env DEPLOY_HOST'",
            result.stdout,
        )

    def test_completed_rg7_fails_without_the_ohttp_production_config(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            deploy_config=SAME_OPERATOR_DISTINCT_HOSTS,
            production_configs={"deploy.ohttp-relay.production.yml": None},
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-7 release config failure", result.stdout)
        self.assertIn("deploy.ohttp-relay.production.yml is missing", result.stdout)

    def test_completed_rg7_requires_distinct_operator_labels(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body=(
                    "ADR-065 defines Protocol v2 finalization.\n\n"
                    "**Release stage**: release"
                ),
            ),
            deploy_config=SAME_OPERATOR_DISTINCT_HOSTS,
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-7 release config failure", result.stdout)
        self.assertIn("operator identities are not distinct", result.stdout)

    def test_completed_rg7_without_release_stage_enforces_operators(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            deploy_config=SAME_OPERATOR_DISTINCT_HOSTS,
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-7 release config failure", result.stdout)
        self.assertIn("operator identities are not distinct", result.stdout)

    def test_completed_rg7_alpha_stage_defers_distinct_operators(self) -> None:
        stage_lines = {
            "alpha": "**Release stage**: alpha",
            "beta": "> **Release stage**: beta",
        }
        for stage, stage_line in stage_lines.items():
            with self.subTest(stage=stage):
                result = self.run_release_gates(
                    plan_with_gates(
                        all_completed=True,
                        status_line="All hard gates passed.",
                        ship_criteria=CHECKED_SHIP_CRITERIA,
                        extra_body=(
                            "ADR-065 defines Protocol v2 finalization.\n\n"
                            f"{stage_line}"
                        ),
                    ),
                    deploy_config=SAME_OPERATOR_DISTINCT_HOSTS,
                )

                self.assertNotIn("RG-7 release config failure", result.stdout)
                self.assertNotIn(
                    "operator identities are not distinct", result.stdout
                )
                self.assertIn(
                    "RG-7 distinct-operator requirement deferred", result.stdout
                )
                self.assertIn("same-operator", result.stdout)

    def test_completed_rg7_alpha_stage_still_requires_distinct_hosts(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body=(
                    "ADR-065 defines Protocol v2 finalization.\n\n"
                    "**Release stage**: alpha"
                ),
            ),
            deploy_config=SAME_OPERATOR_DISTINCT_HOSTS,
            production_configs={
                "deploy.relay.production.yml": production_config("DEPLOY_HOST"),
                "deploy.ohttp-relay.production.yml": production_config(
                    "DEPLOY_HOST"
                ),
            },
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-7 release config failure", result.stdout)
        self.assertIn(
            "relay and OHTTP relay production deploys share host source",
            result.stdout,
        )

    def _completed_gates_result(
        self, certification_evidence, *, checklist_counts=(0, 1, 0, 1)
    ):
        result = self.run_release_gates(
            certification_evidence=certification_evidence,
            checklist_counts=checklist_counts,
            plan=plan_with_gates(
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
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
            privacy_evidence="""
# Service-boundary no-decryptability evidence

relay storage: inspected
ohttp relay storage: inspected
logs: inspected
metrics: inspected
traces: inspected
configuration: inspected
service-held secrets: inspected
plaintext/key access: none
""",
            ohttp_fail_closed_evidence="""
# OHTTP fail-closed evidence

supported production consumers: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

android create card: passed
android edit card: passed
android exchange contact: passed
android receive update: passed
android ignore: passed
ios create card: passed
ios edit card: passed
ios exchange contact: passed
ios receive update: passed
ios ignore: passed
macos create card: passed
macos edit card: passed
macos exchange contact: passed
macos receive update: passed
macos ignore: passed
windows create card: passed
windows edit card: passed
windows exchange contact: passed
windows receive update: passed
windows ignore: passed
linux-app/gtk-display create card: passed
linux-app/gtk-display edit card: passed
linux-app/gtk-display exchange contact: passed
linux-app/gtk-display receive update: passed
linux-app/gtk-display ignore: passed
linux-app/qt-display create card: passed
linux-app/qt-display edit card: passed
linux-app/qt-display exchange contact: passed
linux-app/qt-display receive update: passed
linux-app/qt-display ignore: passed
cli create card: passed
cli edit card: passed
cli exchange contact: passed
cli receive update: passed
cli ignore: passed
tui create card: passed
tui edit card: passed
tui exchange contact: passed
tui receive update: passed
tui ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
in-person local-only no-relay run: passed
offline mode blocks ohttp+relay: passed
real-device in-person ble exchange: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
default online sync via ohttp+relay: passed
in-person to ohttp+relay channel change: passed
ohttp+relay to in-person channel change: passed
alternating channel updates: passed
both privacy hops: passed
ohttp relay: passed
application relay: passed
exchange propagation: passed
update propagation: passed
exact-value assertions: passed
blocking e2e pipeline: passed
""",
            six_device_convergence_evidence="""
# Six-device convergence evidence

six-device topology: passed
alice devices: a1, a2, a3
bob devices: b1, b2, b3
three linked devices per user: passed
socket-backed topology: passed
real link ceremony: passed
convergence at every target: passed
reorder and duplicate handling: passed
simultaneous edits: passed
offline catch-up: passed
relay restart during delivery: passed
device revocation: passed
device replacement: passed
clock skew: passed
""",
            every_linked_device_evidence="""
# Every linked device exchange evidence

active linked devices: a1, a2, a3, b1, b2, b3
exchange from every active device: passed
update from every active device: passed
secondary device initiation: passed
third device initiation: passed
independent per-device ratchet sessions: passed
nine-pair ratchet matrix: passed
sender-token wire inspection: passed
bob-originated updates: passed
""",
            selectable_exchange_evidence="""
# Selectable exchange-mode acceptance evidence

selectable exchange modes: passed
functionality: passed
latency: accepted
enjoyment: accepted
accessibility: passed
cancellation: passed
retry: passed
recovery: passed
""",
            long_lived_contact_evidence="""
# Long-lived contact continuity evidence

long-lived contact continuity: passed
channel-independent updates: passed
composite longitudinal scenario: passed
clock-driven scenario: passed
exchange remains useful: passed
permitted detail changes: passed
offline catch-up: passed
device add/revoke/replace: passed
archive/unarchive: passed
block behavior: passed
ignore semantics: accepted
ignored relationship behavior: passed
no re-exchange required: passed
""",
            production_distribution_evidence="""
# Production distribution evidence

core binding tag: v0.55.2
supported platforms: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
android signing: passed
android packaging: passed
android installation: passed
android distribution-channel acceptance: passed
android store submission: passed
ios signing: passed
ios packaging: passed
ios installation: passed
ios distribution-channel acceptance: passed
ios store submission: passed
ios notarization: passed
macos signing: passed
macos packaging: passed
macos installation: passed
macos distribution-channel acceptance: passed
macos notarization: passed
windows signing: passed
windows packaging: passed
windows installation: passed
windows distribution-channel acceptance: passed
linux-app/gtk-display signing: passed
linux-app/gtk-display packaging: passed
linux-app/gtk-display installation: passed
linux-app/gtk-display distribution-channel acceptance: passed
linux-app/qt-display signing: passed
linux-app/qt-display packaging: passed
linux-app/qt-display installation: passed
linux-app/qt-display distribution-channel acceptance: passed
cli signing: passed
cli packaging: passed
cli installation: passed
cli distribution-channel acceptance: passed
tui signing: passed
tui packaging: passed
tui installation: passed
tui distribution-channel acceptance: passed
""",
            user_data_convergence_evidence="""
# User data convergence evidence

core binding tag: v0.55.2
user data convergence: passed
complete owner-private state convergence: passed
myinfo update/removal: passed
presentation cards: passed
group identity/membership/visibility/overrides: passed
tag change/deletion: passed
contacts/private notes: passed
all six devices synchronized: passed
canonical owner-private state: passed
permitted presentation state only: passed
no private state leaked to Bob or relay: passed
ADR-020 deterministic convergence: passed
""",
        )

        return result

    def test_completed_rg7_accepts_distinct_host_and_operator(self) -> None:
        result = self._completed_gates_result(fresh_report())
        self.assertEqual(0, result.returncode)
        self.assertIn("All hard gates passed", result.stdout)

    def test_open_checklist_items_block_otherwise_completed_release(self) -> None:
        for counts, summary in (
            ((1, 0, 0, 1), "SC open 1, closed 0; decisions open 0, recorded 1"),
            ((0, 1, 1, 0), "SC open 0, closed 1; decisions open 1, recorded 0"),
        ):
            with self.subTest(counts=counts):
                result = self._completed_gates_result(
                    fresh_report(), checklist_counts=counts
                )
                self.assertEqual(1, result.returncode)
                self.assertIn(summary, result.stdout)
                self.assertIn("ship checklist blocks release", result.stdout)
                self.assertNotIn("All hard gates passed", result.stdout)

    def test_completed_checklist_is_counted_without_running_its_checks(self) -> None:
        result = self._completed_gates_result(fresh_report())

        self.assertEqual(0, result.returncode)
        self.assertIn("SC open 0, closed 1; decisions open 0, recorded 1", result.stdout)
        self.assertIn("All hard gates passed", result.stdout)

    def test_missing_checklist_counter_blocks_otherwise_completed_release(self) -> None:
        result = self._completed_gates_result(
            fresh_report(), checklist_counts=None
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("ship checklist blocks release", result.stdout)
        self.assertIn("ship-checklist.py", result.stdout)
        self.assertNotIn("All hard gates passed", result.stdout)

    def test_completed_gates_reject_missing_or_stale_certification_report(self) -> None:
        stale = fresh_report()
        stale["pipeline"]["created_at"] = "2020-01-01T00:00:00Z"
        for evidence in (None, stale):
            with self.subTest(evidence="missing" if evidence is None else "stale"):
                result = self._completed_gates_result(evidence)
                self.assertEqual(1, result.returncode)
                self.assertIn("certification evidence", result.stdout)
                self.assertNotIn("All hard gates passed", result.stdout)

    def test_open_hard_ship_criteria_block_release(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria="""
**Ship criteria**

| Criterion | Required state | Classification |
|-----------|----------------|----------------|
| Release gates RG-1 through RG-16 | complete | hard |
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

    def test_rg1_rejects_block_only_evidence_for_the_ignore_journey(self) -> None:
        consumers = (
            "android", "ios", "macos", "windows", "linux-app/gtk-display",
            "linux-app/qt-display", "cli", "tui",
        )
        journeys = ("create card", "edit card", "exchange contact", "receive update")
        evidence = "\n".join(
            [f"{consumer} {journey}: passed" for consumer in consumers for journey in journeys]
            + [f"{consumer} block or ignore: passed" for consumer in consumers]
        )
        result = self.run_release_gates(
            plan_with_gates(
                completed_gate=1,
                status_line="14 release gates are open.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            frontend_journey_evidence=evidence,
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-1 frontend journey evidence failure", result.stdout)
        for consumer in consumers:
            self.assertIn(f"{consumer} ignore: passed evidence is missing", result.stdout)

    def test_rg2_rejects_direct_relay_instead_of_a_local_only_run(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                completed_gate=2,
                status_line="14 release gates are open.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            local_two_user_evidence="""
local two-user: passed
non-ohttp local run: passed
transport: direct application relay
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-2 local two-user evidence failure", result.stdout)
        self.assertIn("in-person local-only no-relay evidence is missing", result.stdout)
        self.assertIn("offline mode relay blocking evidence is missing", result.stdout)
        self.assertIn("real-device in-person BLE evidence is missing", result.stdout)

    def test_rg3_rejects_missing_reverse_channel_change(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                completed_gate=3,
                status_line="14 release gates are open.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            ohttp_relay_two_user_evidence="""
split-ohttp two-user: passed
in-person to ohttp+relay channel change: passed
both privacy hops: passed
ohttp relay: passed
application relay: passed
exchange propagation: passed
update propagation: passed
exact-value assertions: passed
blocking e2e pipeline: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-3 OHTTP relay evidence failure", result.stdout)
        self.assertIn("OHTTP+relay to in-person channel change evidence is missing", result.stdout)
        self.assertIn("alternating channel update evidence is missing", result.stdout)
        self.assertIn("default OHTTP+relay sync evidence is missing", result.stdout)

    def test_rg15_rejects_missing_channel_independent_continuity(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                completed_gate=15,
                status_line="14 release gates are open.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            long_lived_contact_evidence="""
long-lived contact continuity: passed
composite longitudinal scenario: passed
clock-driven scenario: passed
exchange remains useful: passed
permitted detail changes: passed
offline catch-up: passed
device add/revoke/replace: passed
archive/unarchive: passed
block behavior: passed
ignore semantics: accepted
ignored relationship behavior: passed
no re-exchange required: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-15 long-lived contact evidence failure", result.stdout)
        self.assertIn("channel-independent update continuity evidence is missing", result.stdout)

    def test_completed_rg10_requires_binding_tag_named_by_its_evidence(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                completed_gate=10,
                status_line="14 release gates are open.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            adr_065="""
# ADR-065: First-Release Protocol Version Contract

**Status**: Accepted
""",
            ignored_test_count=5,
            core_tags=["v0.55.2"],
            user_data_convergence_evidence="""
# User data convergence evidence

core binding tag: v0.55.4
user data convergence: passed
complete owner-private state convergence: passed
myinfo update/removal: passed
presentation cards: passed
group identity/membership/visibility/overrides: passed
tag change/deletion: passed
contacts/private notes: passed
all six devices synchronized: passed
canonical owner-private state: passed
permitted presentation state only: passed
no private state leaked to Bob or relay: passed
ADR-020 deterministic convergence: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("Core binding release evidence failure", result.stdout)
        self.assertIn("required core tag v0.55.4 is missing", result.stdout)

    def test_completed_rg10_rejects_noncanonical_binding_tags(self) -> None:
        for tag in ("v0.055.4", "V0.55.4"):
            result = self.run_release_gates(
                plan_with_gates(
                    completed_gate=10,
                    status_line="14 release gates are open.",
                    ship_criteria=CHECKED_SHIP_CRITERIA,
                    extra_body="ADR-065 defines Protocol v2 finalization.",
                ),
                adr_065="""
# ADR-065: First-Release Protocol Version Contract

**Status**: Accepted
""",
                ignored_test_count=5,
                core_tags=[tag],
                user_data_convergence_evidence=f"""
# User data convergence evidence

core binding tag: {tag}
user data convergence: passed
complete owner-private state convergence: passed
myinfo update/removal: passed
presentation cards: passed
group identity/membership/visibility/overrides: passed
tag change/deletion: passed
contacts/private notes: passed
all six devices synchronized: passed
canonical owner-private state: passed
permitted presentation state only: passed
no private state leaked to Bob or relay: passed
ADR-020 deterministic convergence: passed
""",
            )

            with self.subTest(tag=tag):
                self.assertEqual(1, result.returncode)
                self.assertIn("Core binding release evidence failure", result.stdout)
                self.assertIn("must declare exactly one", result.stdout)

    def test_completed_rg10_requires_user_data_convergence_evidence(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                completed_gate=10,
                status_line="14 release gates are open.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body=(
                    "ADR-065 defines Protocol v2 finalization. "
                    "Core !1391 publishes current core main as 0.55.2 bindings."
                ),
            ),
            adr_065="""
# ADR-065: First-Release Protocol Version Contract

**Status**: Accepted
""",
            ignored_test_count=5,
            core_tags=["v0.55.2"],
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-10 user-data convergence evidence failure", result.stdout)
        self.assertIn("user-data-convergence.md is missing", result.stdout)

    def test_completed_rg11_requires_no_humble_todos(self) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=1,
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-11 Humble UI evidence failure", result.stdout)
        self.assertIn("1 TODO(HUMBLE) site(s) remain", result.stdout)

    def test_completed_rg12_requires_native_accessibility_evidence(self) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-12 accessibility evidence failure", result.stdout)
        self.assertIn("native-frontend-acceptance.md is missing", result.stdout)

    def test_completed_rg13_requires_unassisted_usability_evidence(self) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-13 usability evidence failure", result.stdout)
        self.assertIn("first-release-unassisted-sessions.md is missing", result.stdout)

    def test_completed_rg6_requires_service_boundary_privacy_evidence(self) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-6 service-boundary privacy evidence failure", result.stdout)
        self.assertIn("service-boundary-no-decryptability.md is missing", result.stdout)

    def test_completed_rg1_requires_all_frontend_core_journey_evidence(self) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
            privacy_evidence="""
# Service-boundary no-decryptability evidence

relay storage: inspected
ohttp relay storage: inspected
logs: inspected
metrics: inspected
traces: inspected
configuration: inspected
service-held secrets: inspected
plaintext/key access: none
""",
            ohttp_fail_closed_evidence="""
# OHTTP fail-closed evidence

supported production consumers: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-1 frontend journey evidence failure", result.stdout)
        self.assertIn("core-user-journey.md is missing", result.stdout)

    def test_completed_rg2_requires_local_two_user_propagation_evidence(self) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
            privacy_evidence="""
# Service-boundary no-decryptability evidence

relay storage: inspected
ohttp relay storage: inspected
logs: inspected
metrics: inspected
traces: inspected
configuration: inspected
service-held secrets: inspected
plaintext/key access: none
""",
            ohttp_fail_closed_evidence="""
# OHTTP fail-closed evidence

supported production consumers: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

android create card: passed
android edit card: passed
android exchange contact: passed
android receive update: passed
android ignore: passed
ios create card: passed
ios edit card: passed
ios exchange contact: passed
ios receive update: passed
ios ignore: passed
macos create card: passed
macos edit card: passed
macos exchange contact: passed
macos receive update: passed
macos ignore: passed
windows create card: passed
windows edit card: passed
windows exchange contact: passed
windows receive update: passed
windows ignore: passed
linux-app/gtk-display create card: passed
linux-app/gtk-display edit card: passed
linux-app/gtk-display exchange contact: passed
linux-app/gtk-display receive update: passed
linux-app/gtk-display ignore: passed
linux-app/qt-display create card: passed
linux-app/qt-display edit card: passed
linux-app/qt-display exchange contact: passed
linux-app/qt-display receive update: passed
linux-app/qt-display ignore: passed
cli create card: passed
cli edit card: passed
cli exchange contact: passed
cli receive update: passed
cli ignore: passed
tui create card: passed
tui edit card: passed
tui exchange contact: passed
tui receive update: passed
tui ignore: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-2 local two-user evidence failure", result.stdout)
        self.assertIn("local-two-user-propagation.md is missing", result.stdout)

    def test_completed_rg3_requires_ohttp_relay_propagation_evidence(self) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
            privacy_evidence="""
# Service-boundary no-decryptability evidence

relay storage: inspected
ohttp relay storage: inspected
logs: inspected
metrics: inspected
traces: inspected
configuration: inspected
service-held secrets: inspected
plaintext/key access: none
""",
            ohttp_fail_closed_evidence="""
# OHTTP fail-closed evidence

supported production consumers: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

android create card: passed
android edit card: passed
android exchange contact: passed
android receive update: passed
android ignore: passed
ios create card: passed
ios edit card: passed
ios exchange contact: passed
ios receive update: passed
ios ignore: passed
macos create card: passed
macos edit card: passed
macos exchange contact: passed
macos receive update: passed
macos ignore: passed
windows create card: passed
windows edit card: passed
windows exchange contact: passed
windows receive update: passed
windows ignore: passed
linux-app/gtk-display create card: passed
linux-app/gtk-display edit card: passed
linux-app/gtk-display exchange contact: passed
linux-app/gtk-display receive update: passed
linux-app/gtk-display ignore: passed
linux-app/qt-display create card: passed
linux-app/qt-display edit card: passed
linux-app/qt-display exchange contact: passed
linux-app/qt-display receive update: passed
linux-app/qt-display ignore: passed
cli create card: passed
cli edit card: passed
cli exchange contact: passed
cli receive update: passed
cli ignore: passed
tui create card: passed
tui edit card: passed
tui exchange contact: passed
tui receive update: passed
tui ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
in-person local-only no-relay run: passed
offline mode blocks ohttp+relay: passed
real-device in-person ble exchange: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-3 OHTTP relay evidence failure", result.stdout)
        self.assertIn("ohttp-relay-two-user-propagation.md is missing", result.stdout)

    def test_completed_rg4_requires_six_device_convergence_evidence(self) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
            privacy_evidence="""
# Service-boundary no-decryptability evidence

relay storage: inspected
ohttp relay storage: inspected
logs: inspected
metrics: inspected
traces: inspected
configuration: inspected
service-held secrets: inspected
plaintext/key access: none
""",
            ohttp_fail_closed_evidence="""
# OHTTP fail-closed evidence

supported production consumers: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

android create card: passed
android edit card: passed
android exchange contact: passed
android receive update: passed
android ignore: passed
ios create card: passed
ios edit card: passed
ios exchange contact: passed
ios receive update: passed
ios ignore: passed
macos create card: passed
macos edit card: passed
macos exchange contact: passed
macos receive update: passed
macos ignore: passed
windows create card: passed
windows edit card: passed
windows exchange contact: passed
windows receive update: passed
windows ignore: passed
linux-app/gtk-display create card: passed
linux-app/gtk-display edit card: passed
linux-app/gtk-display exchange contact: passed
linux-app/gtk-display receive update: passed
linux-app/gtk-display ignore: passed
linux-app/qt-display create card: passed
linux-app/qt-display edit card: passed
linux-app/qt-display exchange contact: passed
linux-app/qt-display receive update: passed
linux-app/qt-display ignore: passed
cli create card: passed
cli edit card: passed
cli exchange contact: passed
cli receive update: passed
cli ignore: passed
tui create card: passed
tui edit card: passed
tui exchange contact: passed
tui receive update: passed
tui ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
in-person local-only no-relay run: passed
offline mode blocks ohttp+relay: passed
real-device in-person ble exchange: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
default online sync via ohttp+relay: passed
in-person to ohttp+relay channel change: passed
ohttp+relay to in-person channel change: passed
alternating channel updates: passed
both privacy hops: passed
ohttp relay: passed
application relay: passed
exchange propagation: passed
update propagation: passed
exact-value assertions: passed
blocking e2e pipeline: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-4 six-device convergence evidence failure", result.stdout)
        self.assertIn("six-device-convergence.md is missing", result.stdout)

    def test_completed_rg5_requires_every_linked_device_exchange_evidence(self) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
            privacy_evidence="""
# Service-boundary no-decryptability evidence

relay storage: inspected
ohttp relay storage: inspected
logs: inspected
metrics: inspected
traces: inspected
configuration: inspected
service-held secrets: inspected
plaintext/key access: none
""",
            ohttp_fail_closed_evidence="""
# OHTTP fail-closed evidence

supported production consumers: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

android create card: passed
android edit card: passed
android exchange contact: passed
android receive update: passed
android ignore: passed
ios create card: passed
ios edit card: passed
ios exchange contact: passed
ios receive update: passed
ios ignore: passed
macos create card: passed
macos edit card: passed
macos exchange contact: passed
macos receive update: passed
macos ignore: passed
windows create card: passed
windows edit card: passed
windows exchange contact: passed
windows receive update: passed
windows ignore: passed
linux-app/gtk-display create card: passed
linux-app/gtk-display edit card: passed
linux-app/gtk-display exchange contact: passed
linux-app/gtk-display receive update: passed
linux-app/gtk-display ignore: passed
linux-app/qt-display create card: passed
linux-app/qt-display edit card: passed
linux-app/qt-display exchange contact: passed
linux-app/qt-display receive update: passed
linux-app/qt-display ignore: passed
cli create card: passed
cli edit card: passed
cli exchange contact: passed
cli receive update: passed
cli ignore: passed
tui create card: passed
tui edit card: passed
tui exchange contact: passed
tui receive update: passed
tui ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
in-person local-only no-relay run: passed
offline mode blocks ohttp+relay: passed
real-device in-person ble exchange: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
default online sync via ohttp+relay: passed
in-person to ohttp+relay channel change: passed
ohttp+relay to in-person channel change: passed
alternating channel updates: passed
both privacy hops: passed
ohttp relay: passed
application relay: passed
exchange propagation: passed
update propagation: passed
exact-value assertions: passed
blocking e2e pipeline: passed
""",
            six_device_convergence_evidence="""
# Six-device convergence evidence

six-device topology: passed
alice devices: a1, a2, a3
bob devices: b1, b2, b3
three linked devices per user: passed
socket-backed topology: passed
real link ceremony: passed
convergence at every target: passed
reorder and duplicate handling: passed
simultaneous edits: passed
offline catch-up: passed
relay restart during delivery: passed
device revocation: passed
device replacement: passed
clock skew: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-5 every-linked-device evidence failure", result.stdout)
        self.assertIn("every-linked-device-exchange.md is missing", result.stdout)

    def test_completed_rg4_requires_fault_and_lifecycle_coverage(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            # Topology phrases present; the fault and device-lifecycle rows
            # from the ratchet-topology record's six-device matrix contract
            # (offline catch-up, simultaneous edits, retry, duplication,
            # reordering, revocation, replacement, clock skew) are absent.
            six_device_convergence_evidence="""
six-device topology: passed
alice devices: a1, a2, a3
bob devices: b1, b2, b3
three linked devices per user: passed
socket-backed topology: passed
real link ceremony: passed
convergence at every target: passed
reorder and duplicate handling: passed
evidence variant: rg4 fault-lifecycle red fixture
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn(
            "RG-4 six-device convergence evidence failure", result.stdout
        )
        for phrase in (
            "simultaneous edits: passed",
            "offline catch-up: passed",
            "relay restart during delivery: passed",
            "device revocation: passed",
            "device replacement: passed",
            "clock skew: passed",
        ):
            self.assertIn(f"{phrase} evidence is missing", result.stdout)
        self.assertNotIn(
            "reorder/duplicate handling evidence is missing", result.stdout
        )

    def test_completed_rg5_requires_bob_originated_updates(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            # Every current phrase present except the Bob-originated
            # direction the ratchet-topology record lists as remaining work.
            every_linked_device_evidence="""
active linked devices: a1, a2, a3, b1, b2, b3
exchange from every active device: passed
update from every active device: passed
secondary device initiation: passed
third device initiation: passed
independent per-device ratchet sessions: passed
nine-pair ratchet matrix: passed
sender-token wire inspection: passed
evidence variant: rg5 bob-originated red fixture
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-5 every-linked-device evidence failure", result.stdout)
        self.assertIn(
            "bob-originated updates: passed evidence is missing", result.stdout
        )
        self.assertNotIn(
            "nine-pair ratchet matrix evidence is missing", result.stdout
        )

    def test_completed_rg8_requires_ohttp_fail_closed_evidence(self) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
            privacy_evidence="""
# Service-boundary no-decryptability evidence

relay storage: inspected
ohttp relay storage: inspected
logs: inspected
metrics: inspected
traces: inspected
configuration: inspected
service-held secrets: inspected
plaintext/key access: none
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-8 OHTTP fail-closed evidence failure", result.stdout)
        self.assertIn("ohttp-fail-closed.md is missing", result.stdout)

    def test_completed_rg9_requires_selectable_exchange_acceptance_evidence(
        self,
    ) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
            privacy_evidence="""
# Service-boundary no-decryptability evidence

relay storage: inspected
ohttp relay storage: inspected
logs: inspected
metrics: inspected
traces: inspected
configuration: inspected
service-held secrets: inspected
plaintext/key access: none
""",
            ohttp_fail_closed_evidence="""
# OHTTP fail-closed evidence

supported production consumers: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

android create card: passed
android edit card: passed
android exchange contact: passed
android receive update: passed
android ignore: passed
ios create card: passed
ios edit card: passed
ios exchange contact: passed
ios receive update: passed
ios ignore: passed
macos create card: passed
macos edit card: passed
macos exchange contact: passed
macos receive update: passed
macos ignore: passed
windows create card: passed
windows edit card: passed
windows exchange contact: passed
windows receive update: passed
windows ignore: passed
linux-app/gtk-display create card: passed
linux-app/gtk-display edit card: passed
linux-app/gtk-display exchange contact: passed
linux-app/gtk-display receive update: passed
linux-app/gtk-display ignore: passed
linux-app/qt-display create card: passed
linux-app/qt-display edit card: passed
linux-app/qt-display exchange contact: passed
linux-app/qt-display receive update: passed
linux-app/qt-display ignore: passed
cli create card: passed
cli edit card: passed
cli exchange contact: passed
cli receive update: passed
cli ignore: passed
tui create card: passed
tui edit card: passed
tui exchange contact: passed
tui receive update: passed
tui ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
in-person local-only no-relay run: passed
offline mode blocks ohttp+relay: passed
real-device in-person ble exchange: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
default online sync via ohttp+relay: passed
in-person to ohttp+relay channel change: passed
ohttp+relay to in-person channel change: passed
alternating channel updates: passed
both privacy hops: passed
ohttp relay: passed
application relay: passed
exchange propagation: passed
update propagation: passed
exact-value assertions: passed
blocking e2e pipeline: passed
""",
            six_device_convergence_evidence="""
# Six-device convergence evidence

six-device topology: passed
alice devices: a1, a2, a3
bob devices: b1, b2, b3
three linked devices per user: passed
socket-backed topology: passed
real link ceremony: passed
convergence at every target: passed
reorder and duplicate handling: passed
simultaneous edits: passed
offline catch-up: passed
relay restart during delivery: passed
device revocation: passed
device replacement: passed
clock skew: passed
""",
            every_linked_device_evidence="""
# Every linked device exchange evidence

active linked devices: a1, a2, a3, b1, b2, b3
exchange from every active device: passed
update from every active device: passed
secondary device initiation: passed
third device initiation: passed
independent per-device ratchet sessions: passed
nine-pair ratchet matrix: passed
sender-token wire inspection: passed
bob-originated updates: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-9 selectable exchange evidence failure", result.stdout)
        self.assertIn(
            "selectable-exchange-mode-acceptance.md is missing",
            result.stdout,
        )

    def test_completed_rg15_requires_long_lived_contact_continuity_evidence(
        self,
    ) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
            privacy_evidence="""
# Service-boundary no-decryptability evidence

relay storage: inspected
ohttp relay storage: inspected
logs: inspected
metrics: inspected
traces: inspected
configuration: inspected
service-held secrets: inspected
plaintext/key access: none
""",
            ohttp_fail_closed_evidence="""
# OHTTP fail-closed evidence

supported production consumers: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

android create card: passed
android edit card: passed
android exchange contact: passed
android receive update: passed
android ignore: passed
ios create card: passed
ios edit card: passed
ios exchange contact: passed
ios receive update: passed
ios ignore: passed
macos create card: passed
macos edit card: passed
macos exchange contact: passed
macos receive update: passed
macos ignore: passed
windows create card: passed
windows edit card: passed
windows exchange contact: passed
windows receive update: passed
windows ignore: passed
linux-app/gtk-display create card: passed
linux-app/gtk-display edit card: passed
linux-app/gtk-display exchange contact: passed
linux-app/gtk-display receive update: passed
linux-app/gtk-display ignore: passed
linux-app/qt-display create card: passed
linux-app/qt-display edit card: passed
linux-app/qt-display exchange contact: passed
linux-app/qt-display receive update: passed
linux-app/qt-display ignore: passed
cli create card: passed
cli edit card: passed
cli exchange contact: passed
cli receive update: passed
cli ignore: passed
tui create card: passed
tui edit card: passed
tui exchange contact: passed
tui receive update: passed
tui ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
in-person local-only no-relay run: passed
offline mode blocks ohttp+relay: passed
real-device in-person ble exchange: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
default online sync via ohttp+relay: passed
in-person to ohttp+relay channel change: passed
ohttp+relay to in-person channel change: passed
alternating channel updates: passed
both privacy hops: passed
ohttp relay: passed
application relay: passed
exchange propagation: passed
update propagation: passed
exact-value assertions: passed
blocking e2e pipeline: passed
""",
            six_device_convergence_evidence="""
# Six-device convergence evidence

six-device topology: passed
alice devices: a1, a2, a3
bob devices: b1, b2, b3
three linked devices per user: passed
socket-backed topology: passed
real link ceremony: passed
convergence at every target: passed
reorder and duplicate handling: passed
simultaneous edits: passed
offline catch-up: passed
relay restart during delivery: passed
device revocation: passed
device replacement: passed
clock skew: passed
""",
            every_linked_device_evidence="""
# Every linked device exchange evidence

active linked devices: a1, a2, a3, b1, b2, b3
exchange from every active device: passed
update from every active device: passed
secondary device initiation: passed
third device initiation: passed
independent per-device ratchet sessions: passed
nine-pair ratchet matrix: passed
sender-token wire inspection: passed
bob-originated updates: passed
""",
            selectable_exchange_evidence="""
# Selectable exchange-mode acceptance evidence

selectable exchange modes: passed
functionality: passed
latency: accepted
enjoyment: accepted
accessibility: passed
cancellation: passed
retry: passed
recovery: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-15 long-lived contact evidence failure", result.stdout)
        self.assertIn("long-lived-contact-continuity.md is missing", result.stdout)

    def test_completed_rg14_requires_production_distribution_evidence(self) -> None:
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
            core_tags=["v0.55.2"],
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
            privacy_evidence="""
# Service-boundary no-decryptability evidence

relay storage: inspected
ohttp relay storage: inspected
logs: inspected
metrics: inspected
traces: inspected
configuration: inspected
service-held secrets: inspected
plaintext/key access: none
""",
            ohttp_fail_closed_evidence="""
# OHTTP fail-closed evidence

supported production consumers: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

android create card: passed
android edit card: passed
android exchange contact: passed
android receive update: passed
android ignore: passed
ios create card: passed
ios edit card: passed
ios exchange contact: passed
ios receive update: passed
ios ignore: passed
macos create card: passed
macos edit card: passed
macos exchange contact: passed
macos receive update: passed
macos ignore: passed
windows create card: passed
windows edit card: passed
windows exchange contact: passed
windows receive update: passed
windows ignore: passed
linux-app/gtk-display create card: passed
linux-app/gtk-display edit card: passed
linux-app/gtk-display exchange contact: passed
linux-app/gtk-display receive update: passed
linux-app/gtk-display ignore: passed
linux-app/qt-display create card: passed
linux-app/qt-display edit card: passed
linux-app/qt-display exchange contact: passed
linux-app/qt-display receive update: passed
linux-app/qt-display ignore: passed
cli create card: passed
cli edit card: passed
cli exchange contact: passed
cli receive update: passed
cli ignore: passed
tui create card: passed
tui edit card: passed
tui exchange contact: passed
tui receive update: passed
tui ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
in-person local-only no-relay run: passed
offline mode blocks ohttp+relay: passed
real-device in-person ble exchange: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
default online sync via ohttp+relay: passed
in-person to ohttp+relay channel change: passed
ohttp+relay to in-person channel change: passed
alternating channel updates: passed
both privacy hops: passed
ohttp relay: passed
application relay: passed
exchange propagation: passed
update propagation: passed
exact-value assertions: passed
blocking e2e pipeline: passed
""",
            six_device_convergence_evidence="""
# Six-device convergence evidence

six-device topology: passed
alice devices: a1, a2, a3
bob devices: b1, b2, b3
three linked devices per user: passed
socket-backed topology: passed
real link ceremony: passed
convergence at every target: passed
reorder and duplicate handling: passed
simultaneous edits: passed
offline catch-up: passed
relay restart during delivery: passed
device revocation: passed
device replacement: passed
clock skew: passed
""",
            every_linked_device_evidence="""
# Every linked device exchange evidence

active linked devices: a1, a2, a3, b1, b2, b3
exchange from every active device: passed
update from every active device: passed
secondary device initiation: passed
third device initiation: passed
independent per-device ratchet sessions: passed
nine-pair ratchet matrix: passed
sender-token wire inspection: passed
bob-originated updates: passed
""",
            selectable_exchange_evidence="""
# Selectable exchange-mode acceptance evidence

selectable exchange modes: passed
functionality: passed
latency: accepted
enjoyment: accepted
accessibility: passed
cancellation: passed
retry: passed
recovery: passed
""",
            long_lived_contact_evidence="""
# Long-lived contact continuity evidence

long-lived contact continuity: passed
channel-independent updates: passed
composite longitudinal scenario: passed
clock-driven scenario: passed
exchange remains useful: passed
permitted detail changes: passed
offline catch-up: passed
device add/revoke/replace: passed
archive/unarchive: passed
block behavior: passed
ignore semantics: accepted
ignored relationship behavior: passed
no re-exchange required: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-14 production distribution evidence failure", result.stdout)
        self.assertIn("production-distribution.md is missing", result.stdout)

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
            certification_evidence=fresh_report(),
            plan=plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria="""
**Ship criteria**

| Criterion | Required state | Classification |
|-----------|----------------|----------------|
| Release gates RG-1 through RG-16 | complete | hard |
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
            humble_todo_count=0,
            usability_evidence="""
# First-release unassisted usability sessions

representative users: yes
unassisted central journey: yes
approved study protocol: yes

## Sessions

- Session 1: completed central journey without assistance.
- Session 2: completed central journey without assistance.
- Session 3: completed central journey without assistance.
""",
            accessibility_evidence="""
# Native frontend accessibility acceptance

supported native frontends: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display
android accessibility acceptance: passed
ios accessibility acceptance: passed
macos accessibility acceptance: passed
windows accessibility acceptance: passed
linux-app/gtk-display accessibility acceptance: passed
linux-app/qt-display accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
            privacy_evidence="""
# Service-boundary no-decryptability evidence

relay storage: inspected
ohttp relay storage: inspected
logs: inspected
metrics: inspected
traces: inspected
configuration: inspected
service-held secrets: inspected
plaintext/key access: none
""",
            ohttp_fail_closed_evidence="""
# OHTTP fail-closed evidence

supported production consumers: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

android create card: passed
android edit card: passed
android exchange contact: passed
android receive update: passed
android ignore: passed
ios create card: passed
ios edit card: passed
ios exchange contact: passed
ios receive update: passed
ios ignore: passed
macos create card: passed
macos edit card: passed
macos exchange contact: passed
macos receive update: passed
macos ignore: passed
windows create card: passed
windows edit card: passed
windows exchange contact: passed
windows receive update: passed
windows ignore: passed
linux-app/gtk-display create card: passed
linux-app/gtk-display edit card: passed
linux-app/gtk-display exchange contact: passed
linux-app/gtk-display receive update: passed
linux-app/gtk-display ignore: passed
linux-app/qt-display create card: passed
linux-app/qt-display edit card: passed
linux-app/qt-display exchange contact: passed
linux-app/qt-display receive update: passed
linux-app/qt-display ignore: passed
cli create card: passed
cli edit card: passed
cli exchange contact: passed
cli receive update: passed
cli ignore: passed
tui create card: passed
tui edit card: passed
tui exchange contact: passed
tui receive update: passed
tui ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
in-person local-only no-relay run: passed
offline mode blocks ohttp+relay: passed
real-device in-person ble exchange: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
default online sync via ohttp+relay: passed
in-person to ohttp+relay channel change: passed
ohttp+relay to in-person channel change: passed
alternating channel updates: passed
both privacy hops: passed
ohttp relay: passed
application relay: passed
exchange propagation: passed
update propagation: passed
exact-value assertions: passed
blocking e2e pipeline: passed
""",
            six_device_convergence_evidence="""
# Six-device convergence evidence

six-device topology: passed
alice devices: a1, a2, a3
bob devices: b1, b2, b3
three linked devices per user: passed
socket-backed topology: passed
real link ceremony: passed
convergence at every target: passed
reorder and duplicate handling: passed
simultaneous edits: passed
offline catch-up: passed
relay restart during delivery: passed
device revocation: passed
device replacement: passed
clock skew: passed
""",
            every_linked_device_evidence="""
# Every linked device exchange evidence

active linked devices: a1, a2, a3, b1, b2, b3
exchange from every active device: passed
update from every active device: passed
secondary device initiation: passed
third device initiation: passed
independent per-device ratchet sessions: passed
nine-pair ratchet matrix: passed
sender-token wire inspection: passed
bob-originated updates: passed
""",
            selectable_exchange_evidence="""
# Selectable exchange-mode acceptance evidence

selectable exchange modes: passed
functionality: passed
latency: accepted
enjoyment: accepted
accessibility: passed
cancellation: passed
retry: passed
recovery: passed
""",
            long_lived_contact_evidence="""
# Long-lived contact continuity evidence

long-lived contact continuity: passed
channel-independent updates: passed
composite longitudinal scenario: passed
clock-driven scenario: passed
exchange remains useful: passed
permitted detail changes: passed
offline catch-up: passed
device add/revoke/replace: passed
archive/unarchive: passed
block behavior: passed
ignore semantics: accepted
ignored relationship behavior: passed
no re-exchange required: passed
""",
            production_distribution_evidence="""
# Production distribution evidence

core binding tag: v0.55.2
supported platforms: android, ios, macos, windows, linux-app/gtk-display, linux-app/qt-display, cli, tui
android signing: passed
android packaging: passed
android installation: passed
android distribution-channel acceptance: passed
android store submission: passed
ios signing: passed
ios packaging: passed
ios installation: passed
ios distribution-channel acceptance: passed
ios store submission: passed
ios notarization: passed
macos signing: passed
macos packaging: passed
macos installation: passed
macos distribution-channel acceptance: passed
macos notarization: passed
windows signing: passed
windows packaging: passed
windows installation: passed
windows distribution-channel acceptance: passed
linux-app/gtk-display signing: passed
linux-app/gtk-display packaging: passed
linux-app/gtk-display installation: passed
linux-app/gtk-display distribution-channel acceptance: passed
linux-app/qt-display signing: passed
linux-app/qt-display packaging: passed
linux-app/qt-display installation: passed
linux-app/qt-display distribution-channel acceptance: passed
cli signing: passed
cli packaging: passed
cli installation: passed
cli distribution-channel acceptance: passed
tui signing: passed
tui packaging: passed
tui installation: passed
tui distribution-channel acceptance: passed
""",
            user_data_convergence_evidence="""
# User data convergence evidence

core binding tag: v0.55.2
user data convergence: passed
complete owner-private state convergence: passed
myinfo update/removal: passed
presentation cards: passed
group identity/membership/visibility/overrides: passed
tag change/deletion: passed
contacts/private notes: passed
all six devices synchronized: passed
canonical owner-private state: passed
permitted presentation state only: passed
no private state leaked to Bob or relay: passed
ADR-020 deterministic convergence: passed
""",
        )

        self.assertEqual(0, result.returncode)
        self.assertIn("HARD SHIP CRITERIA (2/2 done)", result.stdout)
        self.assertIn("All hard gates passed", result.stdout)


    def test_completed_rg1_requires_per_consumer_journey_results(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            # Only android completed its journey matrix; every other
            # consumer's rows must be reported individually.
            frontend_journey_evidence="""
# Core user journey evidence

android create card: passed
android edit card: passed
android exchange contact: passed
android receive update: passed
android ignore: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-1 frontend journey evidence failure", result.stdout)
        self.assertIn("ios create card: passed evidence is missing", result.stdout)
        self.assertIn("tui ignore: passed evidence is missing", result.stdout)
        self.assertNotIn("android create card: passed evidence is missing", result.stdout)

    def test_completed_rg12_requires_per_frontend_accessibility_pass(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            # Only android has a pass row; every other frontend's missing
            # pass must be reported individually.
            accessibility_evidence="""
# Native frontend accessibility acceptance

android accessibility acceptance: passed
physical screen-reader walkthroughs: complete
blocking accessibility defects: zero
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-12 accessibility evidence failure", result.stdout)
        self.assertIn(
            "ios accessibility acceptance: passed evidence is missing",
            result.stdout,
        )
        self.assertIn(
            "linux-app/qt-display accessibility acceptance: passed evidence is missing",
            result.stdout,
        )
        self.assertNotIn(
            "android accessibility acceptance: passed evidence is missing",
            result.stdout,
        )

    def test_completed_rg14_requires_per_consumer_distribution_results(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            core_tags=["v0.55.2"],
            # Only android completed its distribution rows (including its
            # store submission); every other consumer's rows must be
            # reported individually.
            production_distribution_evidence="""
# Production distribution evidence

android signing: passed
android packaging: passed
android installation: passed
android distribution-channel acceptance: passed
android store submission: passed
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-14 production distribution evidence failure", result.stdout)
        self.assertIn("ios signing: passed evidence is missing", result.stdout)
        self.assertIn("tui packaging: passed evidence is missing", result.stdout)
        self.assertIn(
            "ios store submission: passed evidence is missing", result.stdout
        )
        self.assertIn("ios notarization: passed evidence is missing", result.stdout)
        self.assertIn("macos notarization: passed evidence is missing", result.stdout)
        # A complete consumer produces no rows; store submission applies only
        # to the P0 store platforms, notarization only to Apple.
        self.assertNotIn("android signing: passed evidence is missing", result.stdout)
        self.assertNotIn("android store submission: passed", result.stdout)
        self.assertNotIn("macos store submission: passed", result.stdout)
        self.assertNotIn("windows store submission: passed", result.stdout)
        self.assertNotIn("android notarization: passed", result.stdout)
        self.assertNotIn("cli notarization: passed", result.stdout)

    def test_completed_rg11_counts_web_demo_humble_todos(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            humble_todo_count=0,
            web_demo_todo_count=2,
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-11 Humble UI evidence failure", result.stdout)
        self.assertIn("2 TODO(HUMBLE) site(s) remain", result.stdout)

    def test_completed_rg11_counts_windows_display_humble_todos(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            humble_todo_count=0,
            windows_display_todo_count=3,
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-11 Humble UI evidence failure", result.stdout)
        self.assertIn("3 TODO(HUMBLE) site(s) remain", result.stdout)

    def test_completed_rg11_requires_zero_humble_ratchet_debt(self) -> None:
        result = self.run_release_gates(
            plan_with_gates(
                all_completed=True,
                status_line="All hard gates passed.",
                ship_criteria=CHECKED_SHIP_CRITERIA,
                extra_body="ADR-065 defines Protocol v2 finalization.",
            ),
            humble_todo_count=0,
            humble_release_zero_exit=1,
            humble_release_zero_output=(
                "android.domain_component: live=4, baseline=4"
            ),
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-11 Humble UI evidence failure", result.stdout)
        self.assertIn(
            "android.domain_component: live=4, baseline=4",
            result.stdout,
        )

    def test_release_prod_runs_release_gates_before_prompting(self) -> None:
        justfile_text = JUSTFILE.read_text(encoding="utf-8")
        recipe = justfile_text.split('release-prod repo="core":', 1)[1]
        recipe = recipe.split("# Show version promotion history", 1)[0]

        self.assertIn("just release-gates", recipe)
        self.assertLess(recipe.index("just release-gates"), recipe.index("read -p"))

    def test_release_gate_runner_installs_deploy_check_dependencies(self) -> None:
        ci_config = (JUSTFILE.parent / ".gitlab-ci.yml").read_text(encoding="utf-8")
        release_gate_job = ci_config.split("test:release-gates:", 1)[1]
        release_gate_job = release_gate_job.split("\nlint:dx-gates:", 1)[0]

        self.assertIn(
            "apk add --no-cache bash git jq just python3",
            release_gate_job,
        )

    def test_pipeline_wait_uses_aggregate_pipeline_state(self) -> None:
        gitlab_recipes = (JUSTFILE.parent / "just/gitlab.just").read_text(encoding="utf-8")
        recipe = gitlab_recipes.split("pipeline-wait repo='':", 1)[1]
        recipe = recipe.split("# Retry failed jobs", 1)[0]

        # The pipeline's own status decides, never a job line in the output
        # (one green job read as a passed pipeline). Behaviour is covered by
        # test_gitlab_pipeline_status_recipe.py (private#1179).
        self.assertIn('pipeline=$(just gitlab _branch-pipeline', recipe)
        self.assertIn('case "$3" in', recipe)
        self.assertNotIn('grep -qiE "passed|success"', recipe)

    def test_ci_classifier_passes_gitlab_failure_reason(self) -> None:
        gitlab_recipes = (JUSTFILE.parent / "just/gitlab.just").read_text(encoding="utf-8")
        recipe = gitlab_recipes.split("ci-classify repo job_id:", 1)[1]
        recipe = recipe.split("# Show pipeline status", 1)[0]

        self.assertIn('jobs/{{job_id}}" | jq -r ".failure_reason // empty"', recipe)
        self.assertIn('--failure-reason "$failure_reason"', recipe)

    def test_pipeline_email_recipe_is_failure_only_and_verified(self) -> None:
        gitlab_recipes = (JUSTFILE.parent / "just/gitlab.just").read_text(encoding="utf-8")
        recipe = gitlab_recipes.split(
            "pipeline-email-enable repo recipient:",
            1,
        )[1]
        recipe = recipe.split("# Disable pipeline failure emails", 1)[0]

        self.assertIn("integrations/pipelines-email", recipe)
        self.assertIn("notify_only_broken_pipelines=true", recipe)
        self.assertIn("branches_to_be_notified=default", recipe)
        self.assertIn("pipeline_events=true", recipe)
        self.assertIn("recipients", recipe)
        self.assertIn("glab api", recipe)
        self.assertIn("jq -e", recipe)


if __name__ == "__main__":
    unittest.main()
