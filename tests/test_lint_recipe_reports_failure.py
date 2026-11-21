# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""The `lint` recipe must report a failing checker, not just print it.

`run_step` (scripts/scripts/quiet-runner.sh) invokes each step function as
`"$@" || exit 1`. Bash exempts a command on the left of `||` — and everything
nested inside it — from `set -e`, so a failing checker does not abort the step
function. The function's exit status is then whatever its *last* statement
returns. When an arm ends in a repo-conditional `if` with no `else`, a false
condition yields 0 and the failure is discarded: `just lint tui` printed three
clippy errors and still exited 0.

These tests execute the real arm text out of the justfile with a failing
checker on PATH, so they go red if the fail-fast handling is removed.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

JUSTFILE = Path(sys.argv.pop(1)).resolve()

# Mirrors run_step's non-quiet branch: the step runs in a `||` context, which
# is what disables `set -e` inside it.
HARNESS = """
set -euo pipefail
r="{repo}"
tc="{toolchain}"
dir="$PWD"
quiet_enabled() {{ return 1; }}
_do_step() {{
    case "$tc" in
{arm}
        *) ;;
    esac
}}
_do_step && echo "STEP_REPORTED_SUCCESS" || echo "STEP_REPORTED_FAILURE"
"""


def lint_recipe_arm(toolchain: str) -> str:
    """Extract one `case` arm from the justfile's `lint` recipe verbatim."""
    text = JUSTFILE.read_text(encoding="utf-8")
    recipe = re.search(r"^lint \*args:\n(.*?)(?=^\S)", text, re.M | re.S)
    if recipe is None:
        raise AssertionError("could not locate the `lint` recipe in the justfile")

    arm = re.search(
        rf"^(\s*){re.escape(toolchain)}\)\n(.*?)^\1\s*;;\s*$",
        recipe.group(1),
        re.M | re.S,
    )
    if arm is None:
        raise AssertionError(f"could not locate the `{toolchain})` arm")
    return f"{arm.group(1)}{toolchain})\n{arm.group(2)}{arm.group(1)}    ;;"


class LintRecipeReportsFailureTest(unittest.TestCase):
    def run_arm(self, toolchain: str, repo: str, failing_tools: list[str]) -> str:
        with tempfile.TemporaryDirectory() as workspace:
            root = Path(workspace)
            stub_dir = root / "stub-bin"
            stub_dir.mkdir()
            for tool in failing_tools:
                stub = stub_dir / tool
                stub.write_text("#!/bin/sh\necho 'stub: check failed' >&2\nexit 1\n", encoding="utf-8")
                stub.chmod(0o755)

            # The arms also invoke repo guard scripts by relative path; stub
            # them as passing so the only failure is the checker under test.
            guards = root / "scripts" / "scripts"
            guards.mkdir(parents=True)
            for guard in Path(JUSTFILE.parent, "scripts", "scripts").glob("*.sh"):
                (guards / guard.name).write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                (guards / guard.name).chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{stub_dir}{os.pathsep}{environment['PATH']}"

            script = HARNESS.format(
                repo=repo,
                toolchain=toolchain,
                arm=lint_recipe_arm(toolchain),
            )
            result = subprocess.run(
                ["bash", "-c", script],
                cwd=root,
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )
            return result.stdout

    def test_rust_arm_reports_a_failing_clippy_for_a_non_core_repo(self) -> None:
        """`core` was protected only because its trailing `if` was true."""
        stdout = self.run_arm("rust", repo="tui", failing_tools=["cargo"])

        self.assertIn(
            "STEP_REPORTED_FAILURE",
            stdout,
            "clippy failed but the rust arm reported success — a non-core repo "
            "must not have its lint result discarded by a trailing conditional",
        )

    def test_xcode_arm_reports_a_failing_swiftlint_for_ios(self) -> None:
        """`macos` was protected only because its trailing `if` was true."""
        stdout = self.run_arm(
            "xcode", repo="ios", failing_tools=["swiftlint", "swiftformat"]
        )

        self.assertIn(
            "STEP_REPORTED_FAILURE",
            stdout,
            "swiftlint failed but the xcode arm reported success — ios must not "
            "have its lint result discarded by a trailing conditional",
        )


if __name__ == "__main__":
    unittest.main()
