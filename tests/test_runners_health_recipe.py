# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


RUNNERS_JUST = Path(sys.argv.pop(1)).resolve()
JUST = shutil.which("just")

FLEET = ["allyson-shell", "allyson-docker", "nell-shell", "shelly-ann-arm64", "pam-shell"]


def group_listing(names: list[str]) -> str:
    entries = ",".join(
        f'{{"id":{900 + index},"description":"{name}"}}' for index, name in enumerate(names)
    )
    return f"[{entries}]"


# An idle runner keeps polling, but GitLab.com does not refresh contacted_at
# for polls that find nothing new, so it ages past minutes while GitLab still
# reports the runner online (pam and shelly-ann, 2026-10-12, private#10).
ONLINE_AND_IDLE = (
    '{"contacted_at":"2026-10-09T17:00:00.000Z","status":"online","active":true,"paused":false}'
)
OFFLINE = '{"contacted_at":"2026-10-09T17:00:00.000Z","status":"offline","active":true,"paused":false}'


class RunnersHealthRecipeTests(unittest.TestCase):
    @staticmethod
    def write_executable(path: Path, lines: list[str]) -> None:
        path.write_text("\n".join([*lines, ""]))
        path.chmod(0o755)

    def run_recipe(
        self, registered: list[str], runner: str = ONLINE_AND_IDLE
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            workspace = Path(temporary_directory)
            shutil.copy2(RUNNERS_JUST, workspace / "runners.just")
            (workspace / "justfile").write_text(
                "\n".join(
                    [
                        'set shell := ["bash", "-cu"]',
                        'set script-interpreter := ["bash", "-eu"]',
                        "import 'runners.just'",
                        "",
                    ]
                )
            )

            fake_bin = workspace / "bin"
            fake_bin.mkdir()
            self.write_executable(fake_bin / "just", ["#!/bin/sh", "exit 0"])
            # Runner IDs change on every re-registration, so the fake GitLab
            # hands out IDs the recipe cannot have hardcoded: only a lookup by
            # name reaches them.
            self.write_executable(
                fake_bin / "glab",
                [
                    "#!/bin/sh",
                    'case "$*" in',
                    '  *"groups/vauchi/runners"*)',
                    '    printf "%s\\n" "$RUNNERS_HEALTH_TEST_GROUP"',
                    "    ;;",
                    '  *"runners/9"[0-9][0-9]*)',
                    '    printf "%s\\n" "$RUNNERS_HEALTH_TEST_RUNNER"',
                    "    ;;",
                    "  *)",
                    "    printf '{\"message\":\"404 Not found\"}\\n'",
                    "    exit 1",
                    "    ;;",
                    "esac",
                ],
            )

            environment = os.environ.copy()
            environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
            environment["RUNNERS_HEALTH_READ_TOKEN"] = "test-token"
            environment["RUNNERS_HEALTH_TEST_GROUP"] = group_listing(registered)
            environment["RUNNERS_HEALTH_TEST_RUNNER"] = runner
            environment.pop("BW_SESSION", None)
            return subprocess.run(
                [JUST, "--justfile", str(workspace / "justfile"), "runners-health"],
                cwd=workspace,
                env=environment,
                capture_output=True,
                text=True,
                timeout=60,
            )

    @staticmethod
    def status_line(output: str, name: str) -> str:
        return next((line for line in output.splitlines() if line.startswith(name + " ")), "")

    def test_runners_are_found_by_name_not_by_hardcoded_id(self) -> None:
        result = self.run_recipe(FLEET)

        for name in FLEET:
            line = self.status_line(result.stdout, name)
            self.assertTrue(line, f"no status line for {name}:\n{result.stdout}{result.stderr}")
            self.assertNotIn("ERROR", line)
            self.assertNotIn("MISSING", line)

    def test_a_runner_absent_from_gitlab_is_reported_missing(self) -> None:
        result = self.run_recipe([name for name in FLEET if name != "pam-shell"])

        self.assertIn("MISSING", self.status_line(result.stdout, "pam-shell"), result.stdout)
        self.assertNotEqual(result.returncode, 0)

    def test_host_column_is_the_name_without_its_role_suffix(self) -> None:
        result = self.run_recipe(FLEET)

        self.assertRegex(self.status_line(result.stdout, "shelly-ann-arm64"), r"^shelly-ann-arm64\s+shelly-ann\s")
        self.assertRegex(self.status_line(result.stdout, "allyson-docker"), r"^allyson-docker\s+allyson\s")

    def test_an_idle_runner_gitlab_reports_online_is_healthy(self) -> None:
        result = self.run_recipe(FLEET, ONLINE_AND_IDLE)

        for name in FLEET:
            self.assertRegex(self.status_line(result.stdout, name), rf"^{name}\s+\S+\s+OK\s", result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_runner_gitlab_reports_offline_is_dead(self) -> None:
        result = self.run_recipe(FLEET, OFFLINE)

        self.assertRegex(self.status_line(result.stdout, "pam-shell"), r"^pam-shell\s+pam\s+DEAD\s", result.stdout)
        self.assertNotEqual(result.returncode, 0)

    def test_recipe_holds_no_runner_ids(self) -> None:
        recipe = RUNNERS_JUST.read_text()

        self.assertIsNone(re.search(r"\b5\d{7}:", recipe), "runner IDs are hardcoded again")


if __name__ == "__main__":
    unittest.main()
