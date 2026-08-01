# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""A tool on PATH that cannot run is not a tool that is present.

`cargo` is a rustup shim: with no default toolchain it resolves on PATH
but exits 1 on `--version`. The check reported `✓ cargo — (installed)`
and setup continued to `✓ All required tools present`, then failed three
`cargo update` calls further down (2026-08-01).
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PREREQUISITES_SCRIPT = Path(sys.argv.pop(1)).resolve()

REQUIRED = ("git", "rustup", "cargo", "rustc", "just")


class CheckPrerequisitesTest(unittest.TestCase):
    def make_tool(self, directory: Path, name: str, *, runnable: bool) -> None:
        path = directory / name
        if runnable:
            body = f'#!/bin/sh\necho "{name} 1.2.3"\n'
        else:
            # Mirrors the rustup shim: resolvable, but broken on invocation.
            body = (
                "#!/bin/sh\n"
                'echo "error: no default toolchain configured" >&2\n'
                "exit 1\n"
            )
        path.write_text(body)
        path.chmod(0o755)

    def run_check(self, broken: tuple[str, ...] = ()) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            bindir = root / "bin"
            bindir.mkdir()
            for tool in REQUIRED:
                self.make_tool(bindir, tool, runnable=tool not in broken)
            environment = dict(os.environ)
            # A real ~/.cargo/bin would be prepended by the script and
            # shadow the stubs, so point HOME at an empty directory.
            environment["HOME"] = str(root / "home")
            environment["PATH"] = f"{bindir}:/usr/bin:/bin"
            return subprocess.run(
                ["bash", str(PREREQUISITES_SCRIPT)],
                capture_output=True,
                text=True,
                env=environment,
            )

    def test_runnable_required_tools_pass(self) -> None:
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("✓ cargo", result.stdout)

    def test_broken_required_tool_fails_the_check(self) -> None:
        result = self.run_check(broken=("cargo",))
        self.assertEqual(result.returncode, 1, result.stdout)

    def test_broken_required_tool_is_not_reported_as_present(self) -> None:
        result = self.run_check(broken=("cargo",))
        self.assertNotIn("✓ cargo", result.stdout)
        self.assertNotIn("All required tools present", result.stdout)

    def test_broken_required_tool_is_named_in_the_output(self) -> None:
        result = self.run_check(broken=("cargo",))
        cargo_lines = [
            line for line in result.stdout.splitlines() if "cargo —" in line
        ]
        self.assertTrue(cargo_lines, result.stdout)
        self.assertRegex(cargo_lines[0], r"cargo — .*(not runnable|BROKEN)")

    def test_broken_rust_shim_hints_at_rustup(self) -> None:
        result = self.run_check(broken=("cargo",))
        self.assertIn("rustup default", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
