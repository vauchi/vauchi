# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""A failed cargo sweep must not stop session-init reaching the issue queue."""

from pathlib import Path
import os
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SWEEP = ROOT / "just" / "sweep-targets.sh"
RECIPES = ROOT / "just" / "setup.just"

STUB_CARGO = """#!/usr/bin/env bash
# Stands in for `cargo sweep --time N <dir>`; the last argument is the repo.
for repo in "$@"; do :; done
printf '%s\\n' "$repo" >> "$SWEPT_LOG"
if [ "$repo" = "$FAILING_REPO" ]; then
    echo "Error: Failed to gather metadata for \\"$repo\\"" >&2
    echo "Caused by: key with no value" >&2
    exit 1
fi
"""


class SweepTargetsTests(unittest.TestCase):
    def sweep(self, repos: list[str], failing: str = "") -> tuple[subprocess.CompletedProcess, list[str]]:
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            stub_dir = workspace / "stub-bin"
            stub_dir.mkdir()
            cargo = stub_dir / "cargo"
            cargo.write_text(STUB_CARGO, encoding="utf-8")
            cargo.chmod(cargo.stat().st_mode | stat.S_IEXEC)
            for repo in repos:
                (workspace / repo / "target").mkdir(parents=True)
            swept_log = workspace / "swept.log"
            swept_log.touch()
            result = subprocess.run(
                ["bash", str(SWEEP), *repos],
                cwd=workspace,
                env={
                    **os.environ,
                    "PATH": f"{stub_dir}{os.pathsep}{os.environ['PATH']}",
                    "SWEPT_LOG": str(swept_log),
                    "FAILING_REPO": failing,
                },
                capture_output=True,
                text=True,
                check=False,
            )
            return result, swept_log.read_text(encoding="utf-8").split()

    def test_a_failing_repo_does_not_stop_the_repos_after_it(self) -> None:
        _, swept = self.sweep(["first", "broken", "last"], failing="broken")
        self.assertEqual(swept, ["first", "broken", "last"])

    def test_a_failing_repo_is_named_with_its_error(self) -> None:
        result, _ = self.sweep(["first", "broken", "last"], failing="broken")
        self.assertIn("WARNING: sweep failed in broken", result.stdout)
        self.assertIn('Failed to gather metadata for "broken"', result.stdout)

    def test_the_exit_status_reports_a_failure(self) -> None:
        result, _ = self.sweep(["first", "broken"], failing="broken")
        self.assertEqual(result.returncode, 1)

    def test_a_clean_sweep_exits_zero_and_warns_nothing(self) -> None:
        result, swept = self.sweep(["first", "last"])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(swept, ["first", "last"])
        self.assertNotIn("WARNING", result.stdout)

    def test_session_init_records_a_failed_sweep_as_a_warning_and_continues(self) -> None:
        recipes = RECIPES.read_text(encoding="utf-8")
        self.assertIn(
            'bash just/sweep-targets.sh $(repos_by_toolchain rust) || WARN=1',
            recipes,
        )


if __name__ == "__main__":
    unittest.main()
