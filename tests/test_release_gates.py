# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

JUSTFILE = Path(sys.argv.pop(1)).resolve()


def plan_with_gates(completed_gate: int | None = None) -> str:
    gates = []
    for gate_number in range(1, 16):
        marker = "[x] " if gate_number == completed_gate else ""
        gates.append(f"   - {marker}RG-{gate_number} — Gate {gate_number} outcome.")
    return "\n".join(
        [
            "# Master Plan: Production Readiness",
            "",
            "**Status**",
            "",
            "All 15 release gates are open.",
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
    def run_release_gates(self, plan: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workspace = Path(temporary_directory)
            plan_path = workspace / "_private/docs/planning/master-plan.plan.md"
            plan_path.parent.mkdir(parents=True)
            plan_path.write_text(plan)
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
        self.assertIn("HARD GATES (0/15 done)", result.stdout)
        self.assertIn("15 HARD GATE(s) block release", result.stdout)

    def test_checked_rg_task_counts_as_done(self) -> None:
        result = self.run_release_gates(plan_with_gates(completed_gate=1))

        self.assertEqual(1, result.returncode)
        self.assertIn("HARD GATES (1/15 done)", result.stdout)
        self.assertIn("14 HARD GATE(s) block release", result.stdout)

    def test_empty_gate_parse_fails_loudly(self) -> None:
        result = self.run_release_gates("# Master Plan without release gates\n")

        self.assertNotEqual(0, result.returncode)
        self.assertIn("ERROR: no RG release gates found", result.stderr)


if __name__ == "__main__":
    unittest.main()
