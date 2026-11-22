# SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
# SPDX-License-Identifier: GPL-3.0-or-later

"""`just bump-core` must move every workspace constraint to the new version.

Core's `[workspace.dependencies]` pins each path member with a version, and
Cargo refuses to resolve a member whose constraint excludes the new workspace
version. The recipe kept its own list of three crates; the fourth,
vauchi-core-testkit, was missed in the 0.107.0 and 0.108.0 releases and had to
be set by hand both times (vauchi/private#1304).

The test copies the real justfile into a throwaway workspace whose Core holds
four path members, puts a `cargo` stub on PATH that records its arguments, and
runs the recipe.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

WORKSPACE_ROOT = Path(sys.argv.pop(1)).resolve()

CARGO_TOML = """[workspace]
members = ["vauchi-core", "vauchi-app", "vauchi-protocol", "vauchi-core-testkit"]

[workspace.package]
version = "0.1.0"

[workspace.dependencies]
vauchi-core = { path = "vauchi-core", version = "0.1.0", default-features = false }
vauchi-app = { path = "vauchi-app", version = "0.1.0", default-features = false }
vauchi-protocol = { path = "vauchi-protocol", version = "0.1.0" }
vauchi-core-testkit = { path = "vauchi-core-testkit", version = "0.1.0" }
serde = { version = "1.0.0", features = ["derive"] }
"""

CARGO_STUB = """#!/bin/sh
printf '%s\\n' "$*" >> "$CARGO_CALLS"
"""


class BumpCoreRecipeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.workspace = self.tmp / "vauchi"
        (self.workspace / "core").mkdir(parents=True)
        shutil.copyfile(WORKSPACE_ROOT / "justfile", self.workspace / "justfile")
        shutil.copytree(WORKSPACE_ROOT / "just", self.workspace / "just")
        (self.workspace / "core" / "Cargo.toml").write_text(CARGO_TOML, encoding="utf-8")
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        stub = self.bin / "cargo"
        stub.write_text(CARGO_STUB, encoding="utf-8")
        stub.chmod(0o755)
        self.calls = self.tmp / "cargo-calls"

    def bump(self, version: str) -> subprocess.CompletedProcess[str]:
        environment = {
            **os.environ,
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "CARGO_CALLS": str(self.calls),
        }
        return subprocess.run(
            ["just", "--justfile", str(self.workspace / "justfile"), "bump-core", version],
            cwd=self.workspace, env=environment, capture_output=True, text=True,
        )

    def test_every_workspace_constraint_moves_to_the_new_version(self) -> None:
        result = self.bump("0.2.0")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        manifest = (self.workspace / "core" / "Cargo.toml").read_text(encoding="utf-8")
        for crate in ("vauchi-core", "vauchi-app", "vauchi-protocol", "vauchi-core-testkit"):
            line = next(l for l in manifest.splitlines() if l.startswith(f"{crate} = "))
            self.assertIn('version = "0.2.0"', line, f"{crate} stayed behind: {line}")
        self.assertIn('version = "0.2.0"\n\n[workspace.dependencies]', manifest)
        self.assertIn('serde = { version = "1.0.0"', manifest, "a registry dependency must not move")

    def test_the_lock_update_names_every_workspace_crate(self) -> None:
        result = self.bump("0.2.0")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        update = next(
            l for l in self.calls.read_text(encoding="utf-8").splitlines() if l.startswith("update ")
        )
        for crate in ("vauchi-core", "vauchi-app", "vauchi-protocol", "vauchi-core-testkit"):
            self.assertIn(f"-p {crate}", update)


if __name__ == "__main__":
    unittest.main()
