# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
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
        humble_todo_count: int | None = None,
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
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workspace = Path(temporary_directory)
            env = os.environ.copy()
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
                tag_list = workspace / "core-tags.txt"
                tag_list.write_text("\n".join(core_tags))
                fake_bin = workspace / "bin"
                fake_bin.mkdir()
                fake_git = fake_bin / "git"
                fake_git.write_text(
                    "\n".join(
                        [
                            "#!/bin/sh",
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
                )
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
                )
            if usability_evidence is not None:
                usability_path = (
                    workspace
                    / "_private/docs/testing/usability/"
                    "first-release-unassisted-sessions.md"
                )
                usability_path.parent.mkdir(parents=True)
                usability_path.write_text(usability_evidence)
            if accessibility_evidence is not None:
                accessibility_path = (
                    workspace
                    / "_private/docs/testing/accessibility/"
                    "native-frontend-acceptance.md"
                )
                accessibility_path.parent.mkdir(parents=True)
                accessibility_path.write_text(accessibility_evidence)
            if privacy_evidence is not None:
                privacy_path = (
                    workspace
                    / "_private/docs/testing/privacy/"
                    "service-boundary-no-decryptability.md"
                )
                privacy_path.parent.mkdir(parents=True)
                privacy_path.write_text(privacy_evidence)
            if ohttp_fail_closed_evidence is not None:
                ohttp_path = (
                    workspace
                    / "_private/docs/testing/privacy/"
                    "ohttp-fail-closed.md"
                )
                ohttp_path.parent.mkdir(parents=True, exist_ok=True)
                ohttp_path.write_text(ohttp_fail_closed_evidence)
            if frontend_journey_evidence is not None:
                journey_path = (
                    workspace
                    / "_private/docs/testing/frontend/"
                    "core-user-journey.md"
                )
                journey_path.parent.mkdir(parents=True)
                journey_path.write_text(frontend_journey_evidence)
            if local_two_user_evidence is not None:
                local_two_user_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "local-two-user-propagation.md"
                )
                local_two_user_path.parent.mkdir(parents=True)
                local_two_user_path.write_text(local_two_user_evidence)
            if ohttp_relay_two_user_evidence is not None:
                ohttp_relay_two_user_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "ohttp-relay-two-user-propagation.md"
                )
                ohttp_relay_two_user_path.parent.mkdir(parents=True, exist_ok=True)
                ohttp_relay_two_user_path.write_text(ohttp_relay_two_user_evidence)
            if six_device_convergence_evidence is not None:
                six_device_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "six-device-convergence.md"
                )
                six_device_path.parent.mkdir(parents=True, exist_ok=True)
                six_device_path.write_text(six_device_convergence_evidence)
            if every_linked_device_evidence is not None:
                every_device_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "every-linked-device-exchange.md"
                )
                every_device_path.parent.mkdir(parents=True, exist_ok=True)
                every_device_path.write_text(every_linked_device_evidence)
            if selectable_exchange_evidence is not None:
                selectable_exchange_path = (
                    workspace
                    / "_private/docs/testing/usability/"
                    "selectable-exchange-mode-acceptance.md"
                )
                selectable_exchange_path.parent.mkdir(parents=True, exist_ok=True)
                selectable_exchange_path.write_text(selectable_exchange_evidence)
            if long_lived_contact_evidence is not None:
                long_lived_contact_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "long-lived-contact-continuity.md"
                )
                long_lived_contact_path.parent.mkdir(parents=True, exist_ok=True)
                long_lived_contact_path.write_text(long_lived_contact_evidence)
            if production_distribution_evidence is not None:
                production_distribution_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "production-distribution.md"
                )
                production_distribution_path.parent.mkdir(parents=True, exist_ok=True)
                production_distribution_path.write_text(production_distribution_evidence)
            if user_data_convergence_evidence is not None:
                user_data_convergence_path = (
                    workspace
                    / "_private/docs/testing/release/"
                    "user-data-convergence.md"
                )
                user_data_convergence_path.parent.mkdir(parents=True, exist_ok=True)
                user_data_convergence_path.write_text(user_data_convergence_evidence)
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
                env=env,
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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported production consumers: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

supported frontends: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
create card: passed
edit card: passed
exchange contact: passed
receive update: passed
block or ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
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
supported platforms: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
signing: passed
packaging: passed
installation: passed
store submission: passed
notarization: passed
distribution-channel acceptance: passed
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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported production consumers: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported production consumers: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

supported frontends: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
create card: passed
edit card: passed
exchange contact: passed
receive update: passed
block or ignore: passed
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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported production consumers: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

supported frontends: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
create card: passed
edit card: passed
exchange contact: passed
receive update: passed
block or ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported production consumers: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

supported frontends: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
create card: passed
edit card: passed
exchange contact: passed
receive update: passed
block or ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported production consumers: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

supported frontends: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
create card: passed
edit card: passed
exchange contact: passed
receive update: passed
block or ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
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
""",
        )

        self.assertEqual(1, result.returncode)
        self.assertIn("RG-5 every-linked-device evidence failure", result.stdout)
        self.assertIn("every-linked-device-exchange.md is missing", result.stdout)

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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported production consumers: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

supported frontends: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
create card: passed
edit card: passed
exchange contact: passed
receive update: passed
block or ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported production consumers: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

supported frontends: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
create card: passed
edit card: passed
exchange contact: passed
receive update: passed
block or ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported production consumers: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

supported frontends: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
create card: passed
edit card: passed
exchange contact: passed
receive update: passed
block or ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
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

supported native frontends: android, ios, macos, windows, linux-gtk, linux-qt
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

supported production consumers: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
plaintext path: fails closed
tls-only path: fails closed
direct path: fails closed
bootstrap path: fails closed
reachability-probe path: fails closed
no bypass: verified
""",
            frontend_journey_evidence="""
# Core user journey evidence

supported frontends: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
create card: passed
edit card: passed
exchange contact: passed
receive update: passed
block or ignore: passed
""",
            local_two_user_evidence="""
# Local two-user propagation evidence

local two-user: passed
representative two-device run: passed
mutual exchange: passed
update propagation: passed
exact-value assertions: passed
""",
            ohttp_relay_two_user_evidence="""
# OHTTP relay two-user propagation evidence

split-ohttp two-user: passed
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
supported platforms: android, ios, macos, windows, linux-gtk, linux-qt, cli, tui
signing: passed
packaging: passed
installation: passed
store submission: passed
notarization: passed
distribution-channel acceptance: passed
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


if __name__ == "__main__":
    unittest.main()
